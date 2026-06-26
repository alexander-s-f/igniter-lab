//! todo_postgres_money_report_tests.rs — LAB-TODOAPP-VIEW-DB-MONEY-REPORT-ROUTE-P25
//!
//! The P24 DB-backed Decimal money report promoted into the REAL `examples/todo_postgres_app` as an additive
//! route: `GET /accounts/:account_id/report/money` reads typed `Decimal[2]` money lines through the SAME host
//! `ReadThen` path and renders exact-money HTML (to_text cells + pad_left alignment + a real Decimal fold-TOTAL)
//! via `RenderView`. DB-free (fake adapter), `--features machine`.
//!
//! VERIFY-FIRST: `host.toml` cannot express a typed `Decimal{scale}` field kind today (`[postgres.read]
//! fields` is a flat Text allowlist), so the `Decimal` policy is supplied via `allow_source_typed` in this
//! harness; the route is proven DB-free here, and a production deploy awaits the host-config typed-kind
//! follow-on (named in the card). `host.example.toml` is NOT modified.
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

fn load_product_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let (app, _manifest) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    app
}

/// Money rows as a `numeric` column yields them under a `Decimal`-kind decode: `amount` is the EXACT decimal
/// STRING (the materializer reshapes it to a real `Value::Decimal`). One label carries a `<script>`.
fn money_rows(account: &str) -> Vec<Value> {
    vec![
        json!({"account_id": account, "label": "Coffee <script>", "amount": "12.50"}),
        json!({"account_id": account, "label": "Books",           "amount": "0.05"}),
        json!({"account_id": account, "label": "Gift",            "amount": "1200.00"}),
    ]
}

/// Host policy: `account_id`/`label` Text, `amount` a typed `Decimal{scale}` — expressible ONLY via
/// `allow_source_typed` (Rust), not `host.toml`.
fn money_policy(scale: u32) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(100).allow_ops(&["select"]).allow_source_typed(
        "money_lines",
        &[("account_id", Text), ("label", Text), ("amount", Decimal { scale })],
    )
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy.clone()));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP).with_read_policy(policy)
}

fn report_req(account: &str) -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: format!("/accounts/{account}/report/money"),
        body: Value::Null,
        correlation_id: Some(format!("p25-{account}")),
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

// ── the product route renders exact Decimal cells + a real fold-total, through the same ReadThen seam ──

#[test]
fn money_report_route_renders_exact_cells_and_total() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("money_lines", money_rows("acct-7")));
    let host = make_read_host(adapter.clone(), money_policy(2));

    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(report_req("acct-7"), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");
        assert!(html.contains("<h1>Money</h1>"), "report title: {html}");
        // Exact money cells: to_text preserves trailing zeroes; pad_left right-aligns into an 8-wide column.
        assert!(html.contains("   12.50"), "12.50 padded (3 spaces): {html}");
        assert!(html.contains("    0.05"), "0.05 padded (4 spaces): {html}");
        assert!(html.contains(" 1200.00"), "1200.00 padded (1 space): {html}");
        // Real Decimal fold-total: 12.50 + 0.05 + 1200.00 = 1212.55 (exact arithmetic, not String).
        assert!(html.contains("TOTAL 1212.55"), "exact Decimal fold-total: {html}");
        // Escaping stays renderer-owned for the user-controlled label.
        assert!(html.contains("Coffee &lt;script&gt;"), "label escaped: {html}");
        assert!(!html.contains("<script>"), "no raw script: {html}");
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── scale drift (host Decimal{3} vs app Decimal[2]) fails closed BEFORE any HTML render ─────────────

#[test]
fn money_report_scale_drift_fails_before_render() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("money_lines", money_rows("acct-7")));
    let host = make_read_host(adapter.clone(), money_policy(3)); // host scale 3 ≠ app Decimal[2]
    rt().block_on(async {
        let (status, ctype, body) = html_of(app.dispatch_with_read(report_req("acct-7"), &host).await);
        assert_eq!(status, 500, "scale drift → fail closed");
        assert!(!ctype.contains("text/html"), "no HTML on drift");
        assert!(body.contains("projection_schema_drift"), "{body}");
        assert_eq!(adapter.query_count(), 0, "reconcile fails before the read");
    });
}

// ── route order: /accounts/:id/report/money reaches the report (distinct 3rd segment, not the todos show) ──

#[test]
fn report_route_is_reached_not_shadowed() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("money_lines", money_rows("acct-9")));
    let host = make_read_host(adapter, money_policy(2));
    rt().block_on(async {
        // The path's 3rd segment is `report` (≠ `todos`), so the `/todos/:todo_id` show pattern never matches
        // it. Reaching the money report (200 with TOTAL) proves the additive route is not shadowed.
        let (status, ctype, html) = html_of(app.dispatch_with_read(report_req("acct-9"), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"));
        assert!(html.contains("TOTAL"), "report route reached (not the todo show): {html}");
    });
}

// ── empty account → app-owned empty report (200), not a host error ──────────────────────────────────

#[test]
fn empty_money_report_is_app_owned_200() {
    let app = load_product_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("money_lines", vec![]));
    let host = make_read_host(adapter, money_policy(2));
    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(report_req("acct-none"), &host).await);
        assert_eq!(status, 200, "empty report is app-owned 200");
        assert!(ctype.contains("text/html"));
        // No line rows; the fold-total over an empty collection is the seed 0.00.
        assert!(html.contains("TOTAL    0.00"), "empty report total = 0.00: {html}");
    });
}
