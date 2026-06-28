//! typed_readthen_tests.rs — LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7
//!
//! Lifts the P6 typed-row crossing into the NORMAL `ReadThen` runner contour. An entry contract returns
//! `ReadThen { plan, then, carry }`; `IgWebLoadedApp::dispatch_with_read` inspects the named continuation's
//! COMPILED inputs (from `machine.registry`, never authored source) and chooses the crossing:
//!
//!   FetchTypedTodos  -> ReadThen{then:"TypedTodoIndexFromRows"}  (rows : Collection[TodoRow] + meta) -> typed
//!   FetchLegacyTodos -> ReadThen{then:"LegacyTodoIndexFromRows"} (rows_json : String)               -> legacy
//!
//! For the typed lane the host reconciles its `PostgresReadPolicy` field-kinds against the recovered `TodoRow`
//! shape BEFORE dispatch (drift → fail closed). DB-free, fake adapter, `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use igniter_server::protocol::{ResponseBody, ServerDecision, ServerRequest, PROTOCOL_VERSION};
use igniter_web::host_binding::read_policy_binding;
use igniter_web::host_config::parse_host_config;
use igniter_web::read_continuation::{app_row_shape, classify_continuation, ReadContinuationShape};
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::read_materialize::AppFieldType;
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/typed_readthen/typed_readthen.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn tmp_fixture() -> std::path::PathBuf {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p7_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("typed_readthen.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    fx
}

/// Loaded app entered at `entry` (drives `dispatch_with_read`'s first dispatch).
fn load_app(entry: &str) -> Arc<igniter_web::IgWebLoadedApp> {
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![tmp_fixture()],
        entry: entry.to_string(),
    })
    .expect("load typed_readthen fixture")
}

/// A bare machine (prelude + fixture) for classification / app-row-shape metadata unit tests.
fn load_machine() -> IgniterMachine {
    let fx = tmp_fixture();
    let pl = fx.with_file_name("prelude.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            fx.to_string_lossy().to_string(),
        ],
        "FetchTypedTodos",
    )
    .expect("load program");
    m
}

fn typed_rows() -> Vec<Value> {
    vec![
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk",  "done": false, "rank": 10}),
        json!({"id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true,  "rank": 20}),
    ]
}

/// Host policy whose field kinds MATCH `TodoRow` (done : Bool, rank : Integer, rest Text).
fn matched_policy(cap: i64) -> PostgresReadPolicy {
    let cfg = parse_host_config(&format!(
        "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\n\
         fields = \"id,account_id,title,done,rank\"\nrow_limit = \"{cap}\"\n\
         [postgres.read.todos.fields]\ndone = \"bool\"\nrank = \"integer\"\n"
    ))
    .expect("typed ReadThen host config");
    read_policy_binding(cfg.postgres_read.as_ref().unwrap()).policy
}

/// Host policy that DRIFTS from `TodoRow`: `done` decoded as Text, but the app declares `done : Bool`.
fn drift_policy(cap: i64) -> PostgresReadPolicy {
    let cfg = parse_host_config(&format!(
        "[postgres.read]\ndsn_env = \"R\"\nsource = \"todos\"\n\
         fields = \"id,account_id,title,done,rank\"\nrow_limit = \"{cap}\"\n\
         [postgres.read.todos.fields]\ndone = \"text\"\nrank = \"integer\"\n"
    ))
    .expect("drift ReadThen host config");
    read_policy_binding(cfg.postgres_read.as_ref().unwrap()).policy
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy.clone()));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP).with_read_policy(policy)
}

fn get_req(account: &str) -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: account.to_string(),
        body: Value::Null,
        correlation_id: Some(format!("p7-{account}")),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

fn body_json(response: &igniter_server::protocol::ServerResponse) -> Value {
    match &response.body {
        ResponseBody::Json(v) => v.clone(),
        ResponseBody::Raw { bytes, .. } => serde_json::from_slice(bytes)
            .unwrap_or(Value::String(String::from_utf8_lossy(bytes).to_string())),
    }
}

// ── verify-first: classification + app-row-shape come from compiled metadata, not source parsing ────

#[test]
fn classify_reads_compiled_input_shapes() {
    let m = load_machine();
    match classify_continuation(&m, "TypedTodoIndexFromRows") {
        ReadContinuationShape::TypedRows {
            row_type,
            declares_meta,
        } => {
            assert_eq!(row_type, "TodoRow");
            assert!(declares_meta, "continuation declares meta : DatasetMeta");
        }
        other => panic!("expected TypedRows, got {other:?}"),
    }
    assert_eq!(
        classify_continuation(&m, "LegacyTodoIndexFromRows"),
        ReadContinuationShape::LegacyRowsJson
    );
    match classify_continuation(&m, "NoSuchContract") {
        ReadContinuationShape::Invalid(_) => {}
        other => panic!("expected Invalid for unknown contract, got {other:?}"),
    }
}

#[test]
fn app_row_shape_recovers_field_types_from_type_defs() {
    let m = load_machine();
    let shape = app_row_shape(&m, "TodoRow").expect("recover TodoRow shape");
    // Sorted by field name; recovered from the persisted type_env (not source parse).
    assert_eq!(
        shape,
        vec![
            ("account_id".to_string(), AppFieldType::String),
            ("done".to_string(), AppFieldType::Bool),
            ("id".to_string(), AppFieldType::String),
            ("rank".to_string(), AppFieldType::Integer),
            ("title".to_string(), AppFieldType::String),
        ]
    );
    assert!(
        app_row_shape(&m, "NoSuchType").is_err(),
        "unknown type fails closed"
    );
}

// ── typed lane: auto-routed through dispatch_with_read (no direct execute_typed) ─────────────────────

#[test]
fn typed_lane_auto_routes_and_crosses_rows_and_meta() {
    let app = load_app("FetchTypedTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    let host = make_read_host(adapter.clone(), matched_policy(100));

    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 200, "typed found rows → 200 RespondView");
                let body = body_json(&response);
                // RespondView body root IS the View object (kind = meta.source; items = pending rows).
                assert_eq!(body["kind"], json!("todos"), "view tagged with meta.source");
                let items = body["items"].as_array().unwrap();
                assert_eq!(items.len(), 1, "only the pending (done==false) row");
                assert_eq!(
                    items[0]["label"],
                    json!("Buy milk"),
                    "r.title via map+call_contract"
                );
            }
            other => panic!("expected Respond, got {other:?}"),
        }
        assert_eq!(adapter.query_count(), 1);
    });
}

#[test]
fn typed_lane_empty_is_app_not_found_404() {
    let app = load_app("FetchTypedTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    let host = make_read_host(adapter, matched_policy(100));
    rt().block_on(async {
        // acct-none matches no rows → empty typed collection → continuation-owned 404.
        let decision = app.dispatch_with_read(get_req("acct-none"), &host).await;
        match decision {
            ServerDecision::Respond { response } => assert_eq!(response.status, 404),
            other => panic!("expected Respond 404, got {other:?}"),
        }
    });
}

// ── legacy lane: same loop, routed to the rows_json path by metadata ─────────────────────────────────

#[test]
fn legacy_lane_still_routes_to_rows_json() {
    let app = load_app("FetchLegacyTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    let host = make_read_host(adapter, matched_policy(100));
    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 200);
                let body = body_json(&response);
                // Legacy continuation echoes the rows_json string in `{ "body": "<json>" }`.
                let s = body["body"].as_str().unwrap();
                assert!(
                    s.starts_with('[') && s.contains("todo-1"),
                    "rows_json string body: {s}"
                );
            }
            other => panic!("expected Respond 200, got {other:?}"),
        }
    });
}

// ── drift: host done:Text vs TodoRow.done:Bool fails closed BEFORE the read, never partial ──────────

#[test]
fn schema_drift_fails_closed_before_dispatch() {
    let app = load_app("FetchTypedTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    let host = make_read_host(adapter.clone(), drift_policy(100));
    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 500, "drift → fail closed");
                let body = body_json(&response);
                assert_eq!(body["error"]["code"], json!("projection_schema_drift"));
                assert!(body["error"]["message"].as_str().unwrap().contains("done"));
            }
            other => panic!("expected Respond 500, got {other:?}"),
        }
        assert_eq!(
            adapter.query_count(),
            0,
            "reconcile fails BEFORE the adapter is reached"
        );
    });
}

// ── per-request row-shape mismatch → 502 (host promise violation), not app 4xx, not partial ────────

#[test]
fn row_shape_mismatch_maps_to_502() {
    let app = load_app("FetchTypedTodos");
    // Matched policy (reconcile passes), but a row is missing `done` → materialize refuses.
    let bad =
        vec![json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "rank": 10})];
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", bad));
    let host = make_read_host(adapter.clone(), matched_policy(100));
    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(
                    response.status, 502,
                    "host could not honor the typed projection"
                );
                let body = body_json(&response);
                assert_eq!(body["error"]["code"], json!("projection_row_mismatch"));
            }
            other => panic!("expected Respond 502, got {other:?}"),
        }
        assert_eq!(
            adapter.query_count(),
            1,
            "the read ran; the materializer refused after"
        );
    });
}

// ── denied source stays 403 before the adapter (denial precedes reconcile for an un-typed source) ───

#[test]
fn denied_source_stays_403() {
    let app = load_app("FetchTypedTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    // Policy allows only `orders`; the plan reads `todos` → denied by the executor.
    let policy = PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("orders", &["id"]);
    let host = make_read_host(adapter.clone(), policy);
    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 403, "denied source → 403")
            }
            other => panic!("expected Respond 403, got {other:?}"),
        }
        assert_eq!(adapter.query_count(), 0, "denied before the adapter");
    });
}

// ── a typed continuation with no read policy attached fails closed (not a blind projection) ─────────

#[test]
fn typed_without_policy_fails_closed() {
    let app = load_app("FetchTypedTodos");
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_rows()));
    // make_read_host attaches a policy; here we build one WITHOUT with_read_policy.
    let exec = Arc::new(PostgresReadExecutor::new(
        READ_CAP,
        adapter,
        matched_policy(100),
    ));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let host = StagedReadHost::new(registry, receipts, READ_CAP); // no .with_read_policy

    rt().block_on(async {
        let decision = app.dispatch_with_read(get_req("acct-7"), &host).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 500);
                let body = body_json(&response);
                assert_eq!(body["error"]["code"], json!("typed_read_unconfigured"));
            }
            other => panic!("expected Respond 500, got {other:?}"),
        }
    });
}
