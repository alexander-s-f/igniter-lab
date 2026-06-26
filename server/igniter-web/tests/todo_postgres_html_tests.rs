//! todo_postgres_html_tests.rs — LAB-TODOAPP-VIEW-DB-BACKED-TODO-HTML-P21
//!
//! The product HTML payoff: the REAL `examples/todo_postgres_app` now serves one HTML page
//! (`GET /accounts/:account_id/todos.html`) that reads Todo rows through the SAME host `ReadThen` path the
//! JSON index uses, and renders escaped text/html via `RenderView` — no `rows_json`, no request-body artifact
//! JSON, no manual HTML strings. The row type matches the host policy exactly (`done` decodes as Text, so
//! `TodoHtmlRow.done : String`). DB-free (fake adapter), `--features machine`. JSON API routes untouched.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
};
use igniter_server::protocol::{ResponseBody, ServerDecision, ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::runner::build_loaded_app_from_dir;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn app_dir() -> PathBuf {
    PathBuf::from(format!("{}/examples/todo_postgres_app", env!("CARGO_MANIFEST_DIR")))
}

/// Build the REAL product app from the example dir (routes.igweb + todo_handlers.ig + igweb.toml).
fn load_product_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let (app, _manifest) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    app
}

/// The PRODUCT host read policy (mirrors host.example.toml): `todos` fields as a bare allowlist → all Text;
/// `accounts` for the JSON index's existence check. `with_read_policy` enables the P7 typed crossing.
fn product_policy(cap: i64) -> PostgresReadPolicy {
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
        .allow_source("accounts", &["id", "name"])
}

/// A drift policy: host decodes `done` as Boolean, but `TodoHtmlRow.done : String` — not assignable → drift.
fn drift_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap).allow_ops(&["select"]).allow_source_typed(
        "todos",
        &[
            ("id", Text),
            ("account_id", Text),
            ("title", Text),
            ("done", Boolean), // ← drift vs TodoHtmlRow.done : String
        ],
    )
}

/// Todo rows as the Text-decoding adapter yields them — `done` is a STRING (matches the host policy).
fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": "acct-7", "title": "Buy milk <script>", "done": "false"}),
        json!({"id": "t2", "account_id": "acct-7", "title": "Write spec",         "done": "true"}),
    ]
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy.clone()));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP).with_read_policy(policy)
}

fn html_req(account: &str) -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: format!("/accounts/{account}/todos.html"),
        body: Value::Null,
        correlation_id: Some(format!("p21-{account}")),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

fn html_of(decision: ServerDecision) -> (u16, String, String) {
    match decision {
        ServerDecision::Respond { response } => {
            let status = response.status;
            match response.body {
                ResponseBody::Raw { bytes, content_type } => {
                    (status, content_type, String::from_utf8_lossy(&bytes).to_string())
                }
                ResponseBody::Json(v) => (status, "application/json".to_string(), v.to_string()),
            }
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

// ── found rows → escaped HTML with per-row detail links ─────────────────────────────────────────────

#[test]
fn db_backed_todos_render_escaped_html_with_links() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter.clone(), product_policy(100));

    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(html_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");
        assert!(html.contains("<h1>Todos</h1>"), "page title: {html}");
        // Per-row detail link to the JSON show route, built from String fields.
        assert!(
            html.contains("href=\"/accounts/acct-7/todos/t1\""),
            "per-row detail link from row id: {html}"
        );
        assert!(html.contains("href=\"/accounts/acct-7/todos/t2\""), "second row link: {html}");
        // Title escaped by the renderer; no raw markup.
        assert!(html.contains("Buy milk &lt;script&gt;"), "title escaped: {html}");
        assert!(!html.contains("<script>"), "no raw script: {html}");
        // Not truncated (cap 100 ≥ rows) → no load-more.
        assert!(!html.contains("Load more"), "no load-more when not truncated: {html}");
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── empty rows → app-owned empty state (200), not a host error ──────────────────────────────────────

#[test]
fn db_backed_empty_renders_app_owned_empty_state() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter, product_policy(100));
    rt().block_on(async {
        // acct-none matches no rows.
        let (status, ctype, html) = html_of(app.dispatch_with_read(html_req("acct-none"), &host).await);
        assert_eq!(status, 200, "empty state is app-owned 200");
        assert!(ctype.contains("text/html"));
        assert!(html.contains("No todos yet"), "empty-state label: {html}");
    });
}

// ── truncated read → keyset load-more href ?after=<last_id> ─────────────────────────────────────────

#[test]
fn db_backed_truncated_renders_keyset_load_more() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    // cap 1 clamps the contract's limit → one row (t1) crosses, meta.truncated = true.
    let host = make_read_host(adapter, product_policy(1));
    rt().block_on(async {
        let (status, _ctype, html) = html_of(app.dispatch_with_read(html_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert!(
            html.contains("href=\"?after=t1\""),
            "keyset load-more href from last crossed row id: {html}"
        );
        assert!(html.contains("Load more"), "{html}");
    });
}

// ── projection drift (host done:Boolean vs TodoHtmlRow.done:String) fails before HTML rendering ─────

#[test]
fn db_backed_drift_fails_before_render() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter.clone(), drift_policy(100));
    rt().block_on(async {
        let (status, ctype, body) = html_of(app.dispatch_with_read(html_req("acct-7"), &host).await);
        assert_eq!(status, 500, "drift → fail closed");
        assert!(!ctype.contains("text/html"), "no HTML produced on drift");
        assert!(body.contains("projection_schema_drift"), "{body}");
        assert_eq!(adapter.query_count(), 0, "reconcile fails before the read");
    });
}
