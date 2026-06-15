//! Real capability executors (LAB-MACHINE-CAPABILITY-IO-P3).
//!
//! First **real** substrate after the P1/P2 fake-executor proofs: a read-only local
//! `TBackend` (e.g. RocksDB on disk) wrapped as a `CapabilityExecutor`. The external data
//! store is reached through the same `TBackend` trait that already backs receipts — the
//! closest real substrate to the proven model. **Read-only**: never writes, never mutates.
//! No HTTP/network policy, no retry scheduler — those are later slices.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest};
use async_trait::async_trait;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Reads a fact from a real local `TBackend` by `{store, key, as_of?}` in the request args.
///
/// Explicit outcome mapping (P3 acceptance #3/#4):
/// - found              → `Succeeded { result: fact.value }`
/// - read ok, no record → `PermanentFailure` — a *definite* "not found", not epistemic.
/// - backend error      → `UnknownExternalState` — the substrate did not answer; we cannot
///   determine the external truth, so it stays epistemic, NOT collapsed into a failure.
///   (Decision: unavailability → unknown. Splitting transient→`retryable` is a later slice.)
/// - malformed args     → `PermanentFailure` — the request can never succeed as written.
pub struct TBackendReadExecutor {
    capability_id: String,
    backend: Arc<dyn TBackend>,
    reads: AtomicU64,
}

impl TBackendReadExecutor {
    pub fn new(capability_id: &str, backend: Arc<dyn TBackend>) -> Self {
        Self {
            capability_id: capability_id.to_string(),
            backend,
            reads: AtomicU64::new(0),
        }
    }

    /// How many times the real backend read was actually performed (idempotency proof:
    /// a replayed call must NOT increment this).
    pub fn read_count(&self) -> u64 {
        self.reads.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl CapabilityExecutor for TBackendReadExecutor {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.reads.fetch_add(1, Ordering::SeqCst);

        let store = req.args.get("store").and_then(|v| v.as_str()).unwrap_or("");
        let key = req.args.get("key").and_then(|v| v.as_str()).unwrap_or("");
        if store.is_empty() || key.is_empty() {
            return EffectOutcome::permanent("malformed read request: missing store/key");
        }
        let as_of = req.args.get("as_of").and_then(|v| v.as_f64()).unwrap_or(f64::MAX);

        match self.backend.read_as_of(store, key, as_of).await {
            Ok(Some(fact)) => EffectOutcome::succeeded(fact.value),
            Ok(None) => EffectOutcome::permanent("record not found"),
            Err(e) => EffectOutcome::unknown(&format!("backend unavailable: {}", e)),
        }
    }
}
