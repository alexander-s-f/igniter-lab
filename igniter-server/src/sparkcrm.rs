//! SparkCRM-shaped `ServerApp` (LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2). Machine-free.
//!
//! Offline product shape only — NO live SparkCRM, NO network, NO credentials, NO DB. `SparkCrmApp`
//! turns vendor-like auction webhooks into `ServerDecision::InvokeEffect { target, input,
//! idempotency_key }`. It carries vendor normalization (path→target, raw fields→clean input, and the
//! duplicate-key extraction precedence) so the machine duplicate policy can stay GENERIC
//! (`key_header = "idempotency-key"`): after extraction, the server protocol carries ONE canonical
//! `idempotency_key`.
//!
//! Authority boundary (P1 readiness): the app names only a logical `target`; it NEVER emits
//! `capability_id`, `operation`, or `scope`. The host maps target→route and owns the effect identity.

use crate::protocol::{AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::{json, Value};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

/// Offline SparkCRM-shaped app. Stateless.
#[derive(Default)]
pub struct SparkCrmApp;

impl SparkCrmApp {
    /// Map an inbound webhook path to a logical INBOUND target (never an outbound capability id).
    fn target_for(method: &str, path: &str) -> Option<&'static str> {
        match (method, path) {
            ("POST", "/webhook/leads") => Some("lead-intake"),
            ("POST", "/webhook/bids") => Some("lead-bid"),
            ("POST", "/webhook/status") => Some("lead-status"),
            _ => None,
        }
    }

    /// Normalize raw vendor fields into a clean local capsule input. Always provides `base` (an
    /// integer the capsule consumes as `code = base + attempt`); the host injects `attempt`. Extra
    /// descriptive fields are carried for traceability — the capsule reads only what it declares.
    fn normalize_input(target: &str, body: &Value) -> Value {
        let lead_id = body.get("lead").and_then(|l| l.get("external_id")).and_then(|v| v.as_str()).unwrap_or("unknown");
        let value_cents = body.get("value_cents").and_then(|v| v.as_i64());
        let bid_cents = body.get("bid_amount_cents").and_then(|v| v.as_i64());
        match target {
            "lead-bid" => json!({
                "lead_id": lead_id,
                "bid_amount_cents": bid_cents.unwrap_or(0),
                "base": bid_cents.unwrap_or(0),
            }),
            "lead-status" => json!({
                "lead_id": lead_id,
                "status": body.get("status").and_then(|v| v.as_str()).unwrap_or("unknown"),
                "base": value_cents.unwrap_or(0),
            }),
            // lead-intake (default shape)
            _ => json!({
                "lead_id": lead_id,
                "base": value_cents.unwrap_or(1000),
            }),
        }
    }

    /// Canonical duplicate-key extraction precedence (vendor normalization lives HERE):
    /// 1. `x-auction-id` header · 2. body `auction_id` · 3. deterministic composite from non-secret
    /// stable fields · 4. `idempotency-key` header fallback. `None` = no resolvable key (→ 400).
    pub fn extract_key(req: &ServerRequest) -> Option<String> {
        if let Some(v) = req.headers.get("x-auction-id") {
            if !v.is_empty() {
                return Some(v.clone());
            }
        }
        if let Some(v) = req.body.get("auction_id").and_then(|v| v.as_str()) {
            if !v.is_empty() {
                return Some(v.to_string());
            }
        }
        if let Some(c) = Self::composite_key(&req.body) {
            return Some(c);
        }
        if let Some(v) = req.headers.get("idempotency-key") {
            if !v.is_empty() {
                return Some(v.clone());
            }
        }
        None
    }

    /// Deterministic composite key from non-secret stable fields (`phone`, `email`, `campaign`, plus
    /// an optional payload-supplied `event_bucket` — NEVER the host clock, to preserve replay
    /// determinism). `None` if no stable field is present. Opaque (`comp-<hex>`) so PII is not echoed
    /// in the key; the digest helper is the std `DefaultHasher` (a lab choice, no algorithm mandated).
    fn composite_key(body: &Value) -> Option<String> {
        let fields = [
            body.get("phone").and_then(|v| v.as_str()),
            body.get("email").and_then(|v| v.as_str()),
            body.get("campaign").and_then(|v| v.as_str()),
            body.get("event_bucket").and_then(|v| v.as_str()),
        ];
        if fields.iter().all(|f| f.is_none()) {
            return None;
        }
        let mut h = DefaultHasher::new();
        for f in fields {
            // hash a present/absent marker + value so {phone:"x"} ≠ {email:"x"}.
            match f {
                Some(s) => {
                    1u8.hash(&mut h);
                    s.hash(&mut h);
                }
                None => 0u8.hash(&mut h),
            }
        }
        Some(format!("comp-{:016x}", h.finish()))
    }
}

impl ServerApp for SparkCrmApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        let target = match Self::target_for(&req.method, &req.path) {
            Some(t) => t,
            None => return ServerDecision::Respond { response: ServerResponse::json(404, json!({ "error": "no route" })) },
        };
        // Keyless webhook → 400, ZERO effects (never silently treated as fresh).
        let key = match Self::extract_key(&req) {
            Some(k) => k,
            None => return ServerDecision::Respond { response: ServerResponse::json(400, json!({ "error": "missing duplicate key" })) },
        };
        let input = Self::normalize_input(target, &req.body);
        ServerDecision::InvokeEffect {
            target: target.to_string(),
            input,
            correlation_id: req.correlation_id.clone(),
            idempotency_key: Some(key), // canonical key; the host maps it to the generic duplicate gate.
        }
    }

    fn identity(&self) -> AppIdentity {
        AppIdentity::new("sparkcrm-shadow", "p2", "")
    }
}
