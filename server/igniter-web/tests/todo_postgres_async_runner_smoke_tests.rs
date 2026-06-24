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
        // P44: `delete` joins the op allowlist (mirrors host.example.toml).
        .allow_ops(&["insert", "upsert", "delete"]);
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
    eh.bind_target("todo-delete", "/w"); // P44
    eh
}

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

/// Read host with a policy matching `host_policy.md`: SELECT-only on `todos` (4 cols) and `accounts`
/// (2 cols) — the index route's two-stage account-existence read needs both allowlisted (P38).
fn make_read_host(adapter: Arc<FakePostgresAdapter>) -> StagedReadHost {
    let policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
        .allow_source("accounts", &["id", "name"]);
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

/// A single `accounts` row so the index's stage-1 existence read finds the account (P38).
fn sample_account(account_id: &str) -> Vec<Value> {
    vec![json!({"id": account_id, "name": "Test Account"})]
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

async fn get_todo_show(addr: std::net::SocketAddr, account_id: &str, todo_id: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!(
        "GET /accounts/{account_id}/todos/{todo_id} HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n"
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

async fn post_todo(addr: std::net::SocketAddr, account_id: &str, idem_key: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    // P45: the object create body is the ONLY accepted shape (legacy string body removed).
    let body = "{\"title\":\"Buy milk\"}";
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

async fn delete_todo(
    addr: std::net::SocketAddr,
    account_id: &str,
    todo_id: &str,
    idem_key: &str,
) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!(
        "DELETE /accounts/{account_id}/todos/{todo_id} HTTP/1.1\r\nHost: x\r\n\
         Authorization: Bearer vtok\r\n\
         idempotency-key: {idem_key}\r\n\
         Content-Length: 0\r\n\r\n"
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

/// GET the list with a keyset `?after=` cursor (P47). Proves the query string survives transport
/// (route matching on the query-free path) and reaches the app as `req.query`.
async fn get_todos_after(addr: std::net::SocketAddr, account_id: &str, after: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!(
        "GET /accounts/{account_id}/todos?after={after} HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n"
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

// ── 1a: keyset — `?after=` cursor flows transport → req.query → app plan `id > after` → HTTP 200 ──
//
// LAB-TODOAPP-API-PAGINATION-KEYSET-P47. A query string used to break route matching; this proves it now
// route-matches (path is query-free), the cursor reaches the app via `req.query`, and the keyset filter
// returns only rows after the cursor — DB-free (fake adapter).
#[test]
fn keyset_after_cursor_via_runner_filters_rows() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let account_id = "acct-ks-http";
    let adapter = Arc::new(
        FakePostgresAdapter::new()
            .with_table("accounts", sample_account(account_id))
            .with_table(
                "todos",
                vec![
                    json!({"id":"todo-a","account_id":account_id,"title":"a","done":"false"}),
                    json!({"id":"todo-b","account_id":account_id,"title":"b","done":"false"}),
                    json!({"id":"todo-c","account_id":account_id,"title":"c","done":"false"}),
                ],
            ),
    );
    let read_host = make_read_host(adapter.clone());

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let acct = account_id.to_string();
        // keyset after "todo-a" → expect only todo-b, todo-c (id > "todo-a").
        let client = tokio::spawn(async move { get_todos_after(addr, &acct, "todo-a").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 200, "keyset page → 200; raw={raw}");
        assert!(
            !raw.contains("todo-a"),
            "the row at/-before the cursor is excluded (proves `?after` reached the plan); raw={raw}"
        );
        assert!(
            raw.contains("todo-b") && raw.contains("todo-c"),
            "rows after the cursor are returned; raw={raw}"
        );
    });
}

// ── 1: read — found rows → AccountTodoIndexFromRows → HTTP 200 ───────────────────────────────────

#[test]
fn read_found_todos_via_runner_200() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    let account_id = "acct-p10-found";
    // P38: the account exists (stage 1) AND has todos (stage 2).
    let adapter = Arc::new(
        FakePostgresAdapter::new()
            .with_table("accounts", sample_account(account_id))
            .with_table("todos", sample_todos(account_id)),
    );
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
        assert_eq!(
            adapter.query_count(),
            2,
            "two read queries: stage-1 account existence + stage-2 todos list"
        );
    });
}

// ── 2: read — empty rows → AccountTodoIndexFromRows → HTTP 200 [] (a list, not 404) — P24 ────────

#[test]
fn read_empty_todos_via_runner_200_empty_list() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    // P38: the account EXISTS (stage 1 non-empty) but has zero todos (stage 2 empty) → 200 [].
    let adapter = Arc::new(
        FakePostgresAdapter::new()
            .with_table("accounts", sample_account("acct-p10-empty"))
            .with_table("todos", vec![]),
    );
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
            200,
            "existing account + zero todos → 200 [] (a list, not a not-found); raw={raw}"
        );
        assert!(raw.contains("[]"), "body carries the empty array; raw={raw}");
        assert_eq!(
            adapter.query_count(),
            2,
            "two read queries: account exists (stage 1) + empty todos list (stage 2)"
        );
    });
}

// ── 2a (P38): index — MISSING account → app-owned HTTP 404, todos list never read ────────────────

#[test]
fn read_missing_account_via_runner_404() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    // The accounts table has no row for the requested id → stage-1 existence read is empty → 404.
    let adapter = Arc::new(
        FakePostgresAdapter::new()
            .with_table("accounts", vec![])
            .with_table("todos", vec![]),
    );
    let read_host = make_read_host(adapter.clone());

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let client = tokio::spawn(async move { get_todos(addr, "acct-does-not-exist").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            404,
            "missing account → app-owned 404 (not a 200 []); raw={raw}"
        );
        assert!(
            raw.contains("account not found"),
            "404 body is the app's account-existence message; raw={raw}"
        );
        assert_eq!(
            adapter.query_count(),
            1,
            "only the stage-1 account read ran; the todos list was never issued"
        );
    });
}

// ── 2b: show — found row → AccountTodoShowFromRows → HTTP 200 with row JSON (P14) ────────────────

#[test]
fn show_found_todo_via_runner_200() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    let account_id = "acct-show-found";
    // FindTodo carries limit 1; the fake adapter applies the effective limit, so one row comes back.
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
        let client = tokio::spawn(async move { get_todo_show(addr, &acct, "t1").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            200,
            "show found row → HTTP 200; raw={raw}"
        );
        assert!(
            raw.contains("t1") && raw.contains("Buy milk"),
            "show response carries the row JSON (id + title), not the raw path param; raw={raw}"
        );
        assert_eq!(adapter.query_count(), 1, "one read adapter query for show");
    });
}

// ── 2c: show — no such todo → AccountTodoShowFromRows → app-owned HTTP 404 (P14) ─────────────────

#[test]
fn show_missing_todo_via_runner_404() {
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

        let client =
            tokio::spawn(async move { get_todo_show(addr, "acct-show-empty", "nope").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(
            http_status(&raw),
            404,
            "show missing todo → app-owned HTTP 404; raw={raw}"
        );
        assert!(
            raw.contains("todo not found"),
            "404 body is the app's show message; raw={raw}"
        );
        assert_eq!(
            adapter.query_count(),
            1,
            "adapter was still queried for show"
        );
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

// ── 4b: delete — removes the created row over HTTP; replay same key → no second mutation ───────────
//
// LAB-TODOAPP-API-DELETE-P44. DELETE /accounts/:id/todos/:todo_id → AccountTodoDelete → InvokeEffect
// { target: "todo-delete" } → MachineEffectHost → the write fake's DELETE branch. Create then delete
// the SAME surrogate id: the business row is gone (count 0) and replaying the delete key does not
// mutate again. A committed delete returns HTTP 200 (the chosen status, same as create/done).

#[test]
fn write_delete_via_runner_200_removes_row_and_replay() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let read_host = make_read_host(Arc::new(FakePostgresAdapter::new()));

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let acct = "acct-p44-del";
        let create_key = "evt-p44-create";
        let del_key = "evt-p44-delete";
        // The created row lands under the host-minted surrogate id; the delete route targets that id.
        let id = format!(
            "todo_{}",
            igniter_web::surrogate_id("POST", &format!("/accounts/{acct}/todos"), create_key)
        );

        // Bounded loop serves three requests: create, delete, delete-replay.
        let policy = ServingPolicy::new(3).loopback_only();
        let client = tokio::spawn(async move {
            let r_create = post_todo(addr, acct, create_key).await;
            let r_del = delete_todo(addr, acct, &id, del_key).await;
            let r_rep = delete_todo(addr, acct, &id, del_key).await;
            (r_create, r_del, r_rep)
        });
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();

        let (r_create, r_del, r_rep) = client.await.unwrap();
        assert_eq!(http_status(&r_create), 200, "create → 200; raw={r_create}");
        assert_eq!(http_status(&r_del), 200, "delete committed → 200; raw={r_del}");
        assert_eq!(http_status(&r_rep), 200, "delete replay → still 200; raw={r_rep}");
        // create (1) + delete (1); the replay deduped at the machine receipt → no third attempt.
        assert_eq!(st.adapter.attempts(), 2, "create + delete; replay deduped");
        // the created row was removed by the delete (the DELETE branch of the fake adapter).
        assert_eq!(st.adapter.business_row_count(), 0, "row removed by delete");
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

// ── P20: host-owned error contract (read-denied 403, conflict 409, unauthorized 401) ──────────────
//
// LAB-TODOAPP-API-ERROR-CONTRACT-P20. The host-owned product errors are pinned here (the app-owned
// 404/405/400 errors live in todo_error_contract_tests.rs). Each asserts status + the stable body
// shape + that nothing leaks a DSN / bearer token / raw SQL / host-config path. Host-owned bodies use
// `{"error": "<message>"}`; the app-owned not-found uses `{"body": "<message>"}` (status carries the
// class) — both are documented in API.md.

/// Read host whose policy does NOT allow the `todos` source → the app's plan is host-denied (403).
fn make_denying_read_host() -> StagedReadHost {
    let policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("some_other_table", &["x"]);
    let adapter = Arc::new(FakePostgresAdapter::new());
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP)
}

/// Extract the JSON body from a raw HTTP/1.1 response.
fn http_body_json(raw: &str) -> Value {
    let body = raw.split("\r\n\r\n").nth(1).unwrap_or("");
    serde_json::from_str(body).unwrap_or(Value::Null)
}

/// No error body may leak host-owned secrets or internals.
fn assert_no_leak(raw: &str) {
    let lower = raw.to_lowercase();
    for forbidden in [
        "postgres://",
        "password",
        "dsn",
        "bearer ",
        "select ",
        "insert into",
        "host.toml",
    ] {
        assert!(
            !lower.contains(forbidden),
            "error response leaks `{forbidden}`: {raw}"
        );
    }
}

async fn post_todo_titled(
    addr: std::net::SocketAddr,
    account_id: &str,
    idem_key: &str,
    title: &str,
) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    // P45: object create body is the only accepted shape; distinct titles → distinct payload digests.
    let body = format!("{{\"title\":\"{title}\"}}");
    let raw = format!(
        "POST /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\n\
         Authorization: Bearer vtok\r\nidempotency-key: {idem_key}\r\n\
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

async fn post_todo_noauth(addr: std::net::SocketAddr, account_id: &str, idem_key: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let body = "{\"title\":\"Buy milk\"}";
    let raw = format!(
        "POST /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\n\
         idempotency-key: {idem_key}\r\nContent-Length: {}\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

// read denied by host policy → 403 {"error": ...}; no DSN/policy-secret leak.
#[test]
fn read_denied_by_host_is_403_no_leak() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let read_host = make_denying_read_host();

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client = tokio::spawn(async move { get_todos(addr, "acct-denied").await });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 403, "host-denied read → 403; raw={raw}");
        let body = http_body_json(&raw);
        assert!(
            body.get("error").and_then(|v| v.as_str()).is_some(),
            "host error body must be {{\"error\": \"<message>\"}}; got {body}"
        );
        assert_no_leak(&raw);
    });
}

// reused idempotency key + different body → 409 {"error":"conflict"}.
#[test]
fn write_conflict_is_409_error_shape() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let read_host = make_read_host(Arc::new(FakePostgresAdapter::new()));

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let policy = ServingPolicy::new(2).loopback_only();
        let client = tokio::spawn(async move {
            let a = post_todo_titled(addr, "acct-conflict", "evt-err-conflict", "Buy milk").await;
            let b = post_todo_titled(addr, "acct-conflict", "evt-err-conflict", "Buy bread").await;
            (a, b)
        });
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let (r1, r2) = client.await.unwrap();

        assert_eq!(http_status(&r1), 200, "first create commits; raw={r1}");
        assert_eq!(
            http_status(&r2),
            409,
            "same key + different body → 409; raw={r2}"
        );
        assert_eq!(http_body_json(&r2)["error"], json!("conflict"));
        assert_no_leak(&r2);
    });
}

// missing/invalid passport → 401 {"error":"unauthorized"}.
#[test]
fn unauthorized_write_is_401_error_shape() {
    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    let read_host = make_read_host(Arc::new(FakePostgresAdapter::new()));

    rt().block_on(async {
        let (h, r) = build_write_prod().await;
        let st = build_write_effect_state();
        let c = write_bridge_cfg(&st);
        let eh = build_effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client =
            tokio::spawn(
                async move { post_todo_noauth(addr, "acct-unauth", "evt-err-unauth").await },
            );

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &eh, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 401, "no bearer → 401; raw={raw}");
        assert_eq!(http_body_json(&raw)["error"], json!("unauthorized"));
        assert_no_leak(&raw);
    });
}
