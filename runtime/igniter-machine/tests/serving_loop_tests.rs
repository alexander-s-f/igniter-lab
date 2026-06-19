//! LAB-MACHINE-SERVING-LOOP-P12 — host-owned serving loop over wire-to-effect.
//!
//! Proves the missing in-lab host shell: one `ServingLoop` instance boots recovery once, then
//! processes several real loopback HTTP requests through the proven `serve_once_effect` contour,
//! runs the orchestrator tick on a host-owned cadence to drain due retries, and stops on a
//! bounded condition (max_requests) with no background task left behind.
//!
//! Local loopback only; fake effect executor; no live SparkCRM. The loop adds no new effect or
//! coordination semantics — duplicate same-key requests still produce exactly one effect.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::observability::observe;
use igniter_machine::orchestrator::EffectOrchestrator;
use igniter_machine::retry_queue::enqueue_retry;
use igniter_machine::serving_loop::{ServingLoop, ServingPolicy};
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteRequest};
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const CAP: &str = "IO.SparkCRM";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn cpass(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(), capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0, expires_at: Some(1_000_000.0), revoked: false, evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    cpass("vendor:acme", "coordination", &["create_pool", "import_capsule", "activate_capsule", "grant_access", "accept_recipe", "invoke"])
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}
async fn offer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source("contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }", "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}
fn policy(mode: &str, max_fresh: u32) -> DuplicatePolicy {
    DuplicatePolicy { mode: mode.into(), key_header: "x-vendor-event-id".into(), max_fresh, after_limit: "dedup_last".into(), seed_field: "attempt".into(), variant_payload: false, require_key: true }
}
fn recipe(digest: &str, n: u32, dp: DuplicatePolicy) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(), capsule_digest: digest.into(), entry_contract: "Offer".into(),
        input_schema_digest: None, capability_bindings: vec![], required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(), retry_policy_ref: None, pool_sizing: n,
        created_by: "alice".into(), accepted_by: None, accepted_at: None, duplicate_policy: Some(dp),
    }
}

/// Build a production-ready hub + router for the `/w` route. Mirrors the proven P11 harness.
async fn prod(n: usize, dp: DuplicatePolicy) -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = offer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h.add_capsule(&vendor(), "svc", bytes.clone(), vec![]).await.unwrap().capsule_id;
    }
    h.accept_recipe(&cpass("dev", "coordination", &["accept_recipe"]), "svc", recipe(&digest, n as u32, dp)).await.unwrap();
    h.grant(&cpass("dev", "coordination", &["grant_access"]), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, r)
}

/// One real HTTP/1.1 POST → status code.
async fn http_post(addr: std::net::SocketAddr, key: &str, base: i64, corr: &str) -> u16 {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let body = json!({ "base": base }).to_string();
    let req = format!(
        "POST /w HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nX-Vendor-Event-Id: {}\r\nX-Correlation-Id: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        key, corr, body.len(), body
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut resp = Vec::new();
    s.read_to_end(&mut resp).await.unwrap();
    let text = String::from_utf8_lossy(&resp).to_string();
    text.lines().next().and_then(|l| l.split_whitespace().nth(1)).and_then(|x| x.parse().ok()).unwrap_or(0)
}

fn cfg<'a>(registry: &'a CapabilityExecutorRegistry, receipts: &'a Arc<dyn TBackend>, eclock: &'a Arc<dyn ClockProvider>, ep: &'a CapabilityPassport, sf: &'a SingleFlight) -> EffectBridgeConfig<'a> {
    EffectBridgeConfig { registry, receipts, effect_clock: eclock, effect_passport: ep, single_flight: sf, capability_id: CAP.into(), operation: "create_lead".into(), scope: "write".into() }
}

fn write_req(idem: &str, value: Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(), operation: "put".into(), idempotency_key: idem.into(),
        payload: json!({ "store": "orders", "key": format!("ord-{idem}"), "value": value }),
    }
}

// ── 1: one loop instance processes at least two requests; report/observe stay queryable ───────
#[test]
fn loop_serves_two_requests() {
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
        let orch = EffectOrchestrator { receipts: &receipts, substrate: &substrate, registry: &registry, clock: &eclock, passport: &ep, base_delay: 0.0 };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop { listener: &listener, router: &r, hub: &h, cfg: &c };

        // One loop instance serves two distinct-key requests; clients run concurrently.
        let pol = ServingPolicy::serve(2);
        let (report, s1, s2) = tokio::join!(
            lp.run(&orch, &pol),
            http_post(addr, "E1", 1000, "c1"),
            http_post(addr, "E2", 2000, "c2"),
        );
        let report = report.unwrap();
        assert!(report.booted, "loop boots recovery once before serving");
        assert_eq!(report.requests_served, 2, "one loop instance processed two requests");
        assert_eq!(s1, 200);
        assert_eq!(s2, 200);
        assert_eq!(exec.applied_count(), 2, "two distinct keys → two effects");

        // Observability remains a pure projection from facts — not a side-log inside the loop.
        let snap = observe(&receipts).await.unwrap();
        assert_eq!(snap.metrics.committed, 2, "observe() projects two committed effects from receipts");
        // The orchestrator report is queryable after the loop, too.
        assert_eq!(orch.report().await.unwrap().receipts_committed, 2);
    });
}

// ── 2: duplicate same-key requests through the loop produce exactly one effect ────────────────
#[test]
fn loop_dedup_same_key_one_effect() {
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
        let orch = EffectOrchestrator { receipts: &receipts, substrate: &substrate, registry: &registry, clock: &eclock, passport: &ep, base_delay: 0.0 };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop { listener: &listener, router: &r, hub: &h, cfg: &c };

        // Two requests, SAME vendor event id → dedup_strict → at most one effect ever.
        let pol = ServingPolicy::serve(2);
        let (report, s1, s2) = tokio::join!(
            lp.run(&orch, &pol),
            http_post(addr, "E1", 1000, "c1"),
            http_post(addr, "E1", 1000, "c2"),
        );
        let report = report.unwrap();
        assert_eq!(report.requests_served, 2, "the loop processed both requests");
        assert_eq!(s1, 200);
        assert_eq!(s2, 200);
        assert_eq!(exec.attempts(), 1, "duplicate same-key over the loop performs exactly one effect");
        assert_eq!(observe(&receipts).await.unwrap().metrics.committed, 1, "exactly one committed receipt");
    });
}

// ── 3: host-owned tick drains a due retry intent while the loop shape stays host-owned ────────
#[test]
fn loop_tick_drains_due_retry() {
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
        let orch = EffectOrchestrator { receipts: &receipts, substrate: &substrate, registry: &registry, clock: &eclock, passport: &ep, base_delay: 0.0 };

        // A retry intent due immediately (base_delay 0), for the SAME capability/executor.
        enqueue_retry(&receipts, &eclock, &write_req("R1", json!({"qty": 1})), "write", &ep.authority_digest(), 3, 0.0).await.unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop { listener: &listener, router: &r, hub: &h, cfg: &c };

        // Serve one request, then run a host-owned tick on stop → the due retry is drained.
        let pol = ServingPolicy::serve(1).tick_on_stop();
        let (report, s1) = tokio::join!(
            lp.run(&orch, &pol),
            http_post(addr, "E1", 1000, "c1"),
        );
        let report = report.unwrap();
        assert_eq!(s1, 200);
        assert_eq!(report.requests_served, 1);
        assert_eq!(report.ticks_run, 1, "the host ran one tick (its own cadence, no daemon)");
        assert_eq!(report.retries_drained, 1, "the due retry intent was drained by the tick");
        // Served effect (E1) + drained retry (R1) both reached the executor.
        assert_eq!(exec.applied_count(), 2, "one served effect + one drained retry");
    });
}

// ── 4: deterministic shutdown — bounded, re-entrant, no leaked acceptor; system stays queryable ─
#[test]
fn loop_deterministic_shutdown_no_leak() {
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
        let orch = EffectOrchestrator { receipts: &receipts, substrate: &substrate, registry: &registry, clock: &eclock, passport: &ep, base_delay: 0.0 };

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let lp = ServingLoop { listener: &listener, router: &r, hub: &h, cfg: &c };

        // First bounded run stops after exactly one request.
        let pol = ServingPolicy::serve(1);
        let (r1, _s) = tokio::join!(lp.run(&orch, &pol), http_post(addr, "E1", 1000, "c1"));
        let r1 = r1.unwrap();
        assert_eq!(r1.requests_served, 1, "stops after exactly max_requests — never over-serves");

        // The loop left no background acceptor: the same listener is idle and a SECOND bounded run
        // on the same instance proceeds normally (re-entrant, nothing lingering from run #1).
        let (r2, _s) = tokio::join!(lp.run(&orch, &pol), http_post(addr, "E2", 2000, "c2"));
        let r2 = r2.unwrap();
        assert_eq!(r2.requests_served, 1);
        assert!(r2.booted, "each run boots recovery once (idempotent)");

        // Two requests across two bounded runs → two effects; the system is still queryable.
        assert_eq!(exec.applied_count(), 2);
        assert_eq!(observe(&receipts).await.unwrap().metrics.committed, 2);
        assert_eq!(orch.report().await.unwrap().receipts_committed, 2);
    });
}
