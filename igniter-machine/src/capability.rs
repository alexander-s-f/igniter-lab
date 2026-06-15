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
    rkey: &str,
    req: &EffectRequest,
    outcome: &EffectOutcome,
) -> Result<(), EngineError> {
    let value = json!({
        "capability_id": req.capability_id,
        "idempotency_key": req.idempotency_key,
        "authority_ref": req.authority_ref,
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
        transaction_time: 1.0, // a real ServiceLoop stamps tt = now; fixed here for the proof
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("service-loop")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// ServiceLoop-like effect runner — the data-plane boundary.
/// Order: preflight refusal (no executor) → receipt lookup (idempotency / replay) →
/// executor once → write receipt fact. Denial is written as data, not hidden.
pub async fn run_effect(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    req: &EffectRequest,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    // 1. Preflight refusals — BEFORE any executor is touched.
    if req.idempotency_key.is_empty() {
        return Ok(EffectOutcome::denied("preflight: missing idempotency_key"));
    }
    if req.authority_ref.is_none() {
        return Ok(EffectOutcome::denied("preflight: missing authority"));
    }
    let exec = match registry.get(&req.capability_id) {
        Some(e) => e,
        None => return Ok(EffectOutcome::denied("preflight: unknown capability")),
    };

    // 2. Idempotency / replay — receipt lookup before any external call.
    let rkey = receipt_key(req);
    if let Some(fact) = receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        return Ok(outcome_from_receipt(&fact.value)); // replayed; executor NOT called
    }
    if mode == RunMode::Replay {
        // Replay requested but no receipt exists → epistemic unknown, NOT a failure,
        // and still no executor call.
        return Ok(EffectOutcome::unknown("replay: no receipt to replay"));
    }

    // 3. Live: call the executor exactly once, then record the receipt fact.
    let outcome = exec.execute(req).await;
    write_receipt(receipts, &rkey, req, &outcome).await?;
    Ok(outcome)
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
