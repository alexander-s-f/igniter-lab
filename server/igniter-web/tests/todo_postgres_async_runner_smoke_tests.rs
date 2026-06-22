//! todo_postgres_async_runner_smoke_tests.rs — LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10
//!
//! Proves the `examples/todo_postgres_app` through the productized async runner path
//! (`serve_loop_loaded_with_read`), composing:
//!
//!   READ:  GET /accounts/:id/todos
//!            → AccountTodoIndex → ReadThen { plan, then: "AccountTodoIndexFromRows" }
//!            → StagedReadHost (FakePostgresAdapter, host-owned policy)
//!            → AccountTodoIndexFromRows(req, rows_json) → Respond{200|404}
//!
//!   WRITE: POST /accounts/:id/todos
//!            → AccountTodoCreate → InvokeEffect { target: "todo-create", ... }
//!            → MachineEffectHost (FakePostgresWriteAdapter, IntentBridgeExecutor)
//!            → committed receipt; replay same key → no second mutation
//!
//! All requests served through `serve_loop_loaded_with_read`. No bespoke fixture app — uses
//! `examples/todo_postgres_app` sources. No live Postgres. Gated `--features machine`.
#![cfg(feature = "machine")]

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome,
    EffectRequest,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use igniter_machine::postgres_write::{
    FakePostgresWriteAdapter, FakeWriteBehavior, PostgresWriteExecutor, PostgresWritePolicy,
};
use igniter_machine::single_flight::SingleFlight;
use igniter_server::effect_host::MachineEffectHost;
use igniter_server::serving_loop::ServingPolicy;
use igniter_web::machine_runner;
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::runner::build_loaded_app_from_dir;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const READ_CAP: &str = "IO.PostgresRead";
const WRITE_CAP: &str = "IO.TodoWrite";

// ── scaffolding ───────────────────────────────────────────────────────────────────────────────────

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

/// Thin executor decorator that unwraps the bridge envelope `{ intent: <WriteIntent> }` before
/// passing to `PostgresWriteExecutor::execute`. Identical shape to async_machine_runner_tests.
struct IntentBridgeExecutor {
    cap: String,
    inner: PostgresWriteExecutor<FakePostgresWriteAdapter>,
}
#[async_trait]
impl CapabilityExecutor for IntentBridgeExecutor {
    fn capability_id(&self) -> &str {
        &self.cap
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        let intent = req
            .args
            .get("intent")
            .cloned()
            .unwrap_or_else(|| req.args.clone());
        self.inner
            .execute(&EffectRequest {
                capability_id: req.capability_id.clone(),
                idempotency_key: req.idempotency_key.clone(),
                authority_ref: req.authority_ref.clone(),
                args: intent,
            })
            .await
    }
}

async fn shaping_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract ShapeTodoWrite {\n\
         input operation : String\n  input target : String\n  input key : String\n\
         input values : Unknown\n  input correlation_id : String\n\
         compute intent = { operation: operation, target: target, key: key, values: values, correlation_id: correlation_id }\n\
         output intent : Unknown\n}",
        "ShapeTodoWrite",
    )
    .unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn dup_policy() -> DuplicatePolicy {
    DuplicatePolicy {
        mode: "dedup_strict".into(),
        key_header: "idempotency-key".into(),
        max_fresh: 0,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    }
}

fn service_recipe(digest: &str, n: u32) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "ShapeTodoWrite".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: n,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: Some(dup_policy()),
    }
}

/// Build the write-ready coordination hub + ingress router (3 shaping capsules, recipe accepted).
async fn build_write_prod() -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = shaping_capsule_bytes().await;
    let mut digest = String::new();
    for _ in 0..3 {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &cpass("dev", "coordination", &["accept_recipe"]),
        "svc",
        service_recipe(&digest, 3),
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

struct WriteEffectState {
    adapter: Arc<FakePostgresWriteAdapter>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}

fn build_write_effect_state() -> WriteEffectState {
    let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let policy = PostgresWritePolicy::new()
        .allow_target("todos")
        .allow_ops(&["insert", "upsert"]);
    let inner = PostgresWriteExecutor::new(WRITE_CAP, adapter.clone(), policy);
    let exec = Arc::new(IntentBridgeExecutor {
        cap: WRITE_CAP.into(),
        inner,
    });
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    WriteEffectState {
        adapter,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", WRITE_CAP, &["write"]),
        sf: SingleFlight::new(),
    }
}

fn write_bridge_cfg(s: &WriteEffectState) -> EffectBridgeConfig<'_> {
    EffectBridgeConfig {
        registry: &s.registry,
        receipts: &s.receipts,
        effect_clock: &s.eclock,
        effect_passport: &s.ep,
        single_flight: &s.sf,
        capability_id: WRITE_CAP.into(),
        operation: "write_record".into(),
        scope: "write".into(),
    }
}

fn build_effect_host<'a>(
    r: &'a IngressRouter,
    h: &'a CoordinationHub,
    c: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(r, h, c);
    eh.bind_target("todo-create", "/w");
    eh.bind_target("todo-done", "/w");
    eh
}

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

/// Read host with a policy matching `host_policy.md`: SELECT-only on `todos`, 4 columns.
fn make_read_host(adapter: Arc<FakePostgresAdapter>) -> StagedReadHost {
    let policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"]);
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP)
}

fn sample_todos(account_id: &str) -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": account_id, "title": "Buy milk", "done": false}),
        json!({"id": "t2", "account_id": account_id, "title": "Write spec", "done": true}),
    ]
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────────────────────────

async fn get_todos(addr: std::net::SocketAddr, account_id: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!(
        "GET /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n"
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

async fn post_todo(addr: std::net::SocketAddr, account_id: &str, idem_key: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let body = "{}";
    let raw = format!(
        "POST /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\n\
         Authorization: Bearer vtok\r\n\
         idempotency-key: {idem_key}\r\n\
         Content-Length: {}\r\n\r\n{}",
        body.len(),
        body
    );
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

// ── 1: read — found rows → AccountTodoIndexFromRows → HTTP 200 ───────────────────────────────────

#[test]
fn read_found_todos_via_runner_200() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    let account_id = "acct-p10-found";
    let adapter =
        Arc::new(FakePostgresAdapter::new().with_table("todos", sample_todos(account_id)));
    let read_host = make_read_host(adapter.clone());

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let acct = account_id.to_string();
        let client = tokio::spawn(async move { get_todos(addr, &acct).await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 200, "found rows → HTTP 200; raw={raw}");
        assert!(
            raw.contains("Buy milk"),
            "response body carries the first todo title"
        );
        assert!(
            raw.contains("Write spec"),
            "response body carries the second todo title"
        );
        assert_eq!(adapter.query_count(), 1, "one read adapter query");
    });
}

// ── 2: read — empty rows → AccountTodoIndexFromRows → app-owned HTTP 404 ─────────────────────────

#[test]
fn read_empty_todos_via_runner_404() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
    let read_host = make_read_host(adapter.clone());

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let client = tokio::spawn(async move { get_todos(addr, "acct-p10-empty").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            404,
            "empty rows → app-owned HTTP 404; raw={raw}"
        );
        assert_eq!(adapter.query_count(), 1, "adapter was still queried");
    });
}

// ── 3: write — keyed create → committed receipt → HTTP 200 ───────────────────────────────────────

#[test]
fn write_create_todo_via_runner_committed() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    // Read host present but not exercised by POST (AccountTodoCreate emits InvokeEffect directly).
    let read_host = make_read_host(Arc::new(FakePostgresAdapter::new()));

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let client =
            tokio::spawn(async move { post_todo(addr, "acct-p10-write", "evt-p10-c1").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            200,
            "committed write → HTTP 200; raw={raw}"
        );
        assert!(
            raw.contains("committed"),
            "response body confirms committed status"
        );
        assert_eq!(st.adapter.attempts(), 1, "one write adapter attempt");
        assert_eq!(
            st.adapter.business_row_count(),
            1,
            "one business row committed"
        );
        assert_eq!(
            st.adapter.effect_receipt_count(),
            1,
            "one effect receipt written"
        );
    });
}

// ── 4: write — replay same idempotency key → no second mutation ───────────────────────────────────

#[test]
fn write_replay_same_key_no_second_mutation() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let read_host = make_read_host(Arc::new(FakePostgresAdapter::new()));

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Bounded loop serves two requests (original + replay).
        let policy = ServingPolicy::new(2).loopback_only();
        let client = tokio::spawn(async move {
            let r1 = post_todo(addr, "acct-p10-replay", "evt-p10-replay").await;
            let r2 = post_todo(addr, "acct-p10-replay", "evt-p10-replay").await;
            (r1, r2)
        });
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();

        let (r1, r2) = client.await.unwrap();
        assert_eq!(http_status(&r1), 200, "first create → 200; raw={r1}");
        assert_eq!(http_status(&r2), 200, "replay → still 200; raw={r2}");
        assert_eq!(
            st.adapter.attempts(),
            1,
            "same key → machine dedup: only one adapter attempt"
        );
        assert_eq!(
            st.adapter.business_row_count(),
            1,
            "only one business row committed"
        );
    });
}

// ── 5: app files carry no forbidden authority surface ─────────────────────────────────────────────

#[test]
fn app_files_carry_no_forbidden_authority_surface() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();
    let routes = std::fs::read_to_string(app_dir().join("routes.igweb")).unwrap();
    let strip = |s: &str| {
        s.lines()
            .map(|l| l.split("--").next().unwrap_or(""))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let code = format!("{}\n{}", strip(&handlers), strip(&routes)).to_lowercase();
    for forbidden in [
        "capability_id",
        "io.postgresread",
        "io.todowrite",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "secret",
        "[effects]",
        "select ",
        "insert into",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
    assert!(
        handlers.contains("\"todo-create\""),
        "only logical effect targets"
    );
    assert!(
        handlers.contains("source: \"todos\""),
        "only logical DB source names"
    );
    assert!(
        handlers.contains("ReadThen"),
        "index handler now emits ReadThen"
    );
}
