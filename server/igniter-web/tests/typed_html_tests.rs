//! typed_html_tests.rs — LAB-TODOAPP-VIEW-TYPED-ROWS-HTML-P18
//!
//! The product join: host DB-shaped rows → typed app rows → real escaped `text/html`, through the NORMAL
//! runner contour.
//!
//!   FetchTodoHtml -> ReadThen{then:"TodoHtmlFromRows"}
//!     -> dispatch_with_read materializes rows : Collection[TodoRow] + meta : DatasetMeta
//!     -> filter(pending) -> map(-> HtmlNode via TodoRowLabel) -> FormView -> RenderView
//!     -> igniter-render-html -> escaped text/html bytes
//!
//! No `rows_json : String`, no request-body artifact JSON, no manual HTML strings. DB-free, fake adapter,
//! `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
};
use igniter_server::protocol::{ResponseBody, ServerDecision, ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_dispatch::StagedReadHost;
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/typed_html/typed_html.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn load_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p18_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("typed_html.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fx],
        entry: "FetchTodoHtml".to_string(),
    })
    .expect("load typed_html fixture")
}

/// Rows with one pending malicious-title row, one done row, and a second pending row (order check).
fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": "acct-7", "title": "Buy milk <script>", "done": false, "rank": 10}),
        json!({"id": "t2", "account_id": "acct-7", "title": "Write spec",         "done": true,  "rank": 20}),
        json!({"id": "t3", "account_id": "acct-7", "title": "Pay bills",          "done": false, "rank": 30}),
    ]
}

fn matched_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Boolean),
                ("rank", Integer),
            ],
        )
}

fn drift_policy(cap: i64) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source_typed(
            "todos",
            &[
                ("id", Text),
                ("account_id", Text),
                ("title", Text),
                ("done", Text), // drift vs TodoRow.done : Bool
                ("rank", Integer),
            ],
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
        correlation_id: Some(format!("p18-{account}")),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

/// Extract (status, content_type, body_text) from a RenderView text/html response.
fn html_of(decision: ServerDecision) -> (u16, String, String) {
    match decision {
        ServerDecision::Respond { response } => {
            let status = response.status;
            match response.body {
                ResponseBody::Raw {
                    bytes,
                    content_type,
                } => (
                    status,
                    content_type,
                    String::from_utf8_lossy(&bytes).to_string(),
                ),
                ResponseBody::Json(v) => (status, "application/json".to_string(), v.to_string()),
            }
        }
        other => panic!("expected Respond, got {other:?}"),
    }
}

// ── 1: typed rows → escaped text/html through the normal runner contour ─────────────────────────────

#[test]
fn typed_rows_render_to_escaped_html() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter.clone(), matched_policy(100));

    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");
        // The view title is meta.source.
        assert!(
            html.contains("<h1>todos</h1>"),
            "FormView title = meta.source: {html}"
        );
        // Pending rows rendered, in order; the done row ("Write spec") is filtered out.
        let p_milk = html.find("Buy milk").expect("pending milk present");
        let p_bills = html.find("Pay bills").expect("pending bills present");
        assert!(p_milk < p_bills, "filter+map preserve order");
        assert!(!html.contains("Write spec"), "done row filtered out");
        // The malicious title is ESCAPED — no raw <script> tag survives.
        assert!(
            html.contains("Buy milk &lt;script&gt;"),
            "title escaped: {html}"
        );
        assert!(!html.contains("<script>"), "no raw script injected: {html}");
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── 2: empty rows → app-owned empty-state HTML (200), not a host error ──────────────────────────────

#[test]
fn empty_rows_render_app_owned_empty_state() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter, matched_policy(100));
    rt().block_on(async {
        // acct-none matches no rows → app empty state.
        let (status, ctype, html) =
            html_of(app.dispatch_with_read(get_req("acct-none"), &host).await);
        assert_eq!(
            status, 200,
            "empty state is app-owned 200, not a host error"
        );
        assert!(ctype.contains("text/html"));
        assert!(html.contains("No todos yet"), "empty-state label: {html}");
    });
}

// ── 3: truncated read → DatasetMeta drives a "load more" link node ──────────────────────────────────

#[test]
fn truncated_meta_renders_load_more_link() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    // cap 1 clamps the contract's limit:50 → meta.truncated = true.
    let host = make_read_host(adapter, matched_policy(1));
    rt().block_on(async {
        let (status, _ctype, html) =
            html_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        // meta.truncated → the load-more link node is appended (safe relative href).
        assert!(
            html.contains("Load more"),
            "load-more affordance present: {html}"
        );
        assert!(
            html.contains("href=\"/todos\""),
            "safe relative href: {html}"
        );
    });
}

// ── 4: projection drift fails closed BEFORE the HTML continuation (no render) ───────────────────────

#[test]
fn drift_fails_before_html_continuation() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter.clone(), drift_policy(100));
    rt().block_on(async {
        let (status, ctype, body) = html_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 500, "drift → fail closed");
        assert!(!ctype.contains("text/html"), "no HTML produced on drift");
        assert!(body.contains("projection_schema_drift"), "{body}");
        assert_eq!(
            adapter.query_count(),
            0,
            "reconcile fails before the read/continuation"
        );
    });
}

// ── P19 (LAB-TODOAPP-VIEW-TYPED-ROW-LINKS): typed rows → per-row detail links + keyset load-more ──────

fn load_app_links() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p19_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("typed_html.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fx],
        entry: "FetchTodoLinksHtml".to_string(),
    })
    .expect("load typed_html fixture (links entry)")
}

// ── 5: typed rows → per-row detail links from `row.id` (href) + `row.title` (escaped label) ──────────

#[test]
fn typed_rows_render_per_row_detail_links() {
    let app = load_app_links();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    let host = make_read_host(adapter.clone(), matched_policy(100));
    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");
        // per-row detail links: href from `row.id`, label from `row.title`, in row order.
        let d1 = html
            .find("<a class=\"ig-link\" href=\"/todos/t1\">")
            .expect("detail link for t1 (row.id → href)");
        let d3 = html
            .find("<a class=\"ig-link\" href=\"/todos/t3\">Pay bills</a>")
            .expect("detail link for t3 (row.id + row.title)");
        assert!(d1 < d3, "links follow row order");
        // the malicious title is escaped INSIDE the link text — row data, not a literal.
        assert!(
            html.contains("href=\"/todos/t1\">Buy milk &lt;script&gt;</a>"),
            "row.title escaped in link: {html}"
        );
        assert!(!html.contains("<script>"), "no raw script: {html}");
        // not truncated (cap 100 ≥ rows) → no load-more affordance.
        assert!(
            !html.contains("Load more"),
            "no load-more when not truncated: {html}"
        );
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── 6: truncated read → KEYSET load-more href built from the LAST crossed row's id ──────────────────

#[test]
fn truncated_meta_renders_keyset_load_more_from_last_row_id() {
    let app = load_app_links();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
    // cap 1 clamps the contract's limit:50 → one row (t1) crosses, meta.truncated = true.
    let host = make_read_host(adapter, matched_policy(1));
    rt().block_on(async {
        let (status, _ctype, html) =
            html_of(app.dispatch_with_read(get_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        // KEYSET cursor: the load-more href carries the last crossed row's id, not a generic "/todos".
        assert!(
            html.contains("<a class=\"ig-link\" href=\"/todos?after=t1\">Load more</a>"),
            "keyset load-more href from last row id: {html}"
        );
    });
}

// ── 7 (P20): authored Decimal[2] money cells → exact text + pad_left alignment → escaped HTML ───────

fn load_app_money() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p20_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("typed_html.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fx],
        entry: "MoneyReportHtml".to_string(),
    })
    .expect("load typed_html fixture (money report)")
}

#[test]
fn money_report_renders_exact_decimal_cells() {
    // A pure RenderView route (no host read): authored Decimal[2] amounts via decimal(cents, 2).
    let app = load_app_money();
    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch(get_req("/report")).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");

        // to_text(Decimal) is EXACT, trailing zeroes preserved.
        assert!(html.contains("12.50"), "decimal(1250,2) → 12.50: {html}");
        assert!(html.contains("123.45"), "decimal(12345,2) → 123.45: {html}");
        assert!(html.contains("5.00"), "decimal(500,2) → 5.00 (trailing zeroes): {html}");

        // pad_left(to_text(d), 8, " ") right-aligns into a fixed column — exact leading-space counts.
        assert!(html.contains("   12.50"), "12.50 padded to width 8 (3 spaces): {html}");
        assert!(html.contains("  123.45"), "123.45 padded to width 8 (2 spaces): {html}");
        assert!(html.contains("    5.00"), "5.00 padded to width 8 (4 spaces): {html}");

        // Escaping stays renderer-owned for the user-controlled label; no raw markup leaks.
        assert!(html.contains("Coffee &lt;script&gt;"), "label escaped: {html}");
        assert!(!html.contains("<script>"), "no raw script injected: {html}");
    });
}
