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

/// Same fixture, but entered at an arbitrary contract (used to drive the self-looping `LoopForever`).
fn load_fixture_app_with_entry(entry: &str) -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "igweb_readthen_loop_{}_{}",
        std::process::id(),
        stamp
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let fixture_path = dir.join("read_then_fixture.ig");
    std::fs::write(&fixture_path, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fixture_path],
        entry: entry.to_string(),
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
        query: Default::default(),
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

// ── 1c (P38): a self-looping ReadThen chain is BOUNDED → host 500, never an infinite loop ─────────

#[test]
fn runaway_readthen_chain_is_bounded() {
    // `LoopForever` re-issues a ReadThen naming itself every hop; the read always succeeds (rows present),
    // so only the host's MAX_READ_HOPS bound can stop it. The runner must fail closed to a 500.
    let app = load_fixture_app_with_entry("LoopForever");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let read_host = make_read_host(adapter.clone(), todos_policy(100));

    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-loop"), &read_host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(
                    response.status, 500,
                    "an unbounded continuation chain must fail closed to 500"
                );
            }
            other => panic!("expected a bounded 500 Respond, got {other:?}"),
        }
        // The adapter ran a bounded number of times — the loop did NOT spin forever.
        let n = adapter.query_count();
        assert!(n >= 1 && n <= 8, "bounded staged reads (got {n}, bound 8)");
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

// ── 8: read freshness — replay is opt-in via explicit x-correlation-id (LAB-…-READ-FRESHNESS-P23) ─
//
// `query_count()` is the probe: a REPLAY returns the cached outcome without re-entering the executor,
// so the adapter count stays flat; a FRESH run increments it.

fn freshness_req(account: &str, correlation: Option<&str>) -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: account.to_string(),
        body: Value::Null,
        correlation_id: correlation.map(|c| c.to_string()),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

fn list_plan() -> Value {
    json!({
        "source": "todos", "op": "select",
        "projection": ["id", "account_id", "title", "done"],
        "filters": [], "limit": 50
    })
}

/// No client correlation: the SAME plan run twice on one host executes twice (no stale replay), so a
/// read after a write in the same process observes the new state instead of a replayed empty list.
#[test]
fn uncorrelated_same_plan_reads_run_fresh() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let host = make_read_host(adapter.clone(), todos_policy(100));
        let plan = list_plan();

        let _ = host.execute(&plan, &freshness_req("acct-7", None)).await;
        let _ = host.execute(&plan, &freshness_req("acct-7", None)).await;

        assert_eq!(
            adapter.query_count(),
            2,
            "uncorrelated reads of the same plan must each run fresh (no cross-request replay)"
        );
    });
}

/// Explicit, equal `x-correlation-id` + same plan: the second read REPLAYS the first snapshot (the
/// intended retry semantics) — the executor is not re-entered.
#[test]
fn explicit_same_correlation_same_plan_replays() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let host = make_read_host(adapter.clone(), todos_policy(100));
        let plan = list_plan();

        let _ = host.execute(&plan, &freshness_req("acct-7", Some("corr-1"))).await;
        let _ = host.execute(&plan, &freshness_req("acct-7", Some("corr-1"))).await;

        assert_eq!(
            adapter.query_count(),
            1,
            "same explicit correlation + same plan replays (executor entered once)"
        );
    });
}

/// P12 regression: two DIFFERENT plans must never collide — even under the same/empty correlation each
/// runs its own query.
#[test]
fn distinct_plans_never_collide() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let host = make_read_host(adapter.clone(), todos_policy(100));

        let plan_a = list_plan();
        let mut plan_b = list_plan();
        plan_b["limit"] = json!(1); // a different query

        let _ = host.execute(&plan_a, &freshness_req("acct-7", Some("corr-x"))).await;
        let _ = host.execute(&plan_b, &freshness_req("acct-7", Some("corr-x"))).await;

        assert_eq!(
            adapter.query_count(),
            2,
            "distinct plans under one correlation run independently (P12 fix holds)"
        );
    });
}
