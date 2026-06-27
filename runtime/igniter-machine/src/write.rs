//! Receipt-gated write semantics (LAB-MACHINE-CAPABILITY-IO-WRITE-P6a).
//!
//! Read records *what happened*; **write must gate whether the external mutation may
//! happen.** That asymmetry is the whole point of this module. A write uses a two-phase
//! receipt:
//!
//! ```text
//! prepared   -- written BEFORE the executor (the gate); if it can't be written, no write
//! committed  -- executor succeeded
//! denied     -- executor refused (denial-as-data)
//! unknown_external_state -- timeout / no answer; mutation status UNKNOWN; NO blind retry
//! aborted    -- reserved: explicit host abort after prepare (not produced in P6a)
//! ```
//!
//! Idempotency identity binds `capability_id + operation + authority_digest + payload_digest`.
//! Same key + same payload → replay the receipt. Same key + **different** payload → refuse
//! before the executor (no write). A dangling `prepared` or an `unknown_external_state` is
//! never blindly retried. Fake write executor only — no real substrate (that is P6b).

use crate::backend::TBackend;
use crate::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, EffectRequest, OutcomeKind, PassportVerifier,
    RECEIPTS_STORE, RunMode, verify_passport, verify_passport_signed,
};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use serde_json::{Value, json};
use std::sync::Arc;

/// Lifecycle state of a write receipt. `PermanentFailure` is reached by reconciliation (P7,
/// "did not land") or a hard executor reject. `Retryable` is a transient executor failure that
/// is KNOWN not to have mutated (P8) — safe to retry under a new idempotency key.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WriteState {
    Prepared,
    Committed,
    Denied,
    UnknownExternalState,
    Retryable,
    PermanentFailure,
    Aborted,
}

impl WriteState {
    pub fn as_str(&self) -> &'static str {
        match self {
            WriteState::Prepared => "prepared",
            WriteState::Committed => "committed",
            WriteState::Denied => "denied",
            WriteState::UnknownExternalState => "unknown_external_state",
            WriteState::Retryable => "retryable",
            WriteState::PermanentFailure => "permanent_failure",
            WriteState::Aborted => "aborted",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "prepared" => WriteState::Prepared,
            "committed" => WriteState::Committed,
            "denied" => WriteState::Denied,
            "retryable" => WriteState::Retryable,
            "permanent_failure" => WriteState::PermanentFailure,
            "aborted" => WriteState::Aborted,
            _ => WriteState::UnknownExternalState,
        }
    }
}

/// A write request: a declared mutation with an operation name and a payload.
pub struct WriteRequest {
    pub capability_id: String,
    pub operation: String,
    pub idempotency_key: String,
    pub payload: Value,
}

/// The result of a receipt-gated write attempt.
#[derive(Clone, Debug)]
pub struct WriteResult {
    pub state: WriteState,
    pub result: Value,
    pub detail: Option<String>,
}

impl WriteResult {
    /// A boundary refusal — no receipt was written (nothing happened externally).
    fn refused(reason: &str) -> Self {
        Self {
            state: WriteState::Denied,
            result: Value::Null,
            detail: Some(reason.to_string()),
        }
    }
    fn unknown(reason: &str) -> Self {
        Self {
            state: WriteState::UnknownExternalState,
            result: Value::Null,
            detail: Some(reason.to_string()),
        }
    }
    fn from_receipt(v: &Value) -> Self {
        Self {
            state: WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or("")),
            result: v.get("result").cloned().unwrap_or(Value::Null),
            detail: v
                .get("detail")
                .and_then(|d| d.as_str())
                .map(|s| s.to_string()),
        }
    }
}

/// Deterministic digest of a write payload (serde_json `Map` is sorted by key, so the
/// serialization is stable). Used to bind the idempotency key to the exact payload.
pub fn payload_digest(payload: &Value) -> String {
    let s = serde_json::to_string(payload).unwrap_or_default();
    blake3::hash(s.as_bytes()).to_hex().to_string()
}

/// Deterministic digest of a single value — recorded in the write receipt so reconciliation
/// (P7) can read the target back and compare WITHOUT the receipt holding the raw value.
pub fn value_digest(value: &Value) -> String {
    let s = serde_json::to_string(value).unwrap_or_default();
    blake3::hash(s.as_bytes()).to_hex().to_string()
}

/// A typed local-fact write target. The payload — and therefore the idempotency `payload_digest`
/// — is FORCED to include the full fact identity: `store + key + value + valid_time`. So two
/// writes to *different* keys (or different valid_time) with the same value never collide under
/// one `(capability, idempotency_key)` envelope; a reused idempotency key with a different target
/// is caught as a payload conflict (P6a #4).
pub struct FactWrite {
    pub store: String,
    pub key: String,
    pub value: Value,
    pub valid_time: Option<f64>,
}

impl FactWrite {
    pub fn to_payload(&self) -> Value {
        json!({
            "store": self.store,
            "key": self.key,
            "value": self.value,
            "valid_time": self.valid_time,
        })
    }
}

fn receipt_key(req: &WriteRequest) -> String {
    format!("{}:{}", req.capability_id, req.idempotency_key)
}

#[allow(clippy::too_many_arguments)]
async fn write_receipt(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    rkey: &str,
    req: &WriteRequest,
    authority_digest: &str,
    payload_digest: &str,
    state: WriteState,
    result: &Value,
    detail: Option<&str>,
) -> Result<(), EngineError> {
    // Target addressing (store/key) + a value DIGEST (not the raw value) so reconciliation
    // (P7) can read the target back. Present when the payload is a FactWrite; null otherwise.
    let target_store = req.payload.get("store").and_then(|v| v.as_str());
    let target_key = req.payload.get("key").and_then(|v| v.as_str());
    let target_value_digest = req.payload.get("value").map(value_digest);
    // correlation id: prefer the executor's result, else the request payload (so an `unknown`
    // write — whose result is null — still carries the correlation trail for P13 reconcile).
    let correlation_id = result
        .get("correlation_id")
        .cloned()
        .filter(|v| !v.is_null())
        .or_else(|| {
            req.payload
                .get("correlation_id")
                .cloned()
                .filter(|v| !v.is_null())
        })
        .unwrap_or(Value::Null);
    let value = json!({
        "capability_id": req.capability_id,
        "operation": req.operation,
        "idempotency_key": req.idempotency_key,
        "authority_digest": authority_digest,
        "payload_digest": payload_digest,
        "target_store": target_store,
        "target_key": target_key,
        "value_digest": target_value_digest,
        // first-class correlation id (P11); from executor result or request payload (P13).
        "correlation_id": correlation_id,
        "state": state.as_str(),
        "result": result,
        "detail": detail,
    });
    let fact = Fact {
        // include the state in the id so `prepared` and the terminal fact are distinct facts
        // on the same (store, key) timeline; the latest by tx-time (terminal) wins the read.
        id: format!("write-receipt:{}:{}", rkey, state.as_str()),
        store: RECEIPTS_STORE.to_string(),
        key: rkey.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("service-loop-write")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Receipt-gated write runner. Authority is verified at the boundary; the receipt gates the
/// mutation (prepared before the executor); duplicates and replays resolve by the receipt;
/// unknown outcomes are never blindly retried.
pub async fn run_write_effect(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    required_scope: &str,
    req: &WriteRequest,
    mode: RunMode,
) -> Result<WriteResult, EngineError> {
    // 1. Authority at the boundary — refusal writes NO receipt.
    let authority_digest =
        match verify_passport(passport, &req.capability_id, required_scope, clock) {
            Ok(d) => d,
            Err(reason) => {
                return Ok(WriteResult::refused(&format!(
                    "authority refused ({:?})",
                    reason
                )));
            }
        };
    run_write_effect_with_authority_digest(registry, receipts, clock, authority_digest, req, mode)
        .await
}

/// Signed passport variant for host data-plane paths. Authentication happens before the
/// two-phase write receipt gate; untrusted/tampered passports write no receipt and reach no
/// executor.
pub async fn run_write_effect_signed(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    verifier: &PassportVerifier,
    passport: &CapabilityPassport,
    required_scope: &str,
    req: &WriteRequest,
    mode: RunMode,
) -> Result<WriteResult, EngineError> {
    let authority_digest = match verify_passport_signed(
        verifier,
        passport,
        &req.capability_id,
        required_scope,
        clock,
    ) {
        Ok(d) => d,
        Err(reason) => {
            return Ok(WriteResult::refused(&format!(
                "authority refused ({:?})",
                reason
            )));
        }
    };
    run_write_effect_with_authority_digest(registry, receipts, clock, authority_digest, req, mode)
        .await
}

async fn run_write_effect_with_authority_digest(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    authority_digest: String,
    req: &WriteRequest,
    mode: RunMode,
) -> Result<WriteResult, EngineError> {
    if req.idempotency_key.is_empty() {
        return Ok(WriteResult::refused("missing idempotency_key"));
    }
    let exec = match registry.get(&req.capability_id) {
        Some(e) => e,
        None => return Ok(WriteResult::refused("unknown capability")),
    };

    let pdigest = payload_digest(&req.payload);
    let rkey = receipt_key(req);

    // 2. Existing receipt? Resolve duplicates / replays / unresolved priors.
    if let Some(fact) = receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        let v = &fact.value;
        let stored_auth = v
            .get("authority_digest")
            .and_then(|s| s.as_str())
            .unwrap_or("");
        let stored_payload = v
            .get("payload_digest")
            .and_then(|s| s.as_str())
            .unwrap_or("");
        let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));

        // replay with different authority → refuse (P5 policy).
        if stored_auth != authority_digest {
            return Ok(WriteResult::refused("replay: authority scope mismatch"));
        }
        // same key, DIFFERENT payload → refuse before executor, no write.
        if stored_payload != pdigest {
            return Ok(WriteResult::refused(
                "idempotency key reused with a different payload",
            ));
        }
        // same key + same payload → resolve by state.
        match state {
            WriteState::Committed
            | WriteState::Denied
            | WriteState::PermanentFailure
            | WriteState::Retryable => {
                // terminal receipt for this key (including reconciled permanent_failure and a
                // transient retryable): replay it. To actually retry, the caller / scheduler
                // uses a NEW idempotency key.
                return Ok(WriteResult::from_receipt(v));
            }
            WriteState::Prepared | WriteState::UnknownExternalState | WriteState::Aborted => {
                // a dangling prepare (crash mid-write) or a known-unknown: the mutation status
                // is UNKNOWN. No blind retry — the caller must reconcile out of band.
                return Ok(WriteResult::unknown(
                    "prior write attempt unresolved — no blind retry",
                ));
            }
        }
    }

    // replay mode with no receipt → unknown, no prepare, no executor.
    if mode == RunMode::Replay {
        return Ok(WriteResult::unknown("replay: no committed receipt"));
    }

    // 3. GATE: write the `prepared` receipt BEFORE the executor. If it cannot be written, the
    //    executor must NOT be called.
    let prepared_at = clock.now();
    if let Err(e) = write_receipt(
        receipts,
        prepared_at,
        &rkey,
        req,
        &authority_digest,
        &pdigest,
        WriteState::Prepared,
        &Value::Null,
        None,
    )
    .await
    {
        return Ok(WriteResult::refused(&format!(
            "prepare receipt write failed — executor not called ({})",
            e
        )));
    }

    // 4. Perform the mutation exactly once.
    let effect_req = EffectRequest {
        capability_id: req.capability_id.clone(),
        idempotency_key: req.idempotency_key.clone(),
        authority_ref: None,
        args: req.payload.clone(),
    };
    let outcome = exec.execute(&effect_req).await;

    // 5. Finalize the receipt from the outcome.
    let state = match outcome.kind {
        OutcomeKind::Succeeded => WriteState::Committed,
        OutcomeKind::Denied => WriteState::Denied,
        // The executor's failure taxonomy carries through (executors must only assert
        // retryable/permanent when no-mutation is KNOWN; ambiguous → unknown):
        OutcomeKind::Retryable => WriteState::Retryable, // transient, did not mutate (P8)
        OutcomeKind::PermanentFailure => WriteState::PermanentFailure, // hard reject, retry won't help
        OutcomeKind::UnknownExternalState => WriteState::UnknownExternalState, // status unknown
    };
    let finalized_at = clock.now();
    write_receipt(
        receipts,
        finalized_at,
        &rkey,
        req,
        &authority_digest,
        &pdigest,
        state,
        &outcome.result,
        outcome.failure_kind.as_deref(),
    )
    .await?;

    Ok(WriteResult {
        state,
        result: outcome.result,
        detail: outcome.failure_kind,
    })
}

// ── Fake write executor (proof only — no real substrate) ───────────────────────

use crate::capability::{CapabilityExecutor, EffectOutcome};
use async_trait::async_trait;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

/// What a fake write executor does when reached.
#[derive(Clone, Copy)]
pub enum WriteBehavior {
    Commit,
    Deny,
    Timeout,
    Retryable,
}

/// A fake write executor: records "applied" mutations in memory and counts attempts so
/// duplicate-prevention and gating can be proven. No real substrate.
pub struct FakeWriteExecutor {
    capability_id: String,
    behavior: WriteBehavior,
    applied: Mutex<Vec<Value>>,
    attempts: AtomicU64,
}

impl FakeWriteExecutor {
    pub fn new(capability_id: &str, behavior: WriteBehavior) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            behavior,
            applied: Mutex::new(Vec::new()),
            attempts: AtomicU64::new(0),
        }
    }
    /// How many times the executor was actually reached (a replay must not increment this).
    pub fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }
    /// How many mutations were actually applied (Commit behavior only).
    pub fn applied_count(&self) -> usize {
        self.applied.lock().unwrap().len()
    }
}

#[async_trait]
impl CapabilityExecutor for FakeWriteExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        match self.behavior {
            WriteBehavior::Commit => {
                self.applied.lock().unwrap().push(req.args.clone());
                EffectOutcome::succeeded(json!({ "written": true }))
            }
            WriteBehavior::Deny => EffectOutcome::denied("write denied by executor"),
            WriteBehavior::Timeout => EffectOutcome::unknown("write timed out — mutation unknown"),
            WriteBehavior::Retryable => {
                EffectOutcome::retryable("transient write failure, no mutation")
            }
        }
    }
}
