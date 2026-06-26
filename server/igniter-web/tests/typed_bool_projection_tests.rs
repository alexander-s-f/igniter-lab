//! typed_bool_projection_tests.rs — LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION-P53
//!
//! Proves the typed-`Bool` `done` lane: a host `Boolean` decode-kind crosses into an `.ig` `Bool` field, and
//! app logic branches on it with REAL Bool semantics (`filter(t -> t.done == false/true)`), returning a typed
//! JSON summary via the P50 `RespondJson` arm — through the normal `dispatch_with_read` runner contour.
//!
//! VERIFY-FIRST: `host.toml` cannot express per-field typed kinds today (`[postgres.read] fields = "a,b,c"`
//! is a flat allowlist → `read_policy_binding` → `allow_source` → ALL Text). So the `Boolean` kind is supplied
//! via the in-Rust `allow_source_typed` (test harness only); the shipped list/show API stays `done : String`
//! (P50/P52) and is untouched. This is a PROOF-ONLY lane; the host-config syntax is a named follow-on.
//!
//! DB-free (fake adapter), `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
};
use igniter_server::protocol::{ResponseBody, ServerDecision, ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::read_materialize::{reconcile_projection, AppFieldType, ProjectionSpec};
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/typed_bool/typed_bool.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn load_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p53_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("typed_bool.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fx],
        entry: "FetchBoolTodos".to_string(),
    })
    .expect("load typed_bool fixture")
}

/// Rows with `done` as a REAL JSON bool (what a `Boolean`-decoding adapter yields).
fn bool_rows() -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": "acct-7", "title": "Buy milk",  "done": false}),
        json!({"id": "t2", "account_id": "acct-7", "title": "Write spec", "done": true}),
        json!({"id": "t3", "account_id": "acct-7", "title": "Pay bills",  "done": true}),
    ]
}

/// Policy whose `done` kind is `Boolean` (the typed lane this card validates). Only expressible via
/// `allow_source_typed` in Rust — `host.toml` cannot say this today.
fn bool_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap).allow_ops(&["select"]).allow_source_typed(
        "todos",
        &[("id", Text), ("account_id", Text), ("title", Text), ("done", Boolean)],
    )
}

/// Policy whose `done` kind is `Text` — DRIFTS against the app's `done : Bool` (`Text` ⇏ `Bool`).
fn text_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap).allow_ops(&["select"]).allow_source_typed(
        "todos",
        &[("id", Text), ("account_id", Text), ("title", Text), ("done", Text)],
    )
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
        correlation_id: Some(format!("p53-{account}")),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

fn body_of(decision: ServerDecision) -> (u16, Value) {
    match decision {
        ServerDecision::Respond { response } => {
            let status = response.status;
            let body = match response.body {
                ResponseBody::Json(v) => v,
                ResponseBody::Raw { bytes, .. } => {
                    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
                }
            };
            (status, body)
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

// ── host Boolean kind → .ig Bool → filter in BOTH directions → typed JSON summary ───────────────────

#[test]
fn boolean_kind_crosses_and_filters_both_directions() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", bool_rows()));
    let host = make_read_host(adapter.clone(), bool_policy(100));

    rt().block_on(async {
        let (status, body) = body_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        // Real Bool semantics: 1 pending (done==false), 2 done (done==true), total 3.
        assert_eq!(body["total"], json!(3));
        assert_eq!(body["pending"], json!(1), "filter(t -> t.done == false)");
        assert_eq!(body["done_count"], json!(2), "filter(t -> t.done == true)");
        assert_eq!(body["all_done"], json!(false), "not all done");
        assert_eq!(adapter.query_count(), 1);
    });
}

#[test]
fn all_done_when_every_row_is_true() {
    let app = load_app();
    let rows = vec![
        json!({"id": "t1", "account_id": "acct-7", "title": "a", "done": true}),
        json!({"id": "t2", "account_id": "acct-7", "title": "b", "done": true}),
    ];
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", rows));
    let host = make_read_host(adapter, bool_policy(100));
    rt().block_on(async {
        let (status, body) = body_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert_eq!(body["pending"], json!(0));
        assert_eq!(body["done_count"], json!(2));
        assert_eq!(body["all_done"], json!(true), "every row done → all_done true (Bool from Integer compare)");
    });
}

#[test]
fn empty_is_all_done_false() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
    let host = make_read_host(adapter, bool_policy(100));
    rt().block_on(async {
        let (status, body) = body_of(app.dispatch_with_read(get_req("acct-none"), &host).await);
        assert_eq!(status, 200);
        assert_eq!(body["total"], json!(0));
        assert_eq!(body["all_done"], json!(false), "empty → not all_done (guarded)");
    });
}

// ── drift: host `Text` vs app `Bool` fails closed BEFORE the read/continuation ──────────────────────

#[test]
fn text_host_vs_bool_app_drifts_before_dispatch() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", bool_rows()));
    let host = make_read_host(adapter.clone(), text_policy(100));
    rt().block_on(async {
        let (status, body) = body_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 500, "host Text `done` vs app `Bool` → drift, fail closed");
        assert_eq!(body["error"]["code"], json!("projection_schema_drift"));
        assert!(body["error"]["message"].as_str().unwrap().contains("done"));
        assert_eq!(adapter.query_count(), 0, "reconcile fails before the adapter");
    });
}

// ── reverse drift (matrix symmetry): host `Boolean` vs app `String` is NOT assignable → drift ───────

#[test]
fn boolean_host_vs_string_app_is_drift() {
    // The reverse direction, proven at the reconciliation level: a `Boolean` host kind only lands in `Bool`,
    // never `String` — so a String-typed app row over a Boolean source fails closed.
    let spec = ProjectionSpec::from_policy(
        &bool_policy(100),
        "todos",
        &["id", "account_id", "title", "done"].map(String::from),
    );
    let string_app_row = vec![
        ("id".to_string(), AppFieldType::String),
        ("account_id".to_string(), AppFieldType::String),
        ("title".to_string(), AppFieldType::String),
        ("done".to_string(), AppFieldType::String), // ← String over a Boolean host kind
    ];
    let err = reconcile_projection(&spec, &string_app_row).unwrap_err();
    assert!(err.starts_with("ProjectionSchemaDrift"), "{err}");
    assert!(err.contains("`done`"), "{err}");

    // And the matched direction reconciles clean (Boolean → Bool).
    let bool_app_row = vec![
        ("id".to_string(), AppFieldType::String),
        ("account_id".to_string(), AppFieldType::String),
        ("title".to_string(), AppFieldType::String),
        ("done".to_string(), AppFieldType::Bool),
    ];
    assert!(reconcile_projection(&spec, &bool_app_row).is_ok());
}
