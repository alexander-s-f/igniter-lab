//! LAB-MACHINE-IGNITER-SERVER-EFFECT-P3 — `InvokeEffect` executed through the machine contour.
//!
//! These tests are gated behind the `machine` feature (run with `cargo test --features machine`).
//! They prove the server protocol's `ServerDecision::InvokeEffect`, decided by a fixture `ServerApp`,
//! executes through the EXISTING `igniter-machine` wire-to-effect path (`IngressRouter::handle_effect`
//! / `run_write_effect_atomic`) with the same exactly-one semantics as direct ingress.
//!
//! Local loopback only · fake effect executor · neutral names (no SparkCRM) · no DB/live · no daemon.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRequest, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};

use igniter_server::effect_host::{
    serve_loop_effect, serve_once_effect, serve_once_effect_reloadable, MachineEffectHost,
};
use igniter_server::fixture::DemoApp;
use igniter_server::protocol::{
    AppIdentity, ServerApp, ServerDecision, ServerRequest, ServerResponse,
};
use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::ServingPolicy;

use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const CAP: &str = "IO.Demo"; // neutral — NOT a SparkCRM capability.

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
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
    m.load_contract_source(
        "contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }",
        "Offer",
    )
    .unwrap();
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
/// Build a production pool + accepted recipe + granted vendor + ingress route `/w` → pool `svc`.
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

/// Per-test effect-side state. Kept together so `cfg()` can borrow each piece.
struct EffectState {
    exec: Arc<FakeWriteExecutor>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}
fn effect_state(behavior: WriteBehavior) -> EffectState {
    let exec = Arc::new(FakeWriteExecutor::new(CAP, behavior));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec.clone());
    EffectState {
        exec,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", CAP, &["write"]),
        sf: SingleFlight::new(),
    }
}
fn cfg(s: &EffectState) -> EffectBridgeConfig<'_> {
    EffectBridgeConfig {
        registry: &s.registry,
        receipts: &s.receipts,
        effect_clock: &s.eclock,
        effect_passport: &s.ep,
        single_flight: &s.sf,
        capability_id: CAP.into(),
        operation: "create_record".into(),
        scope: "write".into(),
    }
}

/// One real HTTP/1.1 POST to the SERVER → (status, body json). Drives the loopback socket.
async fn server_post(
    addr: std::net::SocketAddr,
    path: &str,
    key: &str,
    corr: &str,
    base: i64,
) -> (u16, Value) {
    let mut s = TcpStream::connect(addr).await.unwrap();
    let body = json!({ "base": base }).to_string();
    let req = format!(
        "POST {} HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer vtok\r\nX-Vendor-Event-Id: {}\r\nX-Correlation-Id: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
        path, key, corr, body.len(), body
    );
    s.write_all(req.as_bytes()).await.unwrap();
    let mut resp = Vec::new();
    s.read_to_end(&mut resp).await.unwrap();
    let text = String::from_utf8_lossy(&resp).to_string();
    let status = text
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|x| x.parse().ok())
        .unwrap_or(0);
    let body_start = text.find("\r\n\r\n").map(|i| i + 4).unwrap_or(text.len());
    let body_json: Value = serde_json::from_str(text[body_start..].trim()).unwrap_or(Value::Null);
    (status, body_json)
}

/// A `MachineEffectHost` with the infra binding `demo-effect -> /w` (what `DemoApp` decides).
fn effect_host<'a>(
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(router, hub, cfg);
    eh.bind_target("demo-effect", "/w");
    eh
}

// ── 1: real loopback HTTP through igniter-server → committed effect via the machine contour ───────
#[test]
fn server_invoke_effect_commits_via_machine_contour() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = DemoApp;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (_srv, (status, body)) = tokio::join!(
            serve_once_effect(&listener, &app, &eh),
            server_post(addr, "/effect/record", "E1", "c1", 1000),
        );

        assert_eq!(status, 200, "committed effect → 200, body={body}");
        assert_eq!(body["status"], json!("committed"));
        assert_eq!(st.exec.attempts(), 1, "exactly one effect performed");
    });
}

// ── 2: dedup_strict replay through the server path → NO second effect ─────────────────────────────
#[test]
fn server_invoke_effect_replay_no_second_effect() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = DemoApp;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (_s1, (st1, _)) = tokio::join!(
            serve_once_effect(&listener, &app, &eh),
            server_post(addr, "/effect/record", "E1", "c1", 1000)
        );
        let (_s2, (st2, _)) = tokio::join!(
            serve_once_effect(&listener, &app, &eh),
            server_post(addr, "/effect/record", "E1", "c2", 1000)
        );

        assert_eq!(st1, 200);
        assert_eq!(st2, 200);
        assert_eq!(
            st.exec.attempts(),
            1,
            "server replay performs no second effect"
        );
    });
}

// ── 3: bounded_fresh through the server path → distinct effect idem keys by attempt_index ─────────
#[test]
fn server_invoke_effect_bounded_fresh_attempts_match_ingress() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("bounded_fresh", 6)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = DemoApp;

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        for i in 0..3 {
            let corr = format!("c{i}");
            let (_s, _b) = tokio::join!(
                serve_once_effect(&listener, &app, &eh),
                server_post(addr, "/effect/record", "E1", &corr, 1000)
            );
        }

        assert_eq!(
            st.exec.applied_count(),
            3,
            "three fresh attempts → three distinct effects"
        );
        // distinct effect idempotency keys = CAP:duplicate_key:attempt (matches direct ingress).
        assert!(st
            .receipts
            .read_as_of("__receipts__", "IO.Demo:E1:0", f64::MAX)
            .await
            .unwrap()
            .is_some());
        assert!(st
            .receipts
            .read_as_of("__receipts__", "IO.Demo:E1:2", f64::MAX)
            .await
            .unwrap()
            .is_some());
    });
}

// ── 4: server-mediated path == direct ingress (normalized status + body) ──────────────────────────
#[test]
fn server_path_matches_direct_ingress_normalized() {
    rt().block_on(async {
        // server-mediated: ServerApp → InvokeEffect → adapter → handle_effect.
        let (h1, r1) = prod(3, policy("dedup_strict", 0)).await;
        let st1 = effect_state(WriteBehavior::Commit);
        let c1 = cfg(&st1);
        let eh = effect_host(&r1, &h1, &c1);
        let app = DemoApp;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (_s, (sstatus, sbody)) = tokio::join!(
            serve_once_effect(&listener, &app, &eh),
            server_post(addr, "/effect/record", "E1", "c1", 1000)
        );

        // direct ingress on an IDENTICAL fixture: build the IngressRequest by hand.
        let (h2, r2) = prod(3, policy("dedup_strict", 0)).await;
        let st2 = effect_state(WriteBehavior::Commit);
        let c2 = cfg(&st2);
        let mut headers = HashMap::new();
        headers.insert("authorization".to_string(), "Bearer vtok".to_string());
        headers.insert("x-vendor-event-id".to_string(), "E1".to_string());
        headers.insert("x-correlation-id".to_string(), "c1".to_string());
        let ingress = IngressRequest {
            method: "POST".into(),
            path: "/w".into(),
            headers,
            body: json!({ "base": 1000 }),
        };
        let direct = r2.handle_effect(&h2, &ingress, &c2).await;

        assert_eq!(
            sstatus, direct.status,
            "status equal across server-mediated and direct ingress"
        );
        assert_eq!(
            sbody, direct.body,
            "body equal across server-mediated and direct ingress"
        );
        assert_eq!(st1.exec.attempts(), st2.exec.attempts());
    });
}

// ── 5: routing still lives in the app — same host, different app routes differently ──────────────
#[test]
fn server_routing_still_lives_in_app() {
    rt().block_on(async {
        // An app that does NOT route /effect/* to an effect — it answers 404 there and routes a
        // different path to InvokeEffect. The host (serve_once_effect + adapter) is unchanged.
        struct OtherApp;
        impl ServerApp for OtherApp {
            fn call(&self, req: ServerRequest) -> ServerDecision {
                match (req.method.as_str(), req.path.as_str()) {
                    ("POST", "/different-effect") => ServerDecision::InvokeEffect {
                        target: "demo-effect".into(),
                        input: req.body,
                        correlation_id: req.correlation_id,
                        idempotency_key: req.idempotency_key,
                    },
                    _ => ServerDecision::Respond {
                        response: ServerResponse::json(
                            404,
                            json!({ "error": "other-app: no route" }),
                        ),
                    },
                }
            }
        }

        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let app = OtherApp;

        // /effect/record (DemoApp's effect route) is a plain 404 here — the host has no route table.
        let l1 = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let a1 = l1.local_addr().unwrap();
        let (_s, (status1, body1)) = tokio::join!(
            serve_once_effect(&l1, &app, &eh),
            server_post(a1, "/effect/record", "E1", "c1", 1000)
        );
        assert_eq!(status1, 404);
        assert_eq!(body1["error"], json!("other-app: no route"));
        assert_eq!(
            st.exec.attempts(),
            0,
            "no effect: this app does not route there"
        );

        // the path THIS app routes to an effect commits through the same host/adapter.
        let l2 = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let a2 = l2.local_addr().unwrap();
        let (_s2, (status2, body2)) = tokio::join!(
            serve_once_effect(&l2, &app, &eh),
            server_post(a2, "/different-effect", "E2", "c2", 1000)
        );
        assert_eq!(status2, 200);
        assert_eq!(body2["status"], json!("committed"));
        assert_eq!(st.exec.attempts(), 1);
    });
}

// ── 7: reloadable effect path still uses MachineEffectHost / P3 contour; replay no second effect ──
#[test]
fn reloadable_effect_path_uses_machine_host() {
    // A v2 app that still routes /effect/* to the same InvokeEffect target (no effect identity).
    struct EffectAppV2;
    impl ServerApp for EffectAppV2 {
        fn call(&self, req: ServerRequest) -> ServerDecision {
            match (req.method.as_str(), req.path.as_str()) {
                ("POST", p) if p.starts_with("/effect/") => ServerDecision::InvokeEffect {
                    target: "demo-effect".into(),
                    input: req.body,
                    correlation_id: req.correlation_id,
                    idempotency_key: req.idempotency_key,
                },
                _ => ServerDecision::Respond {
                    response: ServerResponse::json(404, json!({ "error": "v2: no route" })),
                },
            }
        }
        fn identity(&self) -> AppIdentity {
            AppIdentity::new("demo", "v2", "")
        }
    }

    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let reload = ReloadableApp::new(Arc::new(DemoApp));

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // request 1 through v1 (DemoApp) → committed via the P3 machine contour.
        let (_s1, (st1, b1)) = tokio::join!(
            serve_once_effect_reloadable(&listener, &reload, &eh),
            server_post(addr, "/effect/record", "E1", "c1", 1000)
        );
        assert_eq!(st1, 200);
        assert_eq!(b1["status"], json!("committed"));

        // operator reloads the app between requests.
        reload.swap(Arc::new(EffectAppV2));
        assert_eq!(reload.identity().version, "v2");

        // request 2 (same key) through the reloaded v2 app → replay, NO second effect.
        let (_s2, (st2, _)) = tokio::join!(
            serve_once_effect_reloadable(&listener, &reload, &eh),
            server_post(addr, "/effect/record", "E1", "c2", 1000)
        );
        assert_eq!(st2, 200);
        assert_eq!(
            st.exec.attempts(),
            1,
            "reloaded app still routes through MachineEffectHost; replay performs no second effect"
        );
    });
}

// ── 8: bounded effect serving loop over a reloadable app → P3 contour, replay no second effect ───
#[test]
fn loop_effect_path_replay_no_second_effect() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);
        let reload = ReloadableApp::new(Arc::new(DemoApp));

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let pol = ServingPolicy::new(2);

        // the bounded loop serves 2 requests while a client posts the SAME key twice.
        let (report, _client) =
            tokio::join!(serve_loop_effect(&listener, &reload, &eh, &pol), async {
                let a = server_post(addr, "/effect/record", "E1", "c1", 1000).await;
                let b = server_post(addr, "/effect/record", "E1", "c2", 1000).await;
                (a, b)
            });
        let report = report.unwrap();

        assert_eq!(
            report.requests_served, 2,
            "loop served exactly two and returned"
        );
        assert_eq!(
            report.app_versions_seen,
            vec!["v0", "v0"],
            "DemoApp identity observed per request"
        );
        assert_eq!(
            st.exec.attempts(),
            1,
            "replay through the loop + P3 contour performs no second effect"
        );
    });
}

// ── 6: concurrent same-key through the server adapter → exactly one effect (SingleFlight) ─────────
#[test]
fn server_concurrent_same_key_exactly_one_effect() {
    rt().block_on(async {
        let (h, r) = prod(3, policy("dedup_strict", 0)).await;
        let st = effect_state(WriteBehavior::Commit);
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        // Four concurrent InvokeEffect dispatches with the SAME duplicate key, sharing the host's
        // one SingleFlight (via cfg). They run through the adapter → handle_effect concurrently.
        let mut req = ServerRequest::new("POST", "/effect/record", json!({ "base": 1000 }));
        req.headers
            .insert("authorization".into(), "Bearer vtok".into());
        req.headers
            .insert("x-vendor-event-id".into(), "SAME".into());
        req.headers.insert("x-correlation-id".into(), "c0".into());
        let input = json!({ "base": 1000 });

        let f = || eh.run_invoke_effect(&req, "demo-effect", &input, Some("c0".into()), None);
        let (r0, r1, r2, r3) = tokio::join!(f(), f(), f(), f());

        for resp in [&r0, &r1, &r2, &r3] {
            assert_eq!(
                resp.status, 200,
                "all four collapse to the same committed result"
            );
        }
        assert_eq!(
            st.exec.attempts(),
            1,
            "four concurrent same-key requests perform exactly one effect"
        );
        assert!(st
            .receipts
            .read_as_of("__receipts__", "IO.Demo:SAME:0", f64::MAX)
            .await
            .unwrap()
            .is_some());
    });
}
