//! Crash-recovery sweep over durable receipts (LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19).
//!
//! After a restart, a receipt whose latest state is `prepared` is DANGLING — the process crashed
//! between the prepare gate and the terminal receipt. Two crash windows both land here:
//!
//! - crash AFTER prepare, BEFORE the executor → the effect did NOT happen;
//! - crash AFTER the executor succeeded, BEFORE the committed receipt → the effect DID happen,
//!   but the receipt still says `prepared` (the "write-succeeded-but-receipt-failed" hole).
//!
//! Recovery does NOT blindly re-run anything — it has no executor. It RECONCILES each dangling
//! receipt (read the target back: P7 value, or P13 correlation) and resolves it to `committed`
//! (it landed), `permanent_failure` (it did not), or leaves it unknown (undecidable). Durable
//! backends (RocksDB) make the receipts/queue/dedup survive the restart in the first place.

use crate::backend::TBackend;
use crate::capability::RECEIPTS_STORE;
use crate::clock::ClockProvider;
use crate::correlation::{
    reconcile_unknown_by_correlation, CorrelationReconcileResult, CorrelationResolver,
};
use crate::errors::EngineError;
use crate::reconcile::{reconcile_unknown_write, ReconcileResult};
use crate::write::WriteState;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;

#[derive(Debug, Default, PartialEq, Eq)]
pub struct RecoveryReport {
    /// Dangling (`prepared`/`unknown`) write receipts found.
    pub scanned: usize,
    pub committed: usize,
    pub permanent_failure: usize,
    pub still_unknown: usize,
}

/// Latest receipt fact per key (last-wins by transaction_time), within the receipts store.
async fn latest_receipts(receipts: &Arc<dyn TBackend>) -> Result<Vec<Value>, EngineError> {
    let all = receipts.all_facts().await?;
    let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
    for f in all {
        if f.store != RECEIPTS_STORE {
            continue;
        }
        let e = latest
            .entry(f.key.clone())
            .or_insert((f64::NEG_INFINITY, Value::Null));
        // P4: latest by (transaction_time, receipt_seq) — deterministic at equal timestamps,
        // replacing the prior wall-clock-only `>=` (which left equal-tx ties to HashMap order).
        if crate::capability::receipt_is_newer_or_equal(f.transaction_time, &f.value, e.0, &e.1) {
            *e = (f.transaction_time, f.value);
        }
    }
    Ok(latest.into_values().map(|(_, v)| v).collect())
}

/// `(capability_id, idempotency_key)` if this receipt is dangling and reconcilable.
fn dangling_key(v: &Value) -> Option<(String, String)> {
    let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));
    if !matches!(
        state,
        WriteState::Prepared | WriteState::UnknownExternalState
    ) {
        return None;
    }
    let cap = v.get("capability_id")?.as_str()?.to_string();
    let idem = v.get("idempotency_key")?.as_str()?.to_string();
    Some((cap, idem))
}

/// Recover dangling write receipts by READING the target back from `substrate` (P7 value
/// reconcile). Never re-runs an executor (it takes none). For HTTP/remote effects use
/// `recover_dangling_by_correlation`.
pub async fn recover_dangling_writes(
    receipts: &Arc<dyn TBackend>,
    substrate: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
) -> Result<RecoveryReport, EngineError> {
    let mut report = RecoveryReport::default();
    for v in latest_receipts(receipts).await? {
        if let Some((cap, idem)) = dangling_key(&v) {
            report.scanned += 1;
            match reconcile_unknown_write(receipts, substrate, clock, &cap, &idem).await? {
                ReconcileResult::ResolvedCommitted => report.committed += 1,
                ReconcileResult::ResolvedPermanentFailure => report.permanent_failure += 1,
                _ => report.still_unknown += 1,
            }
        }
    }
    Ok(report)
}

/// Recover dangling write receipts by their `correlation_id` (P13) via a read-only resolver —
/// for HTTP/remote effects whose fate is learned from the API's status-by-request-id, not a
/// local read-back. Never re-runs an executor.
pub async fn recover_dangling_by_correlation(
    receipts: &Arc<dyn TBackend>,
    resolver: &dyn CorrelationResolver,
    clock: &Arc<dyn ClockProvider>,
) -> Result<RecoveryReport, EngineError> {
    let mut report = RecoveryReport::default();
    for v in latest_receipts(receipts).await? {
        if let Some((cap, idem)) = dangling_key(&v) {
            report.scanned += 1;
            match reconcile_unknown_by_correlation(receipts, resolver, clock, &cap, &idem).await? {
                CorrelationReconcileResult::ResolvedCommitted => report.committed += 1,
                CorrelationReconcileResult::ResolvedPermanentFailure => {
                    report.permanent_failure += 1
                }
                _ => report.still_unknown += 1,
            }
        }
    }
    Ok(report)
}
