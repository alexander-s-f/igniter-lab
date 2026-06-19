//! LAB-MACHINE-CAPABILITY-IO-LOAD-P24 — load/correctness evidence (local, no network).
//!
//! Evidence-only: assert CORRECTNESS first (exactly-one under a same-key storm; distinct keys
//! stay parallel; no duplicate committed effect; sane counts), then MEASURE (throughput, p50/p95/
//! p99, single-flight serialization). Real OS-thread parallelism via a multi-thread runtime — the
//! genuine stress on the atomic gate (P18) and the sharded backend. No code tuning here.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::observability::observe;
use igniter_machine::single_flight::{run_write_effect_atomic, SingleFlight};
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState};
use serde_json::json;
use std::sync::Arc;
use std::time::{Duration, Instant};

const CAP: &str = "IO.LoadCapability";

fn mrt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn passport() -> Arc<CapabilityPassport> {
    Arc::new(CapabilityPassport {
        subject: "host".into(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1e9),
        revoked: false,
        evidence_digest: "s".into(),
    })
}
fn write_req(idem: &str, v: i64) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: idem.into(),
        payload: json!({ "store": "orders", "key": format!("ord-{idem}"), "value": { "n": v } }),
    }
}
fn pct(sorted_us: &[u128], p: f64) -> u128 {
    if sorted_us.is_empty() {
        return 0;
    }
    let idx = ((sorted_us.len() as f64 - 1.0) * p).round() as usize;
    sorted_us[idx]
}
fn report(name: &str, total: usize, wall: Duration, mut lat_us: Vec<u128>) {
    lat_us.sort_unstable();
    let rps = total as f64 / wall.as_secs_f64().max(1e-9);
    eprintln!(
        "[load:{name}] n={total} wall={:.3}s throughput={:.0}/s p50={}us p95={}us p99={}us max={}us",
        wall.as_secs_f64(), rps, pct(&lat_us, 0.50), pct(&lat_us, 0.95), pct(&lat_us, 0.99),
        lat_us.last().copied().unwrap_or(0)
    );
}

// ── same-key storm: thousands of concurrent identical requests → ONE effect ────

#[test]
fn same_key_storm_one_effect() {
    mrt().block_on(async {
        const N: usize = 2000;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let reg = Arc::new(reg);
        let sf = Arc::new(SingleFlight::new());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clk = clock();
        let p = passport();
        let req = Arc::new(write_req("storm", 1));

        let start = Instant::now();
        let mut handles = Vec::with_capacity(N);
        for _ in 0..N {
            let (sf, reg, receipts, clk, p, req) = (
                sf.clone(),
                reg.clone(),
                receipts.clone(),
                clk.clone(),
                p.clone(),
                req.clone(),
            );
            handles.push(tokio::spawn(async move {
                let t = Instant::now();
                let out = run_write_effect_atomic(
                    &sf,
                    &reg,
                    &receipts,
                    &clk,
                    &p,
                    "write",
                    &req,
                    RunMode::Live,
                )
                .await
                .unwrap();
                (out.state, t.elapsed().as_micros())
            }));
        }
        let mut committed = 0;
        let mut lat = Vec::with_capacity(N);
        for h in handles {
            let (state, us) = h.await.unwrap();
            if state == WriteState::Committed {
                committed += 1;
            }
            lat.push(us);
        }
        let wall = start.elapsed();

        // CORRECTNESS FIRST
        assert_eq!(
            exec.applied_count(),
            1,
            "a same-key storm performs the effect EXACTLY ONCE"
        );
        assert_eq!(
            committed, N,
            "every request observes committed (one executed, the rest replay)"
        );
        // exactly one committed receipt fact for the storm key (plus the prepared)
        let storm = receipts
            .facts_for(RECEIPTS_STORE, "IO.LoadCapability:storm", None, None)
            .await
            .unwrap();
        assert_eq!(
            storm
                .iter()
                .filter(|f| f.value["state"] == json!("committed"))
                .count(),
            1
        );

        report("same_key_storm", N, wall, lat);
    });
}

// ── distinct keys stay parallel; one committed effect each, no duplicates ──────

#[test]
fn distinct_keys_parallel_no_duplicates() {
    mrt().block_on(async {
        const N: usize = 3000;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let reg = Arc::new(reg);
        let sf = Arc::new(SingleFlight::new());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clk = clock();
        let p = passport();

        let start = Instant::now();
        let mut handles = Vec::with_capacity(N);
        for i in 0..N {
            let (sf, reg, receipts, clk, p) = (
                sf.clone(),
                reg.clone(),
                receipts.clone(),
                clk.clone(),
                p.clone(),
            );
            let req = Arc::new(write_req(&format!("k{i}"), i as i64));
            handles.push(tokio::spawn(async move {
                let t = Instant::now();
                let out = run_write_effect_atomic(
                    &sf,
                    &reg,
                    &receipts,
                    &clk,
                    &p,
                    "write",
                    &req,
                    RunMode::Live,
                )
                .await
                .unwrap();
                (out.state, t.elapsed().as_micros())
            }));
        }
        let mut committed = 0;
        let mut lat = Vec::with_capacity(N);
        for h in handles {
            let (state, us) = h.await.unwrap();
            if state == WriteState::Committed {
                committed += 1;
            }
            lat.push(us);
        }
        let wall = start.elapsed();

        // CORRECTNESS: every distinct key commits exactly once; no duplicate committed per key
        assert_eq!(committed, N);
        assert_eq!(
            exec.applied_count(),
            N,
            "each distinct key performs its effect once"
        );
        let snap = observe(&receipts).await.unwrap();
        assert_eq!(
            snap.metrics.committed, N,
            "exactly N committed receipts — no duplicates"
        );

        report("distinct_keys", N, wall, lat);
    });
}

// ── mixed outcomes: unknown/retryable do not commit; P23 snapshot is sane ──────

#[test]
fn mixed_outcomes_snapshot_sane() {
    mrt().block_on(async {
        const N: usize = 800;
        // a timeout executor → every effect is unknown (none commits)
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let reg = Arc::new(reg);
        let sf = Arc::new(SingleFlight::new());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clk = clock();
        let p = passport();

        let mut handles = Vec::with_capacity(N);
        for i in 0..N {
            let (sf, reg, receipts, clk, p) = (
                sf.clone(),
                reg.clone(),
                receipts.clone(),
                clk.clone(),
                p.clone(),
            );
            let req = Arc::new(write_req(&format!("t{i}"), i as i64));
            handles.push(tokio::spawn(async move {
                run_write_effect_atomic(
                    &sf,
                    &reg,
                    &receipts,
                    &clk,
                    &p,
                    "write",
                    &req,
                    RunMode::Live,
                )
                .await
                .unwrap()
                .state
            }));
        }
        let mut unknown = 0;
        for h in handles {
            if h.await.unwrap() == WriteState::UnknownExternalState {
                unknown += 1;
            }
        }
        assert_eq!(
            unknown, N,
            "every timeout is unknown — none silently commits"
        );

        let snap = observe(&receipts).await.unwrap();
        assert_eq!(
            snap.metrics.committed, 0,
            "no committed effects under all-timeout load"
        );
        assert_eq!(
            snap.metrics.unknown, N,
            "all N surfaced as unknown in the P23 snapshot"
        );
        eprintln!(
            "[load:mixed] n={N} unknown={} committed={}",
            snap.metrics.unknown, snap.metrics.committed
        );
    });
}
