//! Reconcile an unknown effect by its correlation id (LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13).
//!
//! P7 reconciles an `unknown_external_state` write by reading the TARGET VALUE back — which has a
//! same-value caveat (an independent identical write could falsely match). P13 reconciles by the
//! `correlation_id` (first-class since P11) — a precise per-request identity that external APIs
//! typically expose as the only way to learn the fate of a request. A `CorrelationResolver`
//! answers "did the effect with this correlation id land?" by a READ — it never re-issues the
//! original effect.
//!
//! ```text
//! unknown_external_state receipt (carries correlation_id)
//! -> resolver.lookup(correlation_id)   (read-only)
//!    Landed      -> committed
//!    NotFound    -> permanent_failure
//!    Unavailable -> still unknown
//! ```

use crate::backend::TBackend;
use crate::capability::RECEIPTS_STORE;
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use crate::write::WriteState;
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::Arc;

/// The fate of an effect, looked up by correlation id. Read-only.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CorrelationLookup {
    /// The external system confirms the effect with this correlation id landed.
    Landed,
    /// The external system has no record of this correlation id → it did not land.
    NotFound,
    /// Could not determine (lookup unavailable).
    Unavailable,
}

/// Looks up the fate of an effect by its correlation id. MUST be read-only — never re-issues the
/// original effect. (A real impl queries the external API's status-by-request-id endpoint.)
#[async_trait]
pub trait CorrelationResolver: Send + Sync {
    async fn lookup(&self, correlation_id: &str) -> CorrelationLookup;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CorrelationReconcileResult {
    ResolvedCommitted,
    ResolvedPermanentFailure,
    StillUnknown,
    /// The receipt carries no correlation id — caller should fall back to P7 value reconcile.
    MissingCorrelation,
    /// The receipt is not in `unknown_external_state` — nothing to do.
    NotApplicable(WriteState),
    NoReceipt,
}

async fn write_resolved(
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
        obj.insert("reconciled_by".to_string(), json!("correlation_id"));
    }
    let fact = Fact {
        id: format!("write-receipt:{}:corr-reconciled:{}", rkey, resolved.as_str()),
        store: RECEIPTS_STORE.to_string(),
        key: rkey.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("correlation-reconciler")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Reconcile an `unknown_external_state` write receipt by its `correlation_id`. Reads only via
/// the resolver; never re-issues the original effect.
pub async fn reconcile_unknown_by_correlation(
    receipts: &Arc<dyn TBackend>,
    resolver: &dyn CorrelationResolver,
    clock: &Arc<dyn ClockProvider>,
    capability_id: &str,
    idempotency_key: &str,
) -> Result<CorrelationReconcileResult, EngineError> {
    let rkey = format!("{capability_id}:{idempotency_key}");
    let fact = match receipts.read_as_of(RECEIPTS_STORE, &rkey, f64::MAX).await? {
        Some(f) => f,
        None => return Ok(CorrelationReconcileResult::NoReceipt),
    };
    let v = &fact.value;
    let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));
    if state != WriteState::UnknownExternalState {
        return Ok(CorrelationReconcileResult::NotApplicable(state));
    }

    let correlation_id = v.get("correlation_id").and_then(|c| c.as_str()).unwrap_or("");
    if correlation_id.is_empty() {
        // explicit: no correlation trail → caller falls back to P7 value-based reconcile.
        return Ok(CorrelationReconcileResult::MissingCorrelation);
    }

    match resolver.lookup(correlation_id).await {
        CorrelationLookup::Landed => {
            write_resolved(receipts, clock.now(), &rkey, v, WriteState::Committed).await?;
            Ok(CorrelationReconcileResult::ResolvedCommitted)
        }
        CorrelationLookup::NotFound => {
            write_resolved(receipts, clock.now(), &rkey, v, WriteState::PermanentFailure).await?;
            Ok(CorrelationReconcileResult::ResolvedPermanentFailure)
        }
        CorrelationLookup::Unavailable => Ok(CorrelationReconcileResult::StillUnknown),
    }
}

// ── Fake correlation resolver (proof only) ─────────────────────────────────────

use std::collections::HashMap;

/// A fake resolver backed by a map of `correlation_id -> Landed/NotFound`. A correlation id not
/// in the map resolves to `NotFound` (or `Unavailable` when the resolver is marked down).
pub struct MapCorrelationResolver {
    known: HashMap<String, bool>, // correlation_id -> landed?
    available: bool,
}

impl MapCorrelationResolver {
    pub fn new(landed: &[&str]) -> Self {
        Self { known: landed.iter().map(|c| (c.to_string(), true)).collect(), available: true }
    }
    pub fn unavailable() -> Self {
        Self { known: HashMap::new(), available: false }
    }
}

#[async_trait]
impl CorrelationResolver for MapCorrelationResolver {
    async fn lookup(&self, correlation_id: &str) -> CorrelationLookup {
        if !self.available {
            return CorrelationLookup::Unavailable;
        }
        match self.known.get(correlation_id) {
            Some(true) => CorrelationLookup::Landed,
            _ => CorrelationLookup::NotFound,
        }
    }
}
