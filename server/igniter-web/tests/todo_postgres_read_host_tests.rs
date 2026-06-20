//! igniter-web/tests/todo_postgres_read_host_tests.rs — LAB-IGNITER-WEB-READ-GUARD-HOST-P6
//!
//! The first mid-request READ seam, proven as a direct-dispatch harness (mirrors the P4 write proof):
//!
//!   .ig `ListTodosByAccount` → QueryPlan  → host runs it through the fake `PostgresReadExecutor`
//!     (host `PostgresReadPolicy` gates + clamps) → rows → `rows_json` → .ig `TodoIndexFromRows` → Respond.
//!
//! Both `.ig` ends are REAL contracts dispatched via `IgniterMachine::dispatch` (async, called directly —
//! NOT through `IgWebServerApp::call`, so no `block_on` nesting). NO live Postgres, NO new `.igweb` syntax,
//! NO `ReadThen` prelude arm, NO runner productization. Gated behind `--features machine` (heavy proof).
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, EffectOutcome, OutcomeKind, RunMode,
};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/read_harness/read_harness.ig");
const CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

/// Load the prelude + the authored read fixture into a fresh machine (every contract registered).
fn load_machine() -> IgniterMachine {
    let dir = std::env::temp_dir().join(format!("igweb_read_p6_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let fx = dir.join("read_harness.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    std::fs::write(&fx, FIXTURE).unwrap();
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            fx.to_string_lossy().to_string(),
        ],
        "ListTodosByAccount",
    )
    .expect("load read fixture");
    m
}

/// Host read policy: SELECT-only on `todos`, the four allowed columns, a tight row cap to prove clamp.
fn todos_policy(cap: i64) -> PostgresReadPolicy {
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}

fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": false}),
        json!({"id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true}),
    ]
}

fn min_req() -> Value {
    json!({"method": "GET", "path": "/accounts/acct-7/todos", "body": "",
           "correlation_id": "", "idempotency_key": ""})
}

/// Run a QueryPlan JSON through the fake read executor under a host policy + adapter (the host side).
async fn host_read(
    plan: &Value,
    policy: PostgresReadPolicy,
    adapter: Arc<FakePostgresAdapter>,
) -> EffectOutcome {
    let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter, policy));
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    let store: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let req = EffectRequest {
        capability_id: CAP.to_string(),
        idempotency_key: "rq".to_string(),
        authority_ref: Some("passport:test".to_string()),
        args: plan.clone(),
    };
    run_effect(&reg, &store, &req, RunMode::Live).await.unwrap()
}

// ── 1: full seam — query contract → host read → rows_json → continuation → 200 with rows ──────────

#[test]
fn found_rows_flow_query_to_continuation_200() {
    rt().block_on(async {
        let m = load_machine();

        // (1) the authored query contract produces a structural QueryPlan.
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7"}))
            .await
            .unwrap();
        assert_eq!(plan["source"], json!("todos"));
        assert_eq!(plan["op"], json!("select"));
        assert_eq!(plan["filters"][0]["field"], json!("account_id"));

        // (2) the HOST runs it through the fake read executor (todos table present).
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&plan, todos_policy(100), adapter.clone()).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["count"], json!(2));
        assert_eq!(adapter.query_count(), 1);

        // (3) rows → rows_json → the authored continuation.
        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let decision = m
            .dispatch(
                "TodoIndexFromRows",
                json!({"req": min_req(), "rows_json": rows_json}),
            )
            .await
            .unwrap();

        // (4) the continuation returned a final Respond 200 carrying the rows.
        assert_eq!(decision["__arm"], json!("Respond"));
        assert_eq!(decision["status"], json!(200));
        let body = decision["body"].as_str().unwrap();
        assert!(body.contains("todo-1") && body.contains("Write spec"));
    });
}

// ── 2: empty rows → app-owned 404 (not an infra error) ───────────────────────────────────────────

#[test]
fn empty_rows_are_app_not_found_404() {
    rt().block_on(async {
        let m = load_machine();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-none"}))
            .await
            .unwrap();

        // an allowlisted source the fake has no data for → definite empty (Succeeded, 0 rows).
        let adapter = Arc::new(FakePostgresAdapter::new());
        let out = host_read(&plan, todos_policy(100), adapter).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["count"], json!(0));

        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        assert_eq!(rows_json, "[]");
        let decision = m
            .dispatch(
                "TodoIndexFromRows",
                json!({"req": min_req(), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(decision["__arm"], json!("Respond"));
        assert_eq!(decision["status"], json!(404), "empty rows = app not-found");
    });
}

// ── 3-6: host gates run BEFORE the adapter (denied source/field, raw SQL) + clamp ────────────────

#[test]
fn host_gates_before_adapter_and_clamp() {
    rt().block_on(async {
        // denied source (not allowlisted) → Denied, adapter untouched.
        let a1 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&json!({"source": "secrets", "op": "select"}), todos_policy(100), a1.clone()).await;
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(a1.query_count(), 0, "denied source never reaches the adapter");

        // forbidden projection field → Denied, adapter untouched.
        let a2 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(
            &json!({"source": "todos", "projection": ["id", "ssn"]}),
            todos_policy(100),
            a2.clone(),
        )
        .await;
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(a2.query_count(), 0);

        // raw SQL key → permanent refusal before the adapter.
        let a3 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&json!({"sql": "SELECT * FROM todos"}), todos_policy(100), a3.clone()).await;
        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert_eq!(a3.query_count(), 0);

        // row-limit clamp: the contract's limit:50 clamped to a policy cap of 1.
        let m = load_machine();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7"}))
            .await
            .unwrap();
        let a4 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&plan, todos_policy(1), a4).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["effective_limit"], json!(1));
        assert_eq!(out.result["row_limit_clamped"], json!(true));
        assert_eq!(out.result["count"], json!(1));
    });
}

// ── 7: the authored `.ig` carries no capability id / scope / DSN / raw SQL ────────────────────────

#[test]
fn authored_fixture_has_no_forbidden_surface() {
    let code: String = FIXTURE
        .lines()
        .map(|l| l.split("--").next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n")
        .to_lowercase();
    for forbidden in [
        "select ", "insert into", "where ", "capability_id", "io.postgres", "passport", "dsn",
        "postgres://", "scope",
    ] {
        assert!(!code.contains(forbidden), "authored .ig must not contain `{forbidden}`");
    }
    // the only DB-ish token is the logical `source` field of QueryPlan.
    assert!(FIXTURE.contains("source: \"todos\""));
}
