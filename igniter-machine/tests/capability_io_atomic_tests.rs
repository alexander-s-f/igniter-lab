//! LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18 — exactly-one-effect under concurrency.
//!
//! The receipt protocol gives exactly-one-effect for SEQUENTIAL duplicates. P18 closes the
//! concurrency gap with a per-key single-flight lock: two parallel requests with the same
//! idempotency key must result in ONE effect. Different keys must still run in parallel.

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome,
    EffectRequest, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::single_flight::{run_write_effect_atomic, SingleFlight};
use igniter_machine::write::{payload_digest, WriteRequest, WriteState};
use serde_json::json;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

const CAP: &str = "IO.AtomicCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".into(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn write_req(key: &str, value: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: key.into(),
        payload: json!({ "store": "s", "key": format!("r-{key}"), "value": value }),
    }
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

/// Counts executor invocations AND the maximum number of concurrently-in-flight executions
/// (it yields several times mid-flight, so overlapping calls are observable).
struct ProbeExecutor {
    cap: String,
    attempts: AtomicU64,
    in_flight: AtomicU64,
    max_in_flight: AtomicU64,
}
impl ProbeExecutor {
    fn new() -> Self {
        Self {
            cap: CAP.into(),
            attempts: AtomicU64::new(0),
            in_flight: AtomicU64::new(0),
            max_in_flight: AtomicU64::new(0),
        }
    }
    fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }
    fn max_in_flight(&self) -> u64 {
        self.max_in_flight.load(Ordering::SeqCst)
    }
}
#[async_trait]
impl CapabilityExecutor for ProbeExecutor {
    fn capability_id(&self) -> &str {
        &self.cap
    }
    async fn execute(&self, _req: &EffectRequest) -> EffectOutcome {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        let cur = self.in_flight.fetch_add(1, Ordering::SeqCst) + 1;
        self.max_in_flight.fetch_max(cur, Ordering::SeqCst);
        for _ in 0..8 {
            tokio::task::yield_now().await; // give a concurrent same-key call a chance to overlap
        }
        self.in_flight.fetch_sub(1, Ordering::SeqCst);
        EffectOutcome::succeeded(json!({ "ok": true }))
    }
}

// ── concurrent same key → exactly one effect ───────────────────────────────────

#[test]
fn concurrent_same_key_performs_one_effect() {
    rt().block_on(async {
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let receipts = receipts();
        let sf = SingleFlight::new();
        let p = passport();
        let req = write_req("same", json!(1));
        let c = clock();

        let f1 =
            run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &req, RunMode::Live);
        let f2 =
            run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &req, RunMode::Live);
        let (r1, r2) = tokio::join!(f1, f2);

        assert_eq!(r1.unwrap().state, WriteState::Committed);
        assert_eq!(r2.unwrap().state, WriteState::Committed);
        assert_eq!(
            probe.attempts(),
            1,
            "two concurrent same-key requests → exactly one effect"
        );
        assert_eq!(
            probe.max_in_flight(),
            1,
            "same-key effects never overlap (serialized)"
        );
    });
}

// ── different keys still run in parallel (per-key, not global, lock) ────────────

#[test]
fn concurrent_different_keys_run_in_parallel() {
    rt().block_on(async {
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let receipts = receipts();
        let sf = SingleFlight::new();
        let p = passport();
        let a = write_req("key-a", json!(1));
        let b = write_req("key-b", json!(2));
        let c = clock();

        let f1 = run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &a, RunMode::Live);
        let f2 = run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &b, RunMode::Live);
        let (r1, r2) = tokio::join!(f1, f2);

        assert_eq!(r1.unwrap().state, WriteState::Committed);
        assert_eq!(r2.unwrap().state, WriteState::Committed);
        assert_eq!(
            probe.attempts(),
            2,
            "different keys both perform their effect"
        );
        assert_eq!(
            probe.max_in_flight(),
            2,
            "different keys run concurrently — the lock is per-key"
        );
    });
}

// ── concurrent same key, different payload → one wins, other refused ───────────

#[test]
fn concurrent_same_key_different_payload_one_wins() {
    rt().block_on(async {
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let receipts = receipts();
        let sf = SingleFlight::new();
        let p = passport();
        let ra = write_req("k", json!(1));
        let rb = write_req("k", json!(999)); // same key, different payload
        let c = clock();

        let f1 = run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &ra, RunMode::Live);
        let f2 = run_write_effect_atomic(&sf, &reg, &receipts, &c, &p, "write", &rb, RunMode::Live);
        let (r1, r2) = tokio::join!(f1, f2);

        let states = [r1.unwrap().state, r2.unwrap().state];
        assert!(states.contains(&WriteState::Committed), "one payload wins");
        assert!(
            states.contains(&WriteState::Denied),
            "the conflicting payload is refused"
        );
        assert_eq!(probe.attempts(), 1, "only one effect performed");
    });
}

// ── a dangling `prepared` (crash) stays recoverable under the gate ─────────────

#[test]
fn dangling_prepared_stays_recoverable() {
    rt().block_on(async {
        let probe = Arc::new(ProbeExecutor::new());
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(probe.clone());
        let receipts = receipts();
        let sf = SingleFlight::new();
        let p = passport();
        let req = write_req("dangling", json!(1));

        // simulate a crash AFTER prepare but BEFORE the executor/commit: a lone `prepared` receipt.
        let value = json!({
            "capability_id": CAP, "operation": "put", "idempotency_key": "dangling",
            "authority_digest": p.authority_digest(), "payload_digest": payload_digest(&req.payload),
            "state": "prepared", "result": null, "detail": null,
        });
        receipts.write_fact(Fact {
            id: "write-receipt:IO.AtomicCapability:dangling:prepared".into(),
            store: RECEIPTS_STORE.into(), key: "IO.AtomicCapability:dangling".into(),
            value, value_hash: String::new(), causation: None, transaction_time: 1.0,
            valid_time: None, schema_version: 1, producer: None, derivation: None,
        }).await.unwrap();

        let out = run_write_effect_atomic(&sf, &reg, &receipts, &clock(), &p, "write", &req, RunMode::Live).await.unwrap();
        // unknown (prior attempt unresolved) — NO blind retry; recoverable via reconcile.
        assert_eq!(out.state, WriteState::UnknownExternalState);
        assert_eq!(probe.attempts(), 0, "a dangling prepared is never blindly re-executed");
    });
}
