//! Effect compensation / `aborted` (LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12).
//!
//! Three distinct operations on an effect, often confused:
//! - **retry** (P8/P9): re-attempt a FAILED action so it succeeds.
//! - **reconcile** (P7): DETERMINE the truth of an `unknown` (read-back, never acts).
//! - **compensation** (P12): REVERSE a SUCCEEDED action by running a new, opposite action.
//!
//! Compensation applies ONLY to a `committed` effect. A successful compensation transitions the
//! original receipt to `aborted` (a terminal update; the original `committed` fact is preserved
//! in the append-only timeline, so the history stays auditable). Irreversible effects refuse
//! compensation. A compensation that is itself `unknown` does NOT abort (no blind reversal) —
//! the original stays committed for the host to reconcile.

use crate::backend::TBackend;
use crate::capability::{CapabilityPassport, EffectOutcome, OutcomeKind, RECEIPTS_STORE};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use crate::write::WriteState;
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::Arc;

/// An executor that can REVERSE a committed effect. Separate from `CapabilityExecutor` so the
/// forward path is unaffected. `is_compensatable() == false` models an irreversible effect
/// (the language `irreversible` modifier).
#[async_trait]
pub trait CompensatableExecutor: Send + Sync {
    fn capability_id(&self) -> &str;
    fn is_compensatable(&self) -> bool;
    /// Run the compensating action for a previously committed effect, given the original
    /// receipt value. Succeeded = reversed; Unknown = reversal status unknown; Denied/Permanent
    /// = reversal refused/failed.
    async fn compensate(&self, original_receipt: &Value, compensation_correlation_id: &str) -> EffectOutcome;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CompensationResult {
    /// Compensation succeeded → original receipt is now `aborted`.
    Aborted,
    /// Compensation outcome unknown → original stays `committed`; no blind reversal/retry.
    Unknown,
    /// Compensation refused/failed (denied/permanent) → original stays `committed`.
    Failed,
    /// The effect is irreversible — compensation refused, nothing run.
    NotCompensatable,
    /// The original receipt is not in a `committed` state — nothing to compensate.
    NotCommitted(WriteState),
    /// Already compensated — idempotent no-op (the compensator is not run again).
    AlreadyAborted,
    /// The compensator's authority does not match the original effect's authority.
    AuthorityMismatch,
    /// No receipt found for `(capability_id, idempotency_key)`.
    NoReceipt,
}

async fn append_aborted(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    rkey: &str,
    original: &Value,
    compensation_correlation_id: &str,
) -> Result<(), EngineError> {
    let mut value = original.clone();
    if let Some(o) = value.as_object_mut() {
        o.insert("state".to_string(), json!(WriteState::Aborted.as_str()));
        o.insert("compensated".to_string(), json!(true));
        o.insert("compensation_correlation_id".to_string(), json!(compensation_correlation_id));
    }
    let fact = Fact {
        id: format!("write-receipt:{}:aborted", rkey),
        store: RECEIPTS_STORE.to_string(),
        key: rkey.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("compensator")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Compensate a previously committed effect. The original `committed` fact is preserved; an
/// `aborted` fact is appended on success (linked by correlation id).
pub async fn run_compensation(
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    compensator: &dyn CompensatableExecutor,
    capability_id: &str,
    idempotency_key: &str,
    compensation_correlation_id: &str,
) -> Result<CompensationResult, EngineError> {
    let rkey = format!("{capability_id}:{idempotency_key}");
    let fact = match receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        Some(f) => f,
        None => return Ok(CompensationResult::NoReceipt),
    };
    let v = &fact.value;

    // authority continuity: only the original authority (or a matching digest) may compensate.
    let stored_auth = v.get("authority_digest").and_then(|s| s.as_str()).unwrap_or("");
    if stored_auth != passport.authority_digest() {
        return Ok(CompensationResult::AuthorityMismatch);
    }

    let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));
    match state {
        WriteState::Aborted => return Ok(CompensationResult::AlreadyAborted), // idempotent
        WriteState::Committed => {}                                           // proceed
        other => return Ok(CompensationResult::NotCommitted(other)),
    }

    // irreversible effects refuse compensation — the compensator is never run.
    if !compensator.is_compensatable() {
        return Ok(CompensationResult::NotCompensatable);
    }

    let outcome = compensator.compensate(v, compensation_correlation_id).await;
    match outcome.kind {
        OutcomeKind::Succeeded => {
            append_aborted(receipts, clock.now(), &rkey, v, compensation_correlation_id).await?;
            Ok(CompensationResult::Aborted)
        }
        // unknown reversal → DO NOT abort; original stays committed; host reconciles. No blind retry.
        OutcomeKind::UnknownExternalState => Ok(CompensationResult::Unknown),
        // reversal refused/failed → original stays committed.
        OutcomeKind::Denied | OutcomeKind::PermanentFailure | OutcomeKind::Retryable => {
            Ok(CompensationResult::Failed)
        }
    }
}

// ── Fake compensatable executor (proof only) ───────────────────────────────────

use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Clone, Copy)]
pub enum CompensationBehavior {
    Reverse,
    Deny,
    Timeout,
}

/// A fake compensatable executor. `compensatable=false` models an irreversible effect.
pub struct FakeCompensatableExecutor {
    capability_id: String,
    compensatable: bool,
    behavior: CompensationBehavior,
    calls: AtomicU64,
}

impl FakeCompensatableExecutor {
    pub fn new(capability_id: &str, behavior: CompensationBehavior) -> Self {
        Self { capability_id: capability_id.to_string(), compensatable: true, behavior, calls: AtomicU64::new(0) }
    }
    pub fn irreversible(capability_id: &str) -> Self {
        Self { capability_id: capability_id.to_string(), compensatable: false, behavior: CompensationBehavior::Deny, calls: AtomicU64::new(0) }
    }
    pub fn calls(&self) -> u64 {
        self.calls.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl CompensatableExecutor for FakeCompensatableExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }
    fn is_compensatable(&self) -> bool {
        self.compensatable
    }
    async fn compensate(&self, _original: &Value, _corr: &str) -> EffectOutcome {
        self.calls.fetch_add(1, Ordering::SeqCst);
        match self.behavior {
            CompensationBehavior::Reverse => EffectOutcome::succeeded(json!({ "reversed": true })),
            CompensationBehavior::Deny => EffectOutcome::denied("compensation refused"),
            CompensationBehavior::Timeout => EffectOutcome::unknown("compensation timed out — reversal unknown"),
        }
    }
}
