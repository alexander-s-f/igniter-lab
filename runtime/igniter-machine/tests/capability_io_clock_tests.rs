//! LAB-MACHINE-CAPABILITY-IO-CLOCK-P4 — host clock capability.
//!
//! Receipt `transaction_time` comes from an injected `ClockProvider`, read ONLY at the
//! ServiceLoop boundary. Deterministic `FixedClock` in tests; `SystemClock` in production.
//! Replay never reads the clock (writes no receipt) → never rewrites the original timestamp.
//! The contract body has no access to a clock (`dispatch` takes none).

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect_with_clock, CapabilityExecutorRegistry, EchoCapabilityExecutor, EffectRequest,
    KvReadExecutor, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock, SystemClock};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::service_loop::{run_service_with_clock, HostRequest};
use serde_json::json;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

const FIXTURE: &str =
    "../../frame-ui/igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig";
const STORAGE_CAP: &str = "IO.StorageCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn req(cap: &str, key: &str, args: serde_json::Value) -> EffectRequest {
    EffectRequest {
        capability_id: cap.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

async fn receipt_tt(store: &Arc<dyn TBackend>, key: &str) -> f64 {
    store
        .read_as_of(RECEIPTS_STORE, key, f64::MAX)
        .await
        .unwrap()
        .expect("receipt must exist")
        .transaction_time
}

// ── receipt timestamp comes from the injected clock ────────────────────────────

#[test]
fn receipt_timestamp_comes_from_injected_clock() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();
        let clock: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(1234.5));

        run_effect_with_clock(
            &reg,
            &store,
            &clock,
            &req("echo", "k1", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(receipt_tt(&store, "echo:k1").await, 1234.5);
    });
}

// ── replay does NOT rewrite the receipt timestamp ──────────────────────────────

#[test]
fn replay_does_not_rewrite_receipt_timestamp() {
    rt().block_on(async {
        let echo = Arc::new(EchoCapabilityExecutor::new("echo"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let store = receipts();

        // live write at t=100
        let clock_live: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        run_effect_with_clock(
            &reg,
            &store,
            &clock_live,
            &req("echo", "same", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(receipt_tt(&store, "echo:same").await, 100.0);

        // a later LIVE call with the same key at t=999 → replays the receipt, no new write
        let clock_late: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(999.0));
        run_effect_with_clock(
            &reg,
            &store,
            &clock_late,
            &req("echo", "same", json!(1)),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(
            receipt_tt(&store, "echo:same").await,
            100.0,
            "timestamp must not be rewritten"
        );

        // explicit Replay at t=999 also must not rewrite it
        run_effect_with_clock(
            &reg,
            &store,
            &clock_late,
            &req("echo", "same", json!(1)),
            RunMode::Replay,
        )
        .await
        .unwrap();
        assert_eq!(receipt_tt(&store, "echo:same").await, 100.0);
        assert_eq!(echo.call_count(), 1, "executor still ran exactly once");
    });
}

// ── distinct effects stamp their own clock readings ────────────────────────────

#[test]
fn distinct_effects_carry_their_own_timestamps() {
    rt().block_on(async {
        let mut kv = HashMap::new();
        kv.insert("a".to_string(), json!("va"));
        kv.insert("b".to_string(), json!("vb"));
        let exec = Arc::new(KvReadExecutor::new("kv", kv));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let c10: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(10.0));
        let c20: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(20.0));
        run_effect_with_clock(
            &reg,
            &store,
            &c10,
            &req("kv", "ra", json!({"key": "a"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        run_effect_with_clock(
            &reg,
            &store,
            &c20,
            &req("kv", "rb", json!({"key": "b"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(receipt_tt(&store, "kv:ra").await, 10.0);
        assert_eq!(receipt_tt(&store, "kv:rb").await, 20.0);
    });
}

// ── SystemClock produces a real, plausible epoch stamp ─────────────────────────

#[test]
fn system_clock_produces_real_epoch() {
    let clock = SystemClock::new();
    let t = clock.now();
    // sometime after 2021-01-01 (1_600_000_000) — proves the real host clock is wired
    assert!(
        t > 1_600_000_000.0,
        "system clock should return a real epoch, got {t}"
    );
}

// ── the clock is consulted only at the boundary, never by the contract ─────────

struct CountingClock {
    t: f64,
    calls: AtomicU64,
}
impl CountingClock {
    fn new(t: f64) -> Self {
        Self {
            t,
            calls: AtomicU64::new(0),
        }
    }
    fn count(&self) -> u64 {
        self.calls.load(Ordering::SeqCst)
    }
}
impl ClockProvider for CountingClock {
    fn now(&self) -> f64 {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.t
    }
}

#[test]
fn clock_consulted_only_at_boundary_not_by_contract() {
    rt().block_on(async {
        let m = IgniterMachine::new(None, "in_memory").unwrap();
        m.load_program(&[FIXTURE.to_string()], "ExecuteQuery")
            .unwrap();

        let mut kv = HashMap::new();
        kv.insert("x".to_string(), json!(1));
        let exec = Arc::new(KvReadExecutor::new(STORAGE_CAP, kv));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);

        let counting = Arc::new(CountingClock::new(500.0));
        let clock: Arc<dyn ClockProvider> = counting.clone();

        // dispatching the contract runs only the VM — it has no clock, so `now()` is never read
        let _ = m.dispatch("ExecuteQuery", json!({"plan": {}})).await;
        assert_eq!(
            counting.count(),
            0,
            "contract execution must not read the clock"
        );

        // the host boundary reads the clock exactly once to stamp the receipt
        let hr = HostRequest {
            contract: "ExecuteQuery".to_string(),
            effect: "read_file".to_string(),
            idempotency_key: "c1".to_string(),
            authority_ref: Some("passport:test".to_string()),
            args: json!({"store": "ignored", "key": "x"}),
        };
        run_service_with_clock(&m, &reg, &clock, &hr, RunMode::Live)
            .await
            .unwrap();
        assert_eq!(
            counting.count(),
            1,
            "clock read exactly once, at the boundary"
        );
        assert_eq!(
            receipt_tt(&m.storage, "IO.StorageCapability:c1").await,
            500.0
        );
    });
}
