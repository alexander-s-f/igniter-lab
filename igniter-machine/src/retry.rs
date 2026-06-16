//! Bounded, reconciliation-gated write retry (LAB-MACHINE-CAPABILITY-IO-RETRY-P8).
//!
//! The safety invariant: **never retry an `unknown_external_state` blindly.** A retry only
//! proceeds when the previous attempt is KNOWN not to have landed — either the executor
//! returned `retryable` (a transient failure that did not mutate), or reconciliation (P7) read
//! the target back and resolved the attempt to "did not land". Each attempt uses a fresh
//! idempotency key, so at most one attempt can ever commit.
//!
//! P8 is the safe retry *logic* (bounded by attempt count). Time-based backoff, delay, and
//! durable scheduling across restarts are deliberately out of scope — there is no timer here.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::reconcile::{reconcile_unknown_write, ReconcileResult};
use crate::write::{run_write_effect, WriteRequest, WriteState};
use std::sync::Arc;

/// A bounded retry policy. `max_attempts` caps the number of write attempts (≥1).
#[derive(Clone, Copy, Debug)]
pub struct RetryPolicy {
    pub max_attempts: u32,
}

impl RetryPolicy {
    pub fn new(max_attempts: u32) -> Self {
        Self { max_attempts: max_attempts.max(1) }
    }
}

/// The outcome of a bounded retry run.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RetryOutcome {
    /// A write committed on the given attempt (1-based).
    Committed { attempts: u32 },
    /// A boundary refusal (authority / payload conflict) — not retried.
    Denied,
    /// A hard executor rejection (retry would not help).
    PermanentFailure { attempts: u32 },
    /// Bailed out: an unknown attempt could not be reconciled (substrate unavailable) — we must
    /// NOT proceed (could double-write). Reconcile later, then re-run.
    Unresolved { attempts: u32 },
    /// Ran out of attempts while still hitting retryable failures.
    Exhausted { attempts: u32 },
}

/// Run a write with bounded, reconciliation-gated retries. Each attempt derives a fresh
/// idempotency key from `base.idempotency_key`. Reuses `run_write_effect` (P6) + P7 reconcile.
pub async fn run_write_with_retry(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    substrate: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    required_scope: &str,
    base: &WriteRequest,
    policy: RetryPolicy,
) -> Result<RetryOutcome, EngineError> {
    let mut attempt: u32 = 0;
    while attempt < policy.max_attempts {
        attempt += 1;
        let req = WriteRequest {
            capability_id: base.capability_id.clone(),
            operation: base.operation.clone(),
            idempotency_key: format!("{}:a{}", base.idempotency_key, attempt),
            payload: base.payload.clone(),
        };
        let out = run_write_effect(
            registry,
            receipts,
            clock,
            passport,
            required_scope,
            &req,
            RunMode::Live,
        )
        .await?;

        match out.state {
            WriteState::Committed => return Ok(RetryOutcome::Committed { attempts: attempt }),
            // a boundary refusal (authority / conflict) is not transient — do not retry.
            WriteState::Denied => return Ok(RetryOutcome::Denied),
            // a hard executor rejection won't be helped by retrying.
            WriteState::PermanentFailure => {
                return Ok(RetryOutcome::PermanentFailure { attempts: attempt })
            }
            // transient failure, executor guarantees no mutation → retry under a new key.
            WriteState::Retryable => continue,
            // status unknown → MUST reconcile before retrying (no blind retry).
            WriteState::UnknownExternalState => {
                let rec = reconcile_unknown_write(
                    receipts,
                    substrate,
                    clock,
                    &req.capability_id,
                    &req.idempotency_key,
                )
                .await?;
                match rec {
                    ReconcileResult::ResolvedCommitted => {
                        return Ok(RetryOutcome::Committed { attempts: attempt })
                    }
                    // proven not landed → safe to retry under the next key.
                    ReconcileResult::ResolvedPermanentFailure => continue,
                    // cannot determine → bail; proceeding could double-write.
                    ReconcileResult::StillUnknown | ReconcileResult::NotApplicable(_) => {
                        return Ok(RetryOutcome::Unresolved { attempts: attempt })
                    }
                }
            }
            // a dangling prepare / aborted attempt is unresolved — do not proceed.
            WriteState::Prepared | WriteState::Aborted => {
                return Ok(RetryOutcome::Unresolved { attempts: attempt })
            }
        }
    }
    Ok(RetryOutcome::Exhausted { attempts: attempt })
}
