//! igniter-web/tests/todo_postgres_api_read_tests.rs — LAB-TODOAPP-API-READ-P3
//!
//! The read half of the REAL product app (`examples/todo_postgres_app`), proven over the P6 host-read
//! seam — using the app's OWN authored contracts, not a generic fixture:
//!
//!   product `ListTodosByAccount("acct-7") -> QueryPlan`
//!     → host `PostgresReadExecutor<FakePostgresAdapter>` (host `PostgresReadPolicy` gates + clamps)
//!     → rows → `rows_json` → product `AccountTodoIndexFromRows(req, rows_json) -> Decision` → Respond.
//!
//! Both ends are REAL app contracts dispatched via `IgniterMachine::dispatch` (async, direct — no
//! `IgWebServerApp::call` `block_on` nesting). NO live Postgres, NO new `.igweb` syntax / `ReadThen` arm,
//! NO write execution, NO runner productization. Gated behind `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectOutcome, EffectRequest, OutcomeKind, RunMode,
};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.PostgresRead";

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

/// Load the prelude + the PRODUCT app's `todo_handlers.ig` (its own authored contracts) into a fresh
/// machine; every contract is registered, so we can dispatch the query + continuation directly.
fn load_app_contracts() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_api_read_p3_{}_{}",
        std::process::id(),
        stamp
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    let handlers = app_dir().join("todo_handlers.ig");
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            handlers.to_string_lossy().to_string(),
        ],
        "ListTodosByAccount",
    )
    .expect("load todo_postgres_app/todo_handlers.ig contracts");
    m
}

/// Host read policy mirroring `host_policy.md`: SELECT-only on `todos`, the four product columns, tight cap.
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

/// The host side: run a QueryPlan JSON through the fake read executor under a host policy + adapter.
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

// ── 1: GET /accounts/:account_id/todos — product query → host read → product continuation → 200 ──

#[test]
fn product_todos_index_found_returns_200() {
    rt().block_on(async {
        let m = load_app_contracts();

        // the PRODUCT query contract produces a structural QueryPlan.
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7", "after": ""}))
            .await
            .unwrap();
        assert_eq!(plan["source"], json!("todos"));
        assert_eq!(plan["op"], json!("select"));
        assert_eq!(plan["filters"][0]["field"], json!("account_id"));

        // host runs the read (todos table present).
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&plan, todos_policy(100), adapter.clone()).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["count"], json!(2));
        assert_eq!(adapter.query_count(), 1);

        // rows → rows_json → the PRODUCT continuation contract.
        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let decision = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req(), "rows_json": rows_json}),
            )
            .await
            .unwrap();

        assert_eq!(decision["__arm"], json!("Respond"));
        assert_eq!(decision["status"], json!(200));
        let body = decision["body"].as_str().unwrap();
        assert!(
            body.contains("todo-1") && body.contains("Write spec"),
            "200 carries the todo-shaped rows: {body}"
        );
    });
}

// ── 2: empty rows → product continuation returns 200 [] (a list, not a not-found) — P24 ──────────

#[test]
fn product_todos_index_empty_returns_200_empty_list() {
    rt().block_on(async {
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-none", "after": ""}))
            .await
            .unwrap();

        let adapter = Arc::new(FakePostgresAdapter::new()); // allowlisted source, no data → empty.
        let out = host_read(&plan, todos_policy(100), adapter).await;
        assert_eq!(out.result["count"], json!(0));

        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        assert_eq!(rows_json, "[]");
        let decision = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req(), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(decision["__arm"], json!("Respond"));
        assert_eq!(decision["status"], json!(200), "empty list = 200 []");
        assert_eq!(decision["body"], json!("[]"), "body carries the empty array");
    });
}

// ── 3-6: host gates run BEFORE the adapter (denied source/field, raw SQL) + clamp ────────────────

#[test]
fn host_gates_before_adapter_and_clamp() {
    rt().block_on(async {
        // denied source.
        let a1 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(
            &json!({"source": "secrets", "op": "select"}),
            todos_policy(100),
            a1.clone(),
        )
        .await;
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(a1.query_count(), 0);

        // forbidden projection field.
        let a2 = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(
            &json!({"source": "todos", "projection": ["id", "ssn"]}),
            todos_policy(100),
            a2.clone(),
        )
        .await;
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(a2.query_count(), 0);

        // forbidden FILTER field.
        let a2b = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(
            &json!({"source": "todos", "filters": [{"field": "ssn", "op": "eq", "value": "x"}]}),
            todos_policy(100),
            a2b.clone(),
        )
        .await;
        assert_eq!(out.kind, OutcomeKind::Denied);
        assert_eq!(a2b.query_count(), 0);

        // raw SQL keys refused before the adapter.
        for key in ["sql", "raw_sql", "query"] {
            let a = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
            let mut plan = serde_json::Map::new();
            plan.insert(key.to_string(), json!("SELECT * FROM todos"));
            let out = host_read(&Value::Object(plan), todos_policy(100), a.clone()).await;
            assert_eq!(out.kind, OutcomeKind::PermanentFailure, "`{key}` refused");
            assert_eq!(a.query_count(), 0);
        }

        // clamp: the product contract's limit:50 clamped to a policy cap of 1.
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7", "after": ""}))
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

// ── 7: the authored product app carries no DB authority surface (code, comments stripped) ────────

#[test]
fn product_app_has_no_forbidden_surface() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();
    let routes = std::fs::read_to_string(app_dir().join("routes.igweb")).unwrap();
    let strip = |s: &str| {
        s.lines()
            .map(|l| l.split("--").next().unwrap_or(""))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let code = format!("{}\n{}", strip(&handlers), strip(&routes)).to_lowercase();
    // NOTE: `scope` is the IgWeb routing keyword (`scope "/accounts/:account_id"`), not a capability
    // scope — excluded. Capability scope/passport identity is structurally absent from `.igweb`/`.ig`.
    for forbidden in [
        "select ",
        "insert into",
        "where ",
        "capability_id",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "secret",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
    // the only DB-ish token is the logical `source: "todos"`.
    assert!(handlers.contains("source: \"todos\""));
}
