//! readthen_dispatch_tests.rs — LAB-IGNITER-WEB-READTHEN-DISPATCH-P11
//!
//! Proves the staged-read surface:
//!
//!   FetchTodosEntry(req) -> ReadThen { plan, then: "FetchTodosContinuation" }
//!   host executes plan through fake PostgresReadExecutor (allowlist + clamp)
//!   host dispatches FetchTodosContinuation(req, rows_json) -> final Decision
//!
//! All assertions use `IgWebLoadedApp::dispatch_with_read` — no `block_on` nesting.
//! Gated `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode,
};
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use igniter_server::protocol::{ResponseBody, ServerDecision, ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/read_then_fixture/read_then_fixture.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk",  "done": false}),
        json!({"id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true}),
    ]
}

/// Build the loaded app from the read_then_fixture inline source.
/// `build_igweb_loaded_app` auto-injects the IgWebPrelude — pass only the fixture file.
fn load_fixture_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_readthen_p11_{}_{}",
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
    .expect("load read_then_fixture")
}

/// Build a host policy: SELECT-only on `todos`, four allowed columns, cap clamp.
fn todos_policy(cap: i64) -> PostgresReadPolicy {
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}

/// Build a `StagedReadHost` with the given adapter and policy.
fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP)
}

fn get_req(path: &str) -> ServerRequest {
    // `path` is used as account_id by FetchTodosEntry (fixture simplification)
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: path.to_string(),
        body: Value::Null,
        correlation_id: Some(format!("test-{path}")),
        idempotency_key: None,
        headers: Default::default(),
    }
}

// ── 1: found rows → continuation → 200 ───────────────────────────────────────────────────────────

#[test]
fn found_rows_flow_to_continuation_200() {
    let app = load_fixture_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &read_host).await;

        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 200, "found rows → 200");
                let body_str = match &response.body {
                    ResponseBody::Json(v) => v.to_string(),
                    ResponseBody::Raw { bytes, .. } => {
                        std::str::from_utf8(bytes).unwrap_or("").to_string()
                    }
                };
                assert!(body_str.contains("todo-1"), "body must contain todo-1");
                assert!(
                    body_str.contains("Write spec"),
                    "body must contain second todo"
                );
            }
            other => panic!("expected Respond, got {other:?}"),
        }
        assert_eq!(adapter.query_count(), 1, "exactly one adapter query");
    });
}

// ── 2: empty rows → continuation-owned 404 (not an infra error) ──────────────────────────────────

#[test]
fn empty_rows_gives_continuation_owned_404() {
    let app = load_fixture_app();
    // adapter has the `todos` source but no rows for this account
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let decision = app
            .dispatch_with_read(get_req("acct-empty"), &read_host)
            .await;

        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 404, "empty rows → continuation-owned 404");
            }
            other => panic!("expected Respond, got {other:?}"),
        }
        assert_eq!(adapter.query_count(), 1, "adapter was still queried");
    });
}

// ── 3: denied source → host 403 before adapter ───────────────────────────────────────────────────

#[test]
fn denied_source_gives_host_403_before_adapter() {
    let app = load_fixture_app();
    // The fixture queries `todos` but we give it a policy that only allows `orders` — denied.
    let restrictive_policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("orders", &["id"]);
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let read_host = make_read_host(adapter.clone(), restrictive_policy);

    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &read_host).await;

        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 403, "denied source → host 403");
            }
            other => panic!("expected Respond 403, got {other:?}"),
        }
        assert_eq!(adapter.query_count(), 0, "adapter must not be reached");
    });
}

// ── 4: raw SQL key → permanent refusal before adapter ────────────────────────────────────────────

#[test]
fn raw_sql_key_in_plan_is_refused_before_adapter() {
    // Directly prove the PostgresReadExecutor gate (matches the host_gates test from P6).
    rt().block_on(async {
        let policy = todos_policy(100);
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter.clone(), policy));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec);
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        let raw_sql_req = EffectRequest {
            capability_id: READ_CAP.to_string(),
            idempotency_key: "raw-sql-test".to_string(),
            authority_ref: None,
            args: json!({"sql": "SELECT * FROM todos"}),
        };
        let outcome = run_effect(&registry, &receipts, &raw_sql_req, RunMode::Live)
            .await
            .expect("run_effect should not error");

        assert!(
            matches!(outcome.kind, OutcomeKind::Denied),
            "raw SQL key → Denied before adapter"
        );
        assert_eq!(adapter.query_count(), 0, "adapter must not be reached");
    });
}

// ── 5: no nested block_on — dispatch_with_read is purely async ───────────────────────────────────

#[test]
fn dispatch_with_read_has_no_nested_block_on() {
    // This test runs entirely inside a tokio runtime. If dispatch_with_read called block_on,
    // the runtime would panic with "cannot block the async runtime".
    let app = load_fixture_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let read_host = make_read_host(adapter, todos_policy(100));

    rt().block_on(async {
        // If block_on were nested, this would panic. Reaching the assertion proves safety.
        let decision = app.dispatch_with_read(get_req("acct-7"), &read_host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(
                    response.status, 200,
                    "async dispatch succeeded without nesting"
                );
            }
            other => panic!("expected Respond 200, got {other:?}"),
        }
    });
}

// ── 6: authored fixture has no forbidden authority surface ────────────────────────────────────────

#[test]
fn fixture_carries_no_authority_surface() {
    let code = FIXTURE.to_lowercase();
    let forbidden = [
        "capability_id",
        "io.postgresread",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "select ",
        "insert into",
        "scope",
    ];
    for f in forbidden {
        assert!(!code.contains(f), "fixture must not contain `{f}`");
    }
    // Fixture must only name logical `then` target, not capability wiring
    assert!(code.contains("readthen"), "fixture uses ReadThen arm");
    assert!(
        code.contains("fetchtodoscontinuation"),
        "fixture names continuation by contract name only"
    );
}

// ── 7: P6 existing direct-dispatch tests still green ────────────────────────────────────────────

// (Covered by `todo_postgres_read_host_tests.rs` running in the same feature-gated suite.
// This comment marks the acceptance criterion explicitly.)
