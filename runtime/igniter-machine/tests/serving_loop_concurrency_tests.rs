//! LAB-MACHINE-SERVING-LOOP-CONCURRENCY-P13 — bounded concurrent serving loop.
//!
//! P12 proved the host shape sequentially. P13 proves the next server property: bounded concurrent
//! accept/serve while the central invariant holds —
//!   same idempotency key  → at most one effect
//!   distinct keys         → may run concurrently up to max_in_flight
//!   host still owns loop  → no daemon, no spawned/detached task
//!
//! Loopback only; fake effect executor; no live SparkCRM. The loop uses structured concurrency
//! (`FuturesUnordered`), never `tokio::spawn`, so no task can outlive `run_concurrent`.

use futures::stream::{FuturesUnordered, StreamExt};
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::observability::observe;
use igniter_machine::orchestrator::EffectOrchestrator;
use igniter_machine::retry_queue::enqueue_retry;
use igniter_machine::serving_loop::{ConcurrentServingPolicy, ServingLoop};
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteRequest};
use serde_json::json;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const CAP: &str = "IO.SparkCRM";

/// A multi-thread runtime so the IO reactor genuinely runs accepts/reads across threads. (The
/// loop's futures are still polled cooperatively by one task — it never spawns.)
fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn cpass(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    cpass(
        "vendor:acme",
        "coordination",
        &[
            "create_pool",
            "import_capsule",
            "activate_capsule",
            "grant_access",
            "accept_recipe",
            "invoke",
        ],
    )
}
async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity {
        agent_id: id.into(),
        kind,
        label: id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await
    .unwrap();
}
async fn offer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source("contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }", "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}
fn policy(mode: &str, max_fresh: u32) -> DuplicatePolicy {
    DuplicatePolicy {
        mode: mode.into(),
        key_header: "x-vendor-event-id".into(),
        max_fresh,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    }
}
fn recipe(digest: &str, n: u32, dp: DuplicatePolicy) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "Offer".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: n,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: Some(dp),
    }
}
async fn prod(n: usize, dp: DuplicatePolicy) -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = offer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &cpass("dev", "coordination", &["accept_recipe"]),
        "svc",
        recipe(&digest, n as u32, dp),
    )
    .await
    .unwrap();
    h.grant(
        &cpass("dev", "coordination", &["grant_access"]),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, r)
}
/// One real HTTP/1.1 POST (owned args so it can live in a FuturesUnordered) → status code.
async fn http_post(addr: std::net::SocketAddr, key: String, corr: String) -> u16 {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let body = json!({ "base": 1000 }).to_string();
    let req = format!(
        "POST /w HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nX-Vendor-Event-Id: {}\r\nX-Correlation-Id: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        key, corr, body.len(), body
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut resp = Vec::new();
    s.read_to_end(&mut resp).await.unwrap();
    let text = String::from_utf8_lossy(&resp).to_string();
    text.lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|x| x.parse().ok())
        .unwrap_or(0)
}
fn cfg<'a>(
    registry: &'a CapabilityExecutorRegistry,
    receipts: &'a Arc<dyn TBackend>,
    eclock: &'a Arc<dyn ClockProvider>,
    ep: &'a CapabilityPassport,
    sf: &'a SingleFlight,
) -> EffectBridgeConfig<'a> {
    EffectBridgeConfig {
        registry,
        receipts,
        effect_clock: eclock,
        effect_passport: ep,
        single_flight: sf,
        capability_id: CAP.into(),
        operation: "create_lead".into(),
        scope: "write".into(),
    }
}
fn write_req(idem: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: idem.into(),
        payload: json!({ "store": "orders", "key": format!("ord-{idem}"), "value": {"q": 1} }),
    }
}
/// Drive `keys.len()` concurrent clients (each its own vendor-event-id) against `addr`.
async fn client_storm(addr: std::net::SocketAddr, keys: &[&str]) -> Vec<u16> {
    let mut cs = FuturesUnordered::new();
    for (i, k) in keys.iter().enumerate() {
        cs.push(http_post(addr, k.to_string(), format!("c{i}")));
    }
    let mut out = Vec::new();
    while let Some(s) = cs.next().await {
        out.push(s);
    }
    out
}

// ── 1: N distinct-key requests, observed concurrency > 1, all effects run ───────────────────────
#[test]
fn concurrent_distinct_keys_run_in_parallel() {
    rt().block_on(async {
        let (h, r) = prod(4, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = cpass("host", CAP, &["write"]);
        let sf = SingleFlight::new();
        let c = cfg(&registry, &receipts, &eclock, &ep, &sf);
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &registry,
            clock: &eclock,
            passport: &ep,
            base_delay: 0.0,
        };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop {
            listener: &listener,
            router: &r,
            hub: &h,
            cfg: &c,
        };
        let pol = ConcurrentServingPolicy::new(6, 4);

        let keys = ["E1", "E2", "E3", "E4", "E5", "E6"];
        let (report, statuses) =
            tokio::join!(lp.run_concurrent(&orch, &pol), client_storm(addr, &keys));
        let report = report.unwrap();

        assert!(report.booted);
        assert_eq!(report.requests_served, 6);
        assert!(
            report.max_in_flight_observed > 1,
            "the loop genuinely served concurrently"
        );
        assert_eq!(
            report.max_in_flight_observed, 4,
            "concurrency is bounded by max_in_flight"
        );
        assert!(statuses.iter().all(|s| *s == 200));
        assert_eq!(exec.applied_count(), 6, "six distinct keys → six effects");
        assert_eq!(observe(&receipts).await.unwrap().metrics.committed, 6);
    });
}

// ── 2: same-key concurrent requests → exactly one effect + one committed receipt ────────────────
#[test]
fn concurrent_same_key_exactly_one_effect() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = cpass("host", CAP, &["write"]);
        let sf = SingleFlight::new();
        let c = cfg(&registry, &receipts, &eclock, &ep, &sf);
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &registry,
            clock: &eclock,
            passport: &ep,
            base_delay: 0.0,
        };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop {
            listener: &listener,
            router: &r,
            hub: &h,
            cfg: &c,
        };
        let pol = ConcurrentServingPolicy::new(6, 6);

        let keys = ["SAME", "SAME", "SAME", "SAME", "SAME", "SAME"];
        let (report, statuses) =
            tokio::join!(lp.run_concurrent(&orch, &pol), client_storm(addr, &keys));
        let report = report.unwrap();

        assert_eq!(report.requests_served, 6);
        assert_eq!(
            report.max_in_flight_observed, 6,
            "all six were in flight at once"
        );
        assert!(statuses.iter().all(|s| *s == 200));
        assert_eq!(
            exec.attempts(),
            1,
            "six concurrent same-key requests perform exactly one effect"
        );
        assert_eq!(
            observe(&receipts).await.unwrap().metrics.committed,
            1,
            "exactly one committed receipt"
        );
    });
}

// ── 3: distinct keys parallel WHILE same-key serialized (mixed batch) ───────────────────────────
#[test]
fn concurrent_distinct_parallel_same_key_serialized() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = cpass("host", CAP, &["write"]);
        let sf = SingleFlight::new();
        let c = cfg(&registry, &receipts, &eclock, &ep, &sf);
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &registry,
            clock: &eclock,
            passport: &ep,
            base_delay: 0.0,
        };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop {
            listener: &listener,
            router: &r,
            hub: &h,
            cfg: &c,
        };
        let pol = ConcurrentServingPolicy::new(6, 6);

        // three keys, each duplicated once, all in one concurrent batch.
        let keys = ["A", "A", "B", "B", "C", "C"];
        let (report, statuses) =
            tokio::join!(lp.run_concurrent(&orch, &pol), client_storm(addr, &keys));
        let report = report.unwrap();

        assert_eq!(report.requests_served, 6);
        assert_eq!(report.max_in_flight_observed, 6);
        assert!(statuses.iter().all(|s| *s == 200));
        // distinct keys each produce one effect (parallel); same-key collapses → 3 effects total.
        assert_eq!(
            exec.applied_count(),
            3,
            "one effect per distinct key, duplicates serialized away"
        );
        assert_eq!(observe(&receipts).await.unwrap().metrics.committed, 3);
    });
}

// ── 4: deterministic shutdown — bounded, re-entrant, no leaked task ─────────────────────────────
#[test]
fn concurrent_deterministic_shutdown_no_leak() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = cpass("host", CAP, &["write"]);
        let sf = SingleFlight::new();
        let c = cfg(&registry, &receipts, &eclock, &ep, &sf);
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &registry,
            clock: &eclock,
            passport: &ep,
            base_delay: 0.0,
        };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop {
            listener: &listener,
            router: &r,
            hub: &h,
            cfg: &c,
        };

        // First bounded concurrent run stops after exactly 3 requests.
        let pol = ConcurrentServingPolicy::new(3, 3);
        let (r1, _s) = tokio::join!(
            lp.run_concurrent(&orch, &pol),
            client_storm(addr, &["A", "B", "C"])
        );
        let r1 = r1.unwrap();
        assert_eq!(r1.requests_served, 3, "never over-serves the budget");

        // No background acceptor remained: a second run on the same instance proceeds normally.
        let pol2 = ConcurrentServingPolicy::new(2, 2);
        let (r2, _s) = tokio::join!(
            lp.run_concurrent(&orch, &pol2),
            client_storm(addr, &["D", "E"])
        );
        let r2 = r2.unwrap();
        assert_eq!(r2.requests_served, 2);
        assert!(r2.booted);
        assert_eq!(
            exec.applied_count(),
            5,
            "five distinct keys across two bounded runs → five effects"
        );
        assert_eq!(observe(&receipts).await.unwrap().metrics.committed, 5);
    });
}

// ── 5: host-owned tick still drains a due retry intent (no background scheduler) ────────────────
#[test]
fn concurrent_tick_drains_due_retry() {
    rt().block_on(async {
        let (h, r) = prod(2, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = cpass("host", CAP, &["write"]);
        let sf = SingleFlight::new();
        let c = cfg(&registry, &receipts, &eclock, &ep, &sf);
        let orch = EffectOrchestrator {
            receipts: &receipts,
            substrate: &substrate,
            registry: &registry,
            clock: &eclock,
            passport: &ep,
            base_delay: 0.0,
        };

        // a retry intent due immediately, for the SAME capability/executor.
        enqueue_retry(
            &receipts,
            &eclock,
            &write_req("R1"),
            "write",
            &ep.authority_digest(),
            3,
            0.0,
        )
        .await
        .unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop {
            listener: &listener,
            router: &r,
            hub: &h,
            cfg: &c,
        };

        // Serve two concurrent requests, then one host-owned tick on stop drains the due retry.
        let pol = ConcurrentServingPolicy::new(2, 2).tick_on_stop();
        let (report, _s) = tokio::join!(
            lp.run_concurrent(&orch, &pol),
            client_storm(addr, &["E1", "E2"])
        );
        let report = report.unwrap();

        assert_eq!(report.requests_served, 2);
        assert_eq!(
            report.ticks_run, 1,
            "exactly one host-owned tick (no background scheduler)"
        );
        assert_eq!(
            report.retries_drained, 1,
            "the due retry intent was drained"
        );
        // two served effects (E1,E2) + one drained retry (R1).
        assert_eq!(exec.applied_count(), 3);
    });
}
