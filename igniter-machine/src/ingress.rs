//! HTTP ingress front door for production capsule pools (LAB-MACHINE-SERVICE-HTTP-INGRESS-P6).
//!
//! The **inbound** edge — NOT the outbound HTTP effect executor (`http.rs`). A vendor webhook
//! arrives, the host validates the passport, routes to a production pool + `ServiceRecipe`, and
//! invokes the capsule (real activation: resume + dispatch), then maps the result to an HTTP
//! response and writes an audit fact:
//!
//! ```text
//! vendor webhook (HTTP request)
//!   -> ingress validates passport (before any activation)
//!   -> route → production pool + ServiceRecipe
//!   -> hub.invoke(passport, pool, body)  = real capsule activation
//!   -> map result → HTTP status/body
//!   -> audit fact (accepted or denied), with correlation id + idempotency
//! ```
//!
//! Local loopback ONLY: no public internet, no SparkCRM credentials, no outbound effect, no
//! agent messenger in the hot path (the ingress holds `&CoordinationHub` and only calls
//! `invoke` + `audit_ingress`).

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::coordination::{select_replica, CoordinationHub, DuplicatePolicy, PoolRefusal};
use crate::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

/// A parsed inbound webhook request.
pub struct IngressRequest {
    pub method: String,
    pub path: String,
    /// Header names are lower-cased.
    pub headers: HashMap<String, String>,
    pub body: Value,
}

impl IngressRequest {
    pub fn header(&self, k: &str) -> Option<&str> {
        self.headers.get(k).map(|s| s.as_str())
    }
    /// The bearer token from `Authorization: Bearer <token>`.
    pub fn bearer(&self) -> Option<&str> {
        self.header("authorization").and_then(|h| h.strip_prefix("Bearer "))
    }
}

pub struct IngressResponse {
    pub status: u16,
    pub body: Value,
    pub correlation_id: String,
}

/// Routes inbound paths to production pools and bearer tokens to vendor passports. (The
/// token→passport map is the auth layer; a real deployment would resolve credentials, P6 keeps
/// it explicit and local.)
#[derive(Default)]
pub struct IngressRouter {
    routes: HashMap<String, String>,
    tokens: HashMap<String, CapabilityPassport>,
    /// path → replica selection strategy (`"hash_key"` default | `"hash_key_attempt"` |
    /// `"round_robin"`). Hot-path serving selects ONE replica (P8 `select_replica`).
    strategies: HashMap<String, String>,
    /// round-robin sequence counter (interior mutable; deterministic + auditable).
    seq: AtomicU64,
}

/// What replica handled a served request — recorded by `audit_serve`.
struct ReplicaAudit {
    strategy: String,
    index: usize,
    count: usize,
    seed_digest: String,
}

/// The capability-IO effect side of the service→effect bridge (P10). The selected replica's
/// output becomes the effect payload; `run_write_effect` performs exactly ONE effect under the
/// HOST's `effect_passport` (distinct from the serving/vendor passport). The effect idempotency
/// key is `duplicate_key:attempt_index`, so the duplicate policy decides how many effects happen:
/// `dedup_strict` → one effect ever; `bounded_fresh(n)` → up to n distinct-keyed effects.
pub struct EffectBridgeConfig<'a> {
    pub registry: &'a CapabilityExecutorRegistry,
    pub receipts: &'a Arc<dyn TBackend>,
    pub effect_clock: &'a Arc<dyn ClockProvider>,
    pub effect_passport: &'a CapabilityPassport,
    pub capability_id: String,
    pub operation: String,
    pub scope: String,
}

fn map_effect_outcome(state: WriteState, result: &Value, detail: &Option<String>, correlation: &str) -> (u16, Value) {
    match state {
        WriteState::Committed => (200, json!({ "status": "committed", "result": result })),
        // accepted but external fate unknown → 202; resolve later via reconcile (P7/P13).
        WriteState::UnknownExternalState => (202, json!({ "status": "accepted_unknown", "correlation_id": correlation })),
        WriteState::Denied => (403, json!({ "status": "denied", "detail": detail })),
        WriteState::Retryable => (503, json!({ "status": "retry_later" })),
        WriteState::PermanentFailure => (502, json!({ "status": "failed", "detail": detail })),
        other => (500, json!({ "status": format!("{other:?}") })),
    }
}

impl IngressRouter {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn route(&mut self, path: &str, pool_id: &str) {
        self.routes.insert(path.to_string(), pool_id.to_string());
    }
    /// Route with an explicit replica selection strategy.
    pub fn route_with_strategy(&mut self, path: &str, pool_id: &str, strategy: &str) {
        self.routes.insert(path.to_string(), pool_id.to_string());
        self.strategies.insert(path.to_string(), strategy.to_string());
    }
    fn strategy(&self, path: &str) -> String {
        self.strategies.get(path).cloned().unwrap_or_else(|| "hash_key".to_string())
    }
    pub fn token(&mut self, token: &str, passport: CapabilityPassport) {
        self.tokens.insert(token.to_string(), passport);
    }

    /// Hot-path serving: select ONE replica deterministically (P8) and activate it. The seed is
    /// the duplicate key (stable routing), optionally with the attempt index, or a round-robin
    /// sequence — never random, never fanout (that stays a separate diagnostic API).
    async fn select_and_activate(
        &self,
        hub: &CoordinationHub,
        passport: &CapabilityPassport,
        route: &str,
        pool_id: &str,
        inputs: Value,
        dkey: &str,
        attempt: u32,
    ) -> (Result<Value, PoolRefusal>, ReplicaAudit) {
        let count = hub.replica_count(pool_id).await;
        let strategy = self.strategy(route);
        let seed = match strategy.as_str() {
            "round_robin" => self.seq.fetch_add(1, Ordering::SeqCst).to_string(),
            "hash_key_attempt" => format!("{}:{}", dkey, attempt),
            _ => dkey.to_string(), // hash_key (stable: same key → same replica)
        };
        let index = if count == 0 { 0 } else { select_replica(&strategy, count, &seed) };
        let result = hub.invoke_replica(passport, pool_id, inputs, index).await;
        let seed_digest = blake3::hash(seed.as_bytes()).to_hex().to_string();
        (result, ReplicaAudit { strategy, index, count, seed_digest })
    }

    async fn serve_one(
        &self,
        hub: &CoordinationHub,
        passport: &CapabilityPassport,
        route: &str,
        pool_id: &str,
        inputs: Value,
        dkey: &str,
        attempt: u32,
    ) -> (u16, Value, ReplicaAudit) {
        let (result, ra) = self.select_and_activate(hub, passport, route, pool_id, inputs, dkey, attempt).await;
        let (status, body) = match result {
            Ok(r) => (200, r),
            Err(e) => map_refusal(&e),
        };
        (status, body, ra)
    }

    /// Handle one inbound request: passport → route → invoke → HTTP response + audit.
    pub async fn handle(&self, hub: &CoordinationHub, req: &IngressRequest) -> IngressResponse {
        let correlation_id = req
            .header("x-correlation-id")
            .map(String::from)
            .unwrap_or_else(|| "cid-none".to_string());
        let idempotency = req.header("idempotency-key");

        // 1. passport required + verified BEFORE any activation.
        let passport = match req.bearer().and_then(|t| self.tokens.get(t)) {
            Some(p) => p,
            None => {
                let _ = hub
                    .audit_ingress("anonymous", &req.path, "denied", Some("missing/invalid passport"), &correlation_id, idempotency)
                    .await;
                return IngressResponse { status: 401, body: json!({"error": "unauthorized"}), correlation_id };
            }
        };

        // 2. route → production pool.
        let pool_id = match self.routes.get(&req.path) {
            Some(p) => p.clone(),
            None => {
                let _ = hub
                    .audit_ingress(&passport.subject, &req.path, "denied", Some("no route"), &correlation_id, idempotency)
                    .await;
                return IngressResponse { status: 404, body: json!({"error": "no route"}), correlation_id };
            }
        };

        // 3. resolve the service recipe (carries the optional business duplicate policy).
        let recipe = match hub.read_recipe(&pool_id).await {
            Some(r) => r,
            None => {
                let _ = hub
                    .audit_ingress(&passport.subject, &req.path, "denied", Some("no recipe"), &correlation_id, idempotency)
                    .await;
                return IngressResponse { status: 404, body: json!({"error": "not found"}), correlation_id };
            }
        };

        // 4. duplicate handling (business strategy on the recipe — NOT a canon default).
        if let Some(policy) = recipe.duplicate_policy.clone() {
            match req.header(&policy.key_header).map(String::from) {
                None if policy.require_key => {
                    let _ = hub
                        .audit_ingress(&passport.subject, &req.path, "denied", Some("missing duplicate key"), &correlation_id, idempotency)
                        .await;
                    return IngressResponse { status: 400, body: json!({"error": "missing duplicate key"}), correlation_id };
                }
                None => {} // key not required → fall through to a plain fresh invoke
                Some(dkey) => {
                    let payload_digest = body_digest(&req.body);
                    let history = hub.ingress_dedup_history(&req.path, &dkey).await;
                    let decision = decide_duplicate(&policy, &history, &payload_digest);
                    return self
                        .apply_duplicate(hub, passport, &req.path, &pool_id, &policy, &dkey, &payload_digest, &req.body, decision, &correlation_id, idempotency)
                        .await;
                }
            }
        }

        // 5. plain serve (no policy, or duplicate key not required and absent): select ONE
        //    replica deterministically (seed = correlation id) and activate it.
        let (status, body, ra) = self
            .serve_one(hub, passport, &req.path, &pool_id, req.body.clone(), &correlation_id, 0)
            .await;
        let _ = hub
            .audit_serve(&passport.subject, &pool_id, &ra.strategy, &ra.seed_digest, ra.index, ra.count, &correlation_id)
            .await;
        let outcome = if status < 400 { "allowed" } else { "denied" };
        let _ = hub
            .audit_ingress(&passport.subject, &req.path, outcome, None, &correlation_id, idempotency)
            .await;
        IngressResponse { status, body, correlation_id }
    }

    /// Service→effect bridge with duplicate policy + single-replica selection (P10). Combines
    /// P7 (duplicate policy) + P9 (one replica) + the capability-IO effect: the selected replica's
    /// output is performed as ONE declared effect (`run_write_effect`) under the host's effect
    /// passport. The effect idempotency key = `duplicate_key:attempt_index`, so the duplicate
    /// policy controls effect count: `dedup_strict` replays (NO second effect); `bounded_fresh(n)`
    /// makes up to n distinct-keyed effects. Fanout is never on this path.
    pub async fn handle_effect(
        &self,
        hub: &CoordinationHub,
        req: &IngressRequest,
        cfg: &EffectBridgeConfig<'_>,
    ) -> IngressResponse {
        let correlation_id = req.header("x-correlation-id").map(String::from).unwrap_or_else(|| "cid-none".to_string());
        let idem = req.header("idempotency-key");

        let passport = match req.bearer().and_then(|t| self.tokens.get(t)) {
            Some(p) => p,
            None => {
                let _ = hub.audit_ingress("anonymous", &req.path, "denied", Some("missing/invalid passport"), &correlation_id, idem).await;
                return IngressResponse { status: 401, body: json!({"error": "unauthorized"}), correlation_id };
            }
        };
        let pool_id = match self.routes.get(&req.path) {
            Some(p) => p.clone(),
            None => {
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("no route"), &correlation_id, idem).await;
                return IngressResponse { status: 404, body: json!({"error": "no route"}), correlation_id };
            }
        };
        let recipe = match hub.read_recipe(&pool_id).await {
            Some(r) => r,
            None => {
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("no recipe"), &correlation_id, idem).await;
                return IngressResponse { status: 404, body: json!({"error": "not found"}), correlation_id };
            }
        };
        // an effect bridge REQUIRES a duplicate policy + key — the key is the effect idempotency base.
        let policy = match recipe.duplicate_policy.clone() {
            Some(p) => p,
            None => {
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("effect bridge needs a duplicate policy"), &correlation_id, idem).await;
                return IngressResponse { status: 400, body: json!({"error": "no duplicate policy"}), correlation_id };
            }
        };
        let dkey = match req.header(&policy.key_header).map(String::from) {
            Some(k) => k,
            None => {
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("missing duplicate key"), &correlation_id, idem).await;
                return IngressResponse { status: 400, body: json!({"error": "missing duplicate key"}), correlation_id };
            }
        };

        let payload_digest = body_digest(&req.body);
        let history = hub.ingress_dedup_history(&req.path, &dkey).await;
        match decide_duplicate(&policy, &history, &payload_digest) {
            DuplicateDecision::Conflict => {
                let _ = hub.record_ingress_dedup(&req.path, &dkey, &payload_digest, 0, 409, &json!({"error": "conflict"}), "conflict", &correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("conflict"), &correlation_id, idem).await;
                IngressResponse { status: 409, body: json!({"error": "conflict"}), correlation_id }
            }
            DuplicateDecision::Denied => {
                let _ = hub.record_ingress_dedup(&req.path, &dkey, &payload_digest, 0, 429, &json!({"error": "duplicate limit reached"}), "denied", &correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("duplicate_limit"), &correlation_id, idem).await;
                IngressResponse { status: 429, body: json!({"error": "duplicate limit reached"}), correlation_id }
            }
            DuplicateDecision::Replay { status, response } => {
                // dedup replay → NO second effect.
                let _ = hub.record_ingress_dedup(&req.path, &dkey, &payload_digest, 0, status, &response, "replayed", &correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, &req.path, "replayed", Some("replayed_no_effect"), &correlation_id, idem).await;
                IngressResponse { status, body: response, correlation_id }
            }
            DuplicateDecision::Fresh { attempt_index } => {
                // 1. inject attempt, select ONE replica, activate → the effect INTENT.
                let mut inputs = req.body.clone();
                if let Some(obj) = inputs.as_object_mut() {
                    obj.insert(policy.seed_field.clone(), json!(attempt_index));
                }
                let (intent_res, ra) = self.select_and_activate(hub, passport, &req.path, &pool_id, inputs, &dkey, attempt_index).await;
                let _ = hub.audit_serve(&passport.subject, &pool_id, &ra.strategy, &ra.seed_digest, ra.index, ra.count, &correlation_id).await;
                let intent = match intent_res {
                    Ok(v) => v,
                    Err(e) => {
                        let (status, body) = map_refusal(&e);
                        let _ = hub.record_ingress_dedup(&req.path, &dkey, &payload_digest, attempt_index, status, &body, "denied", &correlation_id).await;
                        let _ = hub.audit_ingress(&passport.subject, &req.path, "denied", Some("activation refused"), &correlation_id, idem).await;
                        return IngressResponse { status, body, correlation_id };
                    }
                };

                // 2. perform EXACTLY ONE effect: idem key = duplicate_key:attempt → distinct per attempt.
                let effect_idem = format!("{}:{}", dkey, attempt_index);
                let write_req = WriteRequest {
                    capability_id: cfg.capability_id.clone(),
                    operation: cfg.operation.clone(),
                    idempotency_key: effect_idem.clone(),
                    payload: json!({ "intent": intent, "correlation_id": correlation_id }),
                };
                let (status, body, state_str) = match run_write_effect(cfg.registry, cfg.receipts, cfg.effect_clock, cfg.effect_passport, &cfg.scope, &write_req, RunMode::Live).await {
                    Ok(o) => {
                        let (s, b) = map_effect_outcome(o.state, &o.result, &o.detail, &correlation_id);
                        (s, b, format!("{:?}", o.state))
                    }
                    Err(_) => (500, json!({"error": "effect error"}), "Error".to_string()),
                };

                // 3. link correlation + attempt + replica + effect receipt id; record the response.
                let effect_receipt_id = format!("{}:{}", cfg.capability_id, effect_idem);
                let _ = hub.audit_bridge(&passport.subject, &pool_id, &correlation_id, attempt_index, ra.index, &effect_receipt_id, &state_str).await;
                let decision_str = if attempt_index == 0 { "accepted" } else { "fresh_duplicate" };
                let _ = hub.record_ingress_dedup(&req.path, &dkey, &payload_digest, attempt_index, status, &body, decision_str, &correlation_id).await;
                let outcome = if status < 400 { "allowed" } else { "denied" };
                let _ = hub.audit_ingress(&passport.subject, &req.path, outcome, Some(&format!("bridge:{}", state_str)), &correlation_id, idem).await;
                IngressResponse { status, body, correlation_id }
            }
        }
    }

    /// Apply a resolved duplicate `decision`: replay/conflict/deny without activation, or a fresh
    /// activation (injecting the deterministic `attempt_index` into the recipe's seed field so a
    /// service can mint a distinct response per duplicate). Records a dedup fact + ingress audit.
    #[allow(clippy::too_many_arguments)]
    async fn apply_duplicate(
        &self,
        hub: &CoordinationHub,
        passport: &CapabilityPassport,
        route: &str,
        pool_id: &str,
        policy: &DuplicatePolicy,
        dkey: &str,
        payload_digest: &str,
        body: &Value,
        decision: DuplicateDecision,
        correlation_id: &str,
        idempotency: Option<&str>,
    ) -> IngressResponse {
        match decision {
            DuplicateDecision::Conflict => {
                let _ = hub.record_ingress_dedup(route, dkey, payload_digest, 0, 409, &json!({"error": "conflict"}), "conflict", correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, route, "denied", Some(&format!("{}:conflict", policy.mode)), correlation_id, idempotency).await;
                IngressResponse { status: 409, body: json!({"error": "conflict"}), correlation_id: correlation_id.to_string() }
            }
            DuplicateDecision::Denied => {
                let _ = hub.record_ingress_dedup(route, dkey, payload_digest, 0, 429, &json!({"error": "duplicate limit reached"}), "denied", correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, route, "denied", Some(&format!("{}:denied", policy.mode)), correlation_id, idempotency).await;
                IngressResponse { status: 429, body: json!({"error": "duplicate limit reached"}), correlation_id: correlation_id.to_string() }
            }
            DuplicateDecision::Replay { status, response } => {
                // recorded response, NO re-activation.
                let _ = hub.record_ingress_dedup(route, dkey, payload_digest, 0, status, &response, "replayed", correlation_id).await;
                let _ = hub.audit_ingress(&passport.subject, route, "replayed", Some(&format!("{}:replayed", policy.mode)), correlation_id, idempotency).await;
                IngressResponse { status, body: response, correlation_id: correlation_id.to_string() }
            }
            DuplicateDecision::Fresh { attempt_index } => {
                // inject the deterministic attempt index into the invoke inputs, then serve ONE
                // replica (seed = duplicate key, optionally + attempt per the route strategy).
                let mut inputs = body.clone();
                if let Some(obj) = inputs.as_object_mut() {
                    obj.insert(policy.seed_field.clone(), json!(attempt_index));
                }
                let (status, resp, ra) = self.serve_one(hub, passport, route, pool_id, inputs, dkey, attempt_index).await;
                let _ = hub.audit_serve(&passport.subject, pool_id, &ra.strategy, &ra.seed_digest, ra.index, ra.count, correlation_id).await;
                let decision_str = if attempt_index == 0 { "accepted" } else { "fresh_duplicate" };
                let _ = hub.record_ingress_dedup(route, dkey, payload_digest, attempt_index, status, &resp, decision_str, correlation_id).await;
                let outcome = if status < 400 { "allowed" } else { "denied" };
                let _ = hub.audit_ingress(&passport.subject, route, outcome, Some(&format!("{}:{}#{}", policy.mode, decision_str, attempt_index)), correlation_id, idempotency).await;
                IngressResponse { status, body: resp, correlation_id: correlation_id.to_string() }
            }
        }
    }
}

fn body_digest(body: &Value) -> String {
    let s = serde_json::to_string(body).unwrap_or_default();
    blake3::hash(s.as_bytes()).to_hex().to_string()
}

/// The resolved duplicate decision for a `(route, duplicate_key)` under a policy.
#[derive(Debug)]
pub enum DuplicateDecision {
    /// Activate the service fresh (re-run) with this deterministic attempt index.
    Fresh { attempt_index: u32 },
    /// Return a previously-recorded response with NO re-activation.
    Replay { status: u16, response: Value },
    /// Same key, different payload (and variants not allowed) → conflict.
    Conflict,
    /// Past the bounded-fresh limit with an `after_limit` of deny.
    Denied,
}

/// Pure duplicate decision: given the policy, the dedup history (oldest first), and the current
/// payload digest. The safety invariant (same key + different payload → conflict) is checked
/// first unless the policy explicitly allows variant payloads.
pub fn decide_duplicate(
    policy: &DuplicatePolicy,
    history: &[Value],
    payload_digest: &str,
) -> DuplicateDecision {
    if !policy.variant_payload
        && history.iter().any(|h| h["payload_digest"].as_str() != Some(payload_digest))
    {
        return DuplicateDecision::Conflict;
    }
    let fresh: Vec<&Value> = history
        .iter()
        .filter(|h| matches!(h["decision"].as_str(), Some("accepted") | Some("fresh_duplicate")))
        .collect();
    let last_response = || -> Option<(u16, Value)> {
        fresh.last().map(|h| (h["status"].as_u64().unwrap_or(200) as u16, h["response"].clone()))
    };
    match policy.mode.as_str() {
        "dedup_strict" => match last_response() {
            Some((s, r)) => DuplicateDecision::Replay { status: s, response: r },
            None => DuplicateDecision::Fresh { attempt_index: 0 },
        },
        "treat_as_fresh" => DuplicateDecision::Fresh { attempt_index: fresh.len() as u32 },
        "bounded_fresh" => {
            if (fresh.len() as u32) < policy.max_fresh {
                DuplicateDecision::Fresh { attempt_index: fresh.len() as u32 }
            } else {
                match policy.after_limit.as_str() {
                    "deny" => DuplicateDecision::Denied,
                    _ => match last_response() {
                        Some((s, r)) => DuplicateDecision::Replay { status: s, response: r },
                        None => DuplicateDecision::Denied,
                    },
                }
            }
        }
        _ => DuplicateDecision::Fresh { attempt_index: fresh.len() as u32 },
    }
}

/// Map a coordination refusal to an HTTP status + body (public so the mapping is testable).
pub fn map_refusal(e: &PoolRefusal) -> (u16, Value) {
    match e {
        PoolRefusal::Unauthenticated(_) => (401, json!({"error": "unauthorized"})),
        PoolRefusal::NotGranted => (403, json!({"error": "forbidden"})),
        PoolRefusal::Invalid(m) if m.contains("not in production") => (404, json!({"error": "not found"})),
        PoolRefusal::Invalid(m) if m.contains("no accepted recipe") => (404, json!({"error": "not found"})),
        PoolRefusal::Invalid(m) if m.contains("digest mismatch") => (409, json!({"error": "conflict"})),
        PoolRefusal::Invalid(m) => (400, json!({"error": m})),
        _ => (403, json!({"error": "forbidden"})),
    }
}

// ── real loopback HTTP/1.1 server (one connection) ─────────────────────────────

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn content_length(head: &[u8]) -> usize {
    let t = String::from_utf8_lossy(head).to_lowercase();
    for line in t.split("\r\n") {
        if let Some(v) = line.strip_prefix("content-length:") {
            return v.trim().parse().unwrap_or(0);
        }
    }
    0
}

fn parse_request(buf: &[u8]) -> IngressRequest {
    let header_end = find_subslice(buf, b"\r\n\r\n").unwrap_or(buf.len());
    let head = String::from_utf8_lossy(&buf[..header_end]);
    let mut lines = head.split("\r\n");
    let request_line = lines.next().unwrap_or("");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("GET").to_string();
    let path = parts.next().unwrap_or("/").to_string();
    let mut headers = HashMap::new();
    for line in lines {
        if let Some((k, v)) = line.split_once(": ") {
            headers.insert(k.to_lowercase(), v.to_string());
        }
    }
    let body_start = header_end + 4;
    let body: Value = if body_start <= buf.len() {
        serde_json::from_slice(&buf[body_start..]).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    IngressRequest { method, path, headers, body }
}

fn status_text(status: u16) -> &'static str {
    match status {
        200 => "OK",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        _ => "Status",
    }
}

/// Serve exactly ONE inbound connection on `listener` (local loopback). Parses HTTP/1.1, runs
/// the router, writes the HTTP/1.1 response. Returns after one request — the host loops over
/// this in a real serving cadence (P6 keeps it explicit, no background worker).
pub async fn serve_once(
    listener: &TcpListener,
    router: &IngressRouter,
    hub: &CoordinationHub,
) -> std::io::Result<()> {
    let (mut stream, _) = listener.accept().await?;
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    loop {
        let n = stream.read(&mut tmp).await?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = find_subslice(&buf, b"\r\n\r\n") {
            let need = pos + 4 + content_length(&buf[..pos]);
            while buf.len() < need {
                let n = stream.read(&mut tmp).await?;
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&tmp[..n]);
            }
            break;
        }
    }
    let req = parse_request(&buf);
    let resp = router.handle(hub, &req).await;
    let body = serde_json::to_vec(&resp.body).unwrap_or_default();
    let head = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nX-Correlation-Id: {}\r\nContent-Length: {}\r\n\r\n",
        resp.status,
        status_text(resp.status),
        resp.correlation_id,
        body.len()
    );
    stream.write_all(head.as_bytes()).await?;
    stream.write_all(&body).await?;
    stream.flush().await?;
    Ok(())
}
