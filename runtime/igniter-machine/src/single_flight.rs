//! Per-key single-flight atomic gate (LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18).
//!
//! The whole receipt protocol guarantees exactly-one-effect for SEQUENTIAL duplicates (a replay
//! reads the prior receipt). Under CONCURRENCY that is not enough: two parallel requests with the
//! SAME idempotency key can both read "no receipt", both write `prepared`, and both execute → a
//! double effect. The `lookup → prepare → execute` critical section is not atomic per key.
//!
//! This closes the gap with a PER-KEY single-flight lock: concurrent same-key requests serialize
//! — the first performs the effect, the rest replay its receipt. Different keys never contend, so
//! throughput is unaffected except where it must be (duplicate/retry storms on one key).
//!
//! In-process scope: this is the single-process machine's gate. A multi-process deployment would
//! need a distributed lock or a backend compare-and-set `prepared` write; that is a later slice.
//! Note: the lock map is not pruned here (one entry per key ever seen) — a production impl evicts
//! idle locks; for the proof it is unbounded.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::write::{run_write_effect, WriteRequest, WriteResult};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// A registry of per-key async locks. Cheap to share (`&SingleFlight`) across concurrent calls.
#[derive(Default)]
pub struct SingleFlight {
    locks: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
}

impl SingleFlight {
    pub fn new() -> Self {
        Self::default()
    }
    fn lock_for(&self, key: &str) -> Arc<tokio::sync::Mutex<()>> {
        let mut map = self.locks.lock().unwrap();
        map.entry(key.to_string())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    }
}

/// Run a receipt-gated write under the per-key single-flight lock. The lock spans the ENTIRE
/// `run_write_effect` (lookup → prepare → execute → finalize), so concurrent same-key requests
/// serialize and exactly one performs the effect; the rest replay its receipt. The key is the
/// receipt key `capability_id:idempotency_key` — identical to the one the receipt uses.
pub async fn run_write_effect_atomic(
    single_flight: &SingleFlight,
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    required_scope: &str,
    req: &WriteRequest,
    mode: RunMode,
) -> Result<WriteResult, EngineError> {
    let key = format!("{}:{}", req.capability_id, req.idempotency_key);
    let lock = single_flight.lock_for(&key);
    let _guard = lock.lock().await;
    run_write_effect(registry, receipts, clock, passport, required_scope, req, mode).await
}
