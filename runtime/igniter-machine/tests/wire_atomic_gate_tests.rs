//! LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7 — close the wire-to-effect seam with the P18 atomic gate.
//!
//! The wire effect path (`ingress::handle_effect`) used plain `run_write_effect`; only the
//! in-process `ServiceEffectBridge` used `run_write_effect_atomic`. The in-memory fake backend
//! never yields mid-`run_write_effect`, so a single-task cooperative serving loop *masked* the
//! race — but a REAL backend (Postgres) genuinely yields between the no-receipt read and the
//! prepared write, opening the window where two concurrent same-key requests both observe
//! "no receipt" and both execute → DOUBLE effect. This is the precondition to real Postgres writes.
//!
//! These tests are DETERMINISTIC (no timing/sleep): a `BarrierBackend` rendezvouses the two
//! same-key receipt reads exactly where a real backend would yield, so the race is forced, not
//! raced-for. They prove: (A) plain `run_write_effect` DOUBLES under that interleave; (B)
//! `run_write_effect_atomic` (now used by the wire path) collapses it to ONE; (C) the gate is
//! PER-KEY — distinct keys still reach the read concurrently (no global serialization).

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome,
    EffectRequest, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::errors::EngineError;
use igniter_machine::fact::Fact;
use igniter_machine::single_flight::{run_write_effect_atomic, SingleFlight};
use igniter_machine::write::{run_write_effect, WriteRequest};
use serde_json::json;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Barrier;

const CAP: &str = "IO.WireEffect";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .build()
        .unwrap()
}

fn passport() -> Arc<CapabilityPassport> {
    Arc::new(CapabilityPassport {
        subject: "host".into(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    })
}

/// Counts how many times the downstream effect was actually performed.
struct ProbeExecutor {
    id: String,
    attempts: AtomicU64,
}
impl ProbeExecutor {
    fn new() -> Self {
        Self {
            id: CAP.into(),
            attempts: AtomicU64::new(0),
        }
    }
    fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }
}
#[async_trait]
impl CapabilityExecutor for ProbeExecutor {
    fn capability_id(&self) -> &str {
        &self.id
    }
    async fn execute(&self, _req: &EffectRequest) -> EffectOutcome {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        EffectOutcome::succeeded(json!({ "written": true }))
    }
}

/// Wraps an in-memory backend and rendezvouses every `__receipts__` read on a barrier — forcing
/// the two same-key receipt lookups to BOTH observe "no receipt" before either writes `prepared`,
/// exactly the window a real (yielding) backend opens. Writes/other stores pass straight through.
struct BarrierBackend {
    inner: InMemoryBackend,
    barrier: Arc<Barrier>,
}
impl BarrierBackend {
    fn new(n: usize) -> Self {
        Self {
            inner: InMemoryBackend::new(),
            barrier: Arc::new(Barrier::new(n)),
        }
    }
}
#[async_trait]
impl TBackend for BarrierBackend {
    async fn read_as_of(
        &self,
        store: &str,
        key: &str,
        as_of: f64,
    ) -> Result<Option<Fact>, EngineError> {
        // Read the value FIRST (both writers observe "no receipt"), THEN park on the barrier so
        // neither can write `prepared` until both have already read "none" — the forced race window.
        let v = self.inner.read_as_of(store, key, as_of).await;
        if store == RECEIPTS_STORE {
            self.barrier.wait().await;
        }
        v
    }
    async fn write_fact(&self, fact: Fact) -> Result<(), EngineError> {
        self.inner.write_fact(fact).await
    }
    async fn facts_for(
        &self,
        store: &str,
        key: &str,
        since: Option<f64>,
        as_of: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError> {
        self.inner.facts_for(store, key, since, as_of).await
    }
    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError> {
        self.inner.all_facts().await
    }
}

fn write_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: key.into(),
        payload: json!({ "store": "orders", "key": format!("o-{key}"), "value": {"q": 1} }),
    }
}

// ── A: plain run_write_effect DOUBLES under the forced same-key interleave ─────

#[test]
fn plain_run_write_effect_doubles_under_forced_interleave() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(BarrierBackend::new(2));
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let registry = Arc::new(reg);
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let p = passport();

        // two concurrent SAME-key writers, each on its own task.
        let mut handles = Vec::new();
        for _ in 0..2 {
            let (registry, receipts, clock, p) =
                (registry.clone(), receipts.clone(), clock.clone(), p.clone());
            handles.push(tokio::spawn(async move {
                run_write_effect(
                    &registry,
                    &receipts,
                    &clock,
                    &p,
                    "write",
                    &write_req("SAME"),
                    RunMode::Live,
                )
                .await
                .unwrap();
            }));
        }
        for h in handles {
            h.await.unwrap();
        }

        assert_eq!(
            probe.attempts(),
            2,
            "plain run_write_effect double-executes under the forced race"
        );
    });
}

// ── B: run_write_effect_atomic (the wire path's gate) collapses it to ONE ──────

#[test]
fn atomic_gate_collapses_same_key_to_one() {
    rt().block_on(async {
        // No barrier needed: the per-key lock serializes regardless of backend yielding.
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let registry = Arc::new(reg);
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let sf = Arc::new(SingleFlight::new());
        let p = passport();

        let mut handles = Vec::new();
        for _ in 0..6 {
            let (sf, registry, receipts, clock, p) = (
                sf.clone(),
                registry.clone(),
                receipts.clone(),
                clock.clone(),
                p.clone(),
            );
            handles.push(tokio::spawn(async move {
                run_write_effect_atomic(
                    &sf,
                    &registry,
                    &receipts,
                    &clock,
                    &p,
                    "write",
                    &write_req("SAME"),
                    RunMode::Live,
                )
                .await
                .unwrap()
            }));
        }
        let mut states = Vec::new();
        for h in handles {
            states.push(h.await.unwrap().state);
        }

        assert_eq!(
            probe.attempts(),
            1,
            "six concurrent same-key writers perform the effect exactly once"
        );
        // every caller still gets a committed result (the duplicates replay the receipt, not 202-unknown).
        assert!(states
            .iter()
            .all(|s| *s == igniter_machine::write::WriteState::Committed));
    });
}

// ── C: the gate is PER-KEY — distinct keys are not globally serialized ─────────

#[test]
fn atomic_gate_is_per_key_not_global() {
    rt().block_on(async {
        // BarrierBackend(2): both DISTINCT-key writers must reach the receipt read CONCURRENTLY for
        // the barrier to trip. A global lock would block the second before it ever reads → deadlock.
        let receipts: Arc<dyn TBackend> = Arc::new(BarrierBackend::new(2));
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let registry = Arc::new(reg);
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let sf = Arc::new(SingleFlight::new());
        let p = passport();

        let keys = ["KA", "KB"];
        let mut handles = Vec::new();
        for k in keys {
            let (sf, registry, receipts, clock, p) = (
                sf.clone(),
                registry.clone(),
                receipts.clone(),
                clock.clone(),
                p.clone(),
            );
            handles.push(tokio::spawn(async move {
                run_write_effect_atomic(
                    &sf,
                    &registry,
                    &receipts,
                    &clock,
                    &p,
                    "write",
                    &write_req(k),
                    RunMode::Live,
                )
                .await
                .unwrap();
            }));
        }
        // a global-lock regression would deadlock on the barrier → fail fast instead of hanging.
        for h in handles {
            tokio::time::timeout(Duration::from_secs(5), h)
                .await
                .expect("distinct keys must not be globally serialized (barrier would deadlock)")
                .unwrap();
        }

        assert_eq!(
            probe.attempts(),
            2,
            "two distinct keys each perform their effect, concurrently"
        );
    });
}
