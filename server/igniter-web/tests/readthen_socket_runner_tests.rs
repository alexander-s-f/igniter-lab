//! readthen_socket_runner_tests.rs — LAB-IGNITER-WEB-READTHEN-SOCKET-RUNNER-P12
//!
//! Proves staged reads through a real `tokio::net::TcpListener`:
//!
//!   socket → serve_once_loaded_with_read
//!          → dispatch_with_read → PostgresReadExecutor (fake) → continuation
//!          → Respond{200|404|403} → HTTP wire
//!
//! The `MachineEffectHost` is constructed but not exercised here (continuations return `Respond`).
//! The code path for a continuation returning `InvokeEffect` is structurally guaranteed —
//! `dispatch_with_read` calls `map_decision` on the continuation value, which maps `InvokeEffect`
//! to `ServerDecision::InvokeEffect`, and `effect_dispatch` then routes it through `MachineEffectHost`
//! unchanged. A dedicated socket test requires a continuation fixture returning `InvokeEffect` and
//! a full write-coordinator setup — deferred to LAB-IGNITER-WEB-READTHEN-INVOKE-EFFECT-P13.
//!
//! Gated `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::CoordinationHub;
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use igniter_machine::single_flight::SingleFlight;
use igniter_server::effect_host::MachineEffectHost;
use igniter_server::serving_loop::ServingPolicy;
use igniter_web::machine_runner;
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const FIXTURE: &str = include_str!("fixtures/read_then_fixture/read_then_fixture.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn fixture_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_p12_{}_{}",
        std::process::id(),
        stamp
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let fixture_path = dir.join("read_then_fixture.ig");
    std::fs::write(&fixture_path, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fixture_path],
        entry: "FetchTodosEntry".to_string(),
    })
    .expect("load read_then_fixture for P12 socket test")
}

fn todos_policy(cap: i64) -> PostgresReadPolicy {
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP)
}

/// Rows whose `account_id` field matches the URL path (including leading `/`) so the
/// fixture filter `field=account_id op=eq value=req.path` finds them.
fn path_rows(path: &str) -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": path, "title": "Buy milk", "done": false}),
        json!({"id": "t2", "account_id": path, "title": "Write spec", "done": true}),
    ]
}

/// Minimal effect host that is never called by the staged-read path.
/// `Respond` decisions short-circuit in `effect_dispatch` before touching the host.
struct EffectHostGuard {
    router: IngressRouter,
    hub: CoordinationHub,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    clk: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}

impl EffectHostGuard {
    fn new() -> Self {
        let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clk: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(100.0));
        let hub = CoordinationHub::new(audit.clone(), clk.clone());
        Self {
            router: IngressRouter::new(),
            hub,
            registry: CapabilityExecutorRegistry::new(),
            receipts: Arc::new(InMemoryBackend::new()),
            clk,
            ep: CapabilityPassport {
                subject: "host".to_string(),
                capability_id: READ_CAP.to_string(),
                scopes: vec!["read".to_string()],
                issued_at: 0.0,
                expires_at: Some(1_000_000.0),
                revoked: false,
                evidence_digest: "stub".to_string(),
            },
            sf: SingleFlight::new(),
        }
    }

    fn build_cfg(&self) -> EffectBridgeConfig<'_> {
        EffectBridgeConfig {
            registry: &self.registry,
            receipts: &self.receipts,
            effect_clock: &self.clk,
            effect_passport: &self.ep,
            single_flight: &self.sf,
            capability_id: READ_CAP.to_string(),
            operation: "read".to_string(),
            scope: "read".to_string(),
        }
    }

    fn effect_host<'a>(&'a self, cfg: &'a EffectBridgeConfig<'a>) -> MachineEffectHost<'a> {
        MachineEffectHost::new(&self.router, &self.hub, cfg)
    }
}

async fn send_get(addr: std::net::SocketAddr, path: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!("GET {path} HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n");
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

fn http_status(raw: &str) -> u16 {
    raw.split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

// ── 1: found rows → continuation → HTTP 200 over the wire ────────────────────────────────────────

#[test]
fn found_rows_gives_http_200_over_socket() {
    let app = fixture_app();
    let path = "/acct-p12-found";
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", path_rows(path)));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let guard = EffectHostGuard::new();
        let cfg = guard.build_cfg();
        let eh = guard.effect_host(&cfg);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let path_clone = path.to_string();
        let client = tokio::spawn(async move { send_get(addr, &path_clone).await });
        machine_runner::serve_once_loaded_with_read(&listener, &app, &eh, &read_host)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 200, "found rows → HTTP 200; raw={raw}");
        assert!(raw.contains("Buy milk"), "response body includes todo title");
        assert_eq!(adapter.query_count(), 1, "one adapter query");
    });
}

// ── 2: empty rows → continuation-owned HTTP 404 over the wire ────────────────────────────────────

#[test]
fn empty_rows_gives_http_404_over_socket() {
    let app = fixture_app();
    let path = "/acct-p12-empty";
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let guard = EffectHostGuard::new();
        let cfg = guard.build_cfg();
        let eh = guard.effect_host(&cfg);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let path_clone = path.to_string();
        let client = tokio::spawn(async move { send_get(addr, &path_clone).await });
        machine_runner::serve_once_loaded_with_read(&listener, &app, &eh, &read_host)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            404,
            "empty rows → continuation-owned HTTP 404; raw={raw}"
        );
        assert_eq!(adapter.query_count(), 1, "adapter was still queried");
    });
}

// ── 3: denied source → HTTP 403 before adapter ───────────────────────────────────────────────────

#[test]
fn denied_source_gives_http_403_adapter_not_reached() {
    let app = fixture_app();
    let path = "/acct-p12-denied";
    // Policy allows "orders" only — fixture queries "todos" → Denied.
    let restrictive = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("orders", &["id"]);
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", path_rows(path)));
    let read_host = make_read_host(adapter.clone(), restrictive);

    rt().block_on(async {
        let guard = EffectHostGuard::new();
        let cfg = guard.build_cfg();
        let eh = guard.effect_host(&cfg);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let path_clone = path.to_string();
        let client = tokio::spawn(async move { send_get(addr, &path_clone).await });
        machine_runner::serve_once_loaded_with_read(&listener, &app, &eh, &read_host)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 403, "denied source → HTTP 403; raw={raw}");
        assert_eq!(adapter.query_count(), 0, "adapter must not be reached");
    });
}

// ── 4: serve_loop_loaded_with_read serves multiple requests ──────────────────────────────────────

#[test]
fn serve_loop_serves_multiple_staged_read_requests() {
    let app = fixture_app(); // already Arc<IgWebLoadedApp>
    let path = "/acct-p12-loop";
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", path_rows(path)));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let guard = EffectHostGuard::new();
        let cfg = guard.build_cfg();
        let eh = guard.effect_host(&cfg);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let policy = ServingPolicy { max_requests: 2, loopback_only: true };

        let path_clone = path.to_string();
        let client = tokio::spawn(async move {
            let r1 = send_get(addr, &path_clone).await;
            let r2 = send_get(addr, &path_clone).await;
            (r1, r2)
        });
        let report = machine_runner::serve_loop_loaded_with_read(
            &listener, &app, &eh, &read_host, &policy,
        )
        .await
        .unwrap();
        let (r1, r2) = client.await.unwrap();

        assert_eq!(http_status(&r1), 200, "first request → 200");
        assert_eq!(http_status(&r2), 200, "second request → 200");
        assert_eq!(report.requests_served, 2);
        assert!(report.is_loopback);
    });
}

// ── 5: existing P11 and P2 tests remain green ────────────────────────────────────────────────────

// (Covered by the shared --features machine test suite; marked here as an explicit acceptance gate.)
