//! Capability IO boundary (LAB-MACHINE-CAPABILITY-IO-P1) — production data-plane shape.
//!
//! ```text
//! contract declares effect/capability
//! ServiceLoop validates authority + idempotency + executor binding
//! CapabilityExecutor performs external IO
//! EffectReceipt is written as a bitemporal fact
//! pure graph continues from the typed outcome
//! ```
//!
//! Guardrail: **the external world may be contract-shaped, but never carries
//! pure-contract authority — it always carries receipt, failure, authority, and
//! idempotency.** `TBackend` is the first proven capability family; this generalizes
//! its pattern. Fake executors only (no real DB/HTTP) — this is a proof of the model.

use crate::backend::TBackend;
use crate::clock::{ClockProvider, SystemClock};
use crate::errors::EngineError;
use crate::fact::Fact;
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

/// Typed effect outcome — failure is a *taxonomy*, not a boolean. `UnknownExternalState`
/// is an epistemic outcome (we could not determine the external truth), NOT a failure.
/// (Proof-local vocabulary; aligns with the canon epistemic-outcome model, ledger D-001 —
/// NOT a claim that D-001 is fully implemented in canon.)
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OutcomeKind {
    Succeeded,
    Denied,
    Retryable,
    PermanentFailure,
    UnknownExternalState,
}

impl OutcomeKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            OutcomeKind::Succeeded => "succeeded",
            OutcomeKind::Denied => "denied",
            OutcomeKind::Retryable => "retryable",
            OutcomeKind::PermanentFailure => "permanent_failure",
            OutcomeKind::UnknownExternalState => "unknown_external_state",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "succeeded" => OutcomeKind::Succeeded,
            "denied" => OutcomeKind::Denied,
            "retryable" => OutcomeKind::Retryable,
            "permanent_failure" => OutcomeKind::PermanentFailure,
            _ => OutcomeKind::UnknownExternalState,
        }
    }
}

#[derive(Clone, Debug)]
pub struct EffectOutcome {
    pub kind: OutcomeKind,
    pub result: Value,
    pub failure_kind: Option<String>,
}

impl EffectOutcome {
    pub fn succeeded(result: Value) -> Self {
        Self { kind: OutcomeKind::Succeeded, result, failure_kind: None }
    }
    pub fn denied(reason: &str) -> Self {
        Self { kind: OutcomeKind::Denied, result: json!({ "denied": reason }), failure_kind: Some(reason.to_string()) }
    }
    pub fn unknown(reason: &str) -> Self {
        Self { kind: OutcomeKind::UnknownExternalState, result: Value::Null, failure_kind: Some(reason.to_string()) }
    }
    pub fn permanent(reason: &str) -> Self {
        Self { kind: OutcomeKind::PermanentFailure, result: Value::Null, failure_kind: Some(reason.to_string()) }
    }
    /// A transient failure where the executor KNOWS no mutation occurred (e.g. it failed
    /// before sending the write). Distinct from `unknown` — safe to retry. Executors must only
    /// return this when no-mutation is guaranteed; otherwise return `unknown`.
    pub fn retryable(reason: &str) -> Self {
        Self { kind: OutcomeKind::Retryable, result: Value::Null, failure_kind: Some(reason.to_string()) }
    }
}

/// A request to perform an external effect. Carries the four things the boundary always
/// requires: capability, idempotency, authority, and (typed) args.
pub struct EffectRequest {
    pub capability_id: String,
    pub idempotency_key: String,
    pub authority_ref: Option<String>,
    pub args: Value,
}

/// A typed external-port executor. `TBackend` is the proven temporal/storage instance of
/// this same shape; HTTP/DB/queue executors are future instances.
#[async_trait]
pub trait CapabilityExecutor: Send + Sync {
    fn capability_id(&self) -> &str;
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome;
}

#[derive(Default)]
pub struct CapabilityExecutorRegistry {
    execs: HashMap<String, Arc<dyn CapabilityExecutor>>,
}

impl CapabilityExecutorRegistry {
    pub fn new() -> Self {
        Self { execs: HashMap::new() }
    }
    pub fn register(&mut self, exec: Arc<dyn CapabilityExecutor>) {
        self.execs.insert(exec.capability_id().to_string(), exec);
    }
    pub fn get(&self, id: &str) -> Option<Arc<dyn CapabilityExecutor>> {
        self.execs.get(id).cloned()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum RunMode {
    Live,
    Replay,
}

// ── Authority: typed capability passport (LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5) ──

/// A minimal, verifiable caller authority. NOT OAuth/JWT/ACL/roles — just enough to gate an
/// effect at the host boundary: who, for which capability, with which scopes, valid when.
#[derive(Clone, Debug)]
pub struct CapabilityPassport {
    pub subject: String,
    pub capability_id: String,
    pub scopes: Vec<String>,
    pub issued_at: f64,
    pub expires_at: Option<f64>,
    pub revoked: bool,
    /// Opaque caller-supplied evidence (e.g. a signature/material hash). Folded into the
    /// authority digest; this layer does not parse or validate its internal structure.
    pub evidence_digest: String,
}

impl CapabilityPassport {
    /// A stable digest of the authority identity — recorded in the receipt and matched on
    /// replay. Independent of `issued_at`/`expires_at`/`revoked` (those are validity, not
    /// identity): subject + capability + sorted scopes + evidence_digest.
    pub fn authority_digest(&self) -> String {
        let mut scopes = self.scopes.clone();
        scopes.sort();
        let material = format!(
            "{}|{}|{}|{}",
            self.subject,
            self.capability_id,
            scopes.join(","),
            self.evidence_digest
        );
        blake3::hash(material.as_bytes()).to_hex().to_string()
    }
}

/// Why a passport was refused at the host boundary (all → runtime refusal, no receipt).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AuthRefusal {
    WrongCapability,
    MissingScope,
    Revoked,
    Expired,
}

/// Verify a passport at the host boundary. Expiry uses the injected clock. Returns the
/// authority digest on success. Pure (no IO) — called before any executor.
pub fn verify_passport(
    passport: &CapabilityPassport,
    capability_id: &str,
    required_scope: &str,
    clock: &Arc<dyn ClockProvider>,
) -> Result<String, AuthRefusal> {
    if passport.capability_id != capability_id {
        return Err(AuthRefusal::WrongCapability);
    }
    if passport.revoked {
        return Err(AuthRefusal::Revoked);
    }
    if let Some(exp) = passport.expires_at {
        if clock.now() > exp {
            return Err(AuthRefusal::Expired);
        }
    }
    if !required_scope.is_empty() && !passport.scopes.iter().any(|s| s == required_scope) {
        return Err(AuthRefusal::MissingScope);
    }
    Ok(passport.authority_digest())
}

/// Receipts are bitemporal facts in a dedicated TBackend store namespace.
pub const RECEIPTS_STORE: &str = "__receipts__";

fn receipt_key(req: &EffectRequest) -> String {
    format!("{}:{}", req.capability_id, req.idempotency_key)
}

fn outcome_from_receipt(value: &Value) -> EffectOutcome {
    EffectOutcome {
        kind: OutcomeKind::from_str(value["outcome_kind"].as_str().unwrap_or("unknown_external_state")),
        result: value.get("result").cloned().unwrap_or(Value::Null),
        failure_kind: value["failure_kind"].as_str().map(|s| s.to_string()),
    }
}

async fn write_receipt(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    rkey: &str,
    req: &EffectRequest,
    authority_digest: &str,
    outcome: &EffectOutcome,
) -> Result<(), EngineError> {
    let value = json!({
        "capability_id": req.capability_id,
        "idempotency_key": req.idempotency_key,
        "authority_ref": req.authority_ref,
        "authority_digest": authority_digest,
        // first-class correlation id (P11); from executor result or request args (P13).
        "correlation_id": outcome.result.get("correlation_id").cloned().filter(|v| !v.is_null())
            .or_else(|| req.args.get("correlation_id").cloned().filter(|v| !v.is_null()))
            .unwrap_or(Value::Null),
        "outcome_kind": outcome.kind.as_str(),
        "result": outcome.result,
        "failure_kind": outcome.failure_kind,
    });
    let fact = Fact {
        id: format!("receipt:{}", rkey),
        store: RECEIPTS_STORE.to_string(),
        key: rkey.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: now, // stamped by the injected ClockProvider at the boundary
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("service-loop")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Shared effect core — the executor + receipt + idempotency/replay machinery. The caller
/// has ALREADY verified authority and passes the resolved `authority_digest` (the evidence to
/// record and to match on replay). Order: idempotency-key check → resolve executor → receipt
/// lookup (idempotency / replay, with authority-scope match) → executor once → write receipt.
async fn run_effect_core(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    req: &EffectRequest,
    authority_digest: &str,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    if req.idempotency_key.is_empty() {
        return Ok(EffectOutcome::denied("preflight: missing idempotency_key"));
    }
    let exec = match registry.get(&req.capability_id) {
        Some(e) => e,
        None => return Ok(EffectOutcome::denied("preflight: unknown capability")),
    };

    // Idempotency / replay — receipt lookup before any external call.
    let rkey = receipt_key(req);
    if let Some(fact) = receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        // Replay policy: the replaying caller must present the SAME authority scope. A receipt
        // recorded with a different authority digest is refused (default strict; a
        // `replay_override` knob is a future slice, not implemented).
        let stored = fact
            .value
            .get("authority_digest")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if stored != authority_digest {
            return Ok(EffectOutcome::denied("replay: authority scope mismatch"));
        }
        return Ok(outcome_from_receipt(&fact.value)); // replayed; executor + clock NOT touched
    }
    if mode == RunMode::Replay {
        // Replay requested but no receipt exists → epistemic unknown, NOT a failure,
        // and still no executor call and no clock read.
        return Ok(EffectOutcome::unknown("replay: no receipt to replay"));
    }

    // Live: call the executor exactly once, then record the receipt fact. The clock is read
    // here and only here — at the boundary, never inside a contract.
    let outcome = exec.execute(req).await;
    write_receipt(receipts, clock.now(), &rkey, req, authority_digest, &outcome).await?;
    Ok(outcome)
}

/// ServiceLoop-like effect runner with an explicitly injected clock and **presence-only**
/// authority (the `req.authority_ref` string is the authority evidence). Preflight refuses a
/// missing authority before any executor. For typed authority use `run_effect_with_passport`.
pub async fn run_effect_with_clock(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    req: &EffectRequest,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    let digest = match &req.authority_ref {
        Some(a) if !a.is_empty() => a.clone(),
        _ => return Ok(EffectOutcome::denied("preflight: missing authority")),
    };
    run_effect_core(registry, receipts, clock, req, &digest, mode).await
}

/// ServiceLoop-like effect runner with a typed `CapabilityPassport` (richer authority). The
/// passport is verified at the host boundary BEFORE the executor; a wrong capability / missing
/// scope / revoked / expired passport is a runtime refusal with NO receipt. The verified
/// authority digest is recorded in the receipt and matched on replay.
pub async fn run_effect_with_passport(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    required_scope: &str,
    req: &EffectRequest,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    let digest = match verify_passport(passport, &req.capability_id, required_scope, clock) {
        Ok(d) => d,
        Err(reason) => {
            return Ok(EffectOutcome::denied(&format!(
                "preflight: authority refused ({:?})",
                reason
            )))
        }
    };
    run_effect_core(registry, receipts, clock, req, &digest, mode).await
}

/// Convenience boundary entrypoint using the default production clock (`SystemClock`).
/// Use `run_effect_with_clock` to inject a deterministic clock (tests) or a custom provider.
pub async fn run_effect(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    req: &EffectRequest,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    let clock: Arc<dyn ClockProvider> = Arc::new(SystemClock::new());
    run_effect_with_clock(registry, receipts, &clock, req, mode).await
}

// ── Fake executors (proof only — no real IO) ──────────────────────────────────

use std::sync::atomic::{AtomicU64, Ordering};

/// Echoes the request args back as a successful result. Counts invocations so idempotency
/// can be proven (the second call must not increment it).
pub struct EchoCapabilityExecutor {
    id: String,
    calls: AtomicU64,
}

impl EchoCapabilityExecutor {
    pub fn new(id: &str) -> Self {
        Self { id: id.to_string(), calls: AtomicU64::new(0) }
    }
    pub fn call_count(&self) -> u64 {
        self.calls.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl CapabilityExecutor for EchoCapabilityExecutor {
    fn capability_id(&self) -> &str {
        &self.id
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.calls.fetch_add(1, Ordering::SeqCst);
        EffectOutcome::succeeded(req.args.clone())
    }
}

/// A fake key/value read port. Special keys exercise the full outcome taxonomy:
/// `__timeout__` → unknown_external_state (epistemic), `__forbidden__` → denied
/// (denial-as-data), a known key → succeeded, anything else → permanent_failure.
pub struct KvReadExecutor {
    id: String,
    kv: HashMap<String, Value>,
    calls: AtomicU64,
}

impl KvReadExecutor {
    pub fn new(id: &str, kv: HashMap<String, Value>) -> Self {
        Self { id: id.to_string(), kv, calls: AtomicU64::new(0) }
    }
    pub fn call_count(&self) -> u64 {
        self.calls.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl CapabilityExecutor for KvReadExecutor {
    fn capability_id(&self) -> &str {
        &self.id
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.calls.fetch_add(1, Ordering::SeqCst);
        let key = req.args["key"].as_str().unwrap_or("");
        match key {
            "__timeout__" => EffectOutcome::unknown("external system did not answer"),
            "__forbidden__" => EffectOutcome::denied("authority insufficient for key"),
            k => match self.kv.get(k) {
                Some(v) => EffectOutcome::succeeded(v.clone()),
                None => EffectOutcome::permanent("key not found"),
            },
        }
    }
}
