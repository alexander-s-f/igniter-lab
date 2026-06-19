//! Reconciliation of unknown writes (LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7).
//!
//! A write that resolved to `unknown_external_state` left the mutation status UNKNOWN — we
//! cannot blindly retry it (P6a). Reconciliation **reads the target back** (never re-writes)
//! and resolves the receipt to a terminal state:
//!
//! ```text
//! read-back the target fact history (append-only)
//!   our value present  -> committed         (the mutation did land)
//!   our value absent   -> permanent_failure (it did not land)
//!   substrate error    -> still unknown_external_state (cannot determine; no resolution)
//! ```
//!
//! Reconciliation writes only to the RECEIPT ledger (upgrading the unknown receipt), never to
//! the external substrate. It is the prerequisite for any future retry: only a reconciled
//! `permanent_failure` is safe to re-issue as a fresh write.

use crate::backend::TBackend;
use crate::capability::RECEIPTS_STORE;
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use crate::write::{value_digest, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

/// The result of a reconciliation pass over one write receipt.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ReconcileResult {
    /// Receipt was not in `unknown_external_state` — nothing to do; current state returned.
    NotApplicable(WriteState),
    /// Resolved: the mutation did land.
    ResolvedCommitted,
    /// Resolved: the mutation did not land.
    ResolvedPermanentFailure,
    /// Could not determine (substrate unavailable, or no target to read back) — still unknown.
    StillUnknown,
}

async fn write_resolved_receipt(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    rkey: &str,
    original: &Value,
    resolved: WriteState,
) -> Result<(), EngineError> {
    let mut value = original.clone();
    if let Some(obj) = value.as_object_mut() {
        obj.insert("state".to_string(), json!(resolved.as_str()));
        obj.insert("reconciled".to_string(), json!(true));
    }
    let fact = Fact {
        id: format!("write-receipt:{}:reconciled:{}", rkey, resolved.as_str()),
        store: RECEIPTS_STORE.to_string(),
        key: rkey.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("reconciler")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Reconcile one write receipt by `(capability_id, idempotency_key)`. Reads the target back
/// from `substrate` (a TBackend) and resolves an `unknown_external_state` receipt. Never
/// writes to `substrate` — no blind retry.
pub async fn reconcile_unknown_write(
    receipts: &Arc<dyn TBackend>,
    substrate: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    capability_id: &str,
    idempotency_key: &str,
) -> Result<ReconcileResult, EngineError> {
    let rkey = format!("{}:{}", capability_id, idempotency_key);

    let fact = match receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        Some(f) => f,
        None => return Ok(ReconcileResult::StillUnknown), // no receipt to reconcile
    };
    let v = &fact.value;
    let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));

    // An `unknown` receipt — or a DANGLING `prepared` (a crash between prepare and the terminal
    // receipt, P19) — is reconcilable; a terminal receipt is returned as-is (idempotent).
    if !matches!(
        state,
        WriteState::UnknownExternalState | WriteState::Prepared
    ) {
        return Ok(ReconcileResult::NotApplicable(state));
    }

    let store = v.get("target_store").and_then(|s| s.as_str()).unwrap_or("");
    let key = v.get("target_key").and_then(|s| s.as_str()).unwrap_or("");
    let want = v.get("value_digest").and_then(|s| s.as_str()).unwrap_or("");
    if store.is_empty() || key.is_empty() || want.is_empty() {
        // no target addressing recorded — cannot read back
        return Ok(ReconcileResult::StillUnknown);
    }

    // READ-BACK ONLY. Append-only history: did our exact value ever land at the target?
    match substrate.facts_for(store, key, None, None).await {
        Ok(versions) => {
            let landed = versions.iter().any(|f| value_digest(&f.value) == want);
            let resolved = if landed {
                WriteState::Committed
            } else {
                WriteState::PermanentFailure
            };
            write_resolved_receipt(receipts, clock.now(), &rkey, v, resolved).await?;
            Ok(if landed {
                ReconcileResult::ResolvedCommitted
            } else {
                ReconcileResult::ResolvedPermanentFailure
            })
        }
        // substrate still unavailable → cannot determine; leave the receipt unknown, write nothing.
        Err(_) => Ok(ReconcileResult::StillUnknown),
    }
}
