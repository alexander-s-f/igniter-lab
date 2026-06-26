//! db_money_report_tests.rs — LAB-TODOAPP-VIEW-DB-DECIMAL-MONEY-REPORT-P24
//!
//! The product payoff of P23: a host `numeric` column crosses as an EXACT `.ig Decimal[2]` through the normal
//! `ReadThen` runner path and renders as a money report — exact `to_text` cells, `pad_left` alignment, and a
//! real Decimal `fold`-total — in escaped text/html.
//!
//!   FetchMoneyReport -> ReadThen{then:"MoneyReportFromRows"}
//!     -> host materializes rows : Collection[LineRow{amount:Decimal[2]}] + meta : DatasetMeta (P23)
//!     -> map(MoneyRowLine) + fold-total -> RenderView -> escaped text/html
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
use igniter_web::{build_igweb_loaded_app, IgWebBuildInput};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/db_money_report/db_money_report.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn load_app() -> Arc<igniter_web::IgWebLoadedApp> {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p24_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let fx = dir.join("db_money_report.ig");
    std::fs::write(&fx, FIXTURE).unwrap();
    build_igweb_loaded_app(IgWebBuildInput {
        sources: vec![fx],
        entry: "FetchMoneyReport".to_string(),
    })
    .expect("load db_money_report fixture")
}

/// Money rows as a Text-decoding `numeric` column yields them — `amount` is the exact decimal STRING. One
/// label carries a `<script>` to prove renderer-owned escaping.
fn money_rows() -> Vec<Value> {
    vec![
        json!({"label": "Coffee <script>", "amount": "12.50"}),
        json!({"label": "Books",           "amount": "0.05"}),
        json!({"label": "Gift",            "amount": "1200.00"}),
    ]
}

/// Host policy: `label` Text, `amount` a typed `Decimal{scale}`.
fn money_policy(scale: u32) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source_typed("lines", &[("label", Text), ("amount", Decimal { scale })])
}

fn make_read_host(adapter: Arc<FakePostgresAdapter>, policy: PostgresReadPolicy) -> StagedReadHost {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy.clone()));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    StagedReadHost::new(registry, receipts, READ_CAP).with_read_policy(policy)
}

fn get_req() -> ServerRequest {
    ServerRequest {
        protocol: PROTOCOL_VERSION.to_string(),
        method: "GET".to_string(),
        path: "/money.html".to_string(),
        body: Value::Null,
        correlation_id: Some("p24".to_string()),
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

// ── DB-shaped Decimal rows render as an exact money report in HTML, with a real fold-total ──────────

#[test]
fn db_decimal_rows_render_money_report_with_total() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("lines", money_rows()));
    let host = make_read_host(adapter.clone(), money_policy(2));

    rt().block_on(async {
        let (status, ctype, html) = html_of(app.dispatch_with_read(get_req(), &host).await);
        assert_eq!(status, 200);
        assert!(ctype.contains("text/html"), "content-type: {ctype}");
        assert!(html.contains("<h1>lines</h1>"), "report title = meta.source: {html}");

        // Exact money cells: to_text preserves trailing zeroes, pad_left right-aligns into an 8-wide column.
        assert!(html.contains("   12.50"), "12.50 padded (3 spaces): {html}"); // 5 chars → 3 pad
        assert!(html.contains("    0.05"), "0.05 padded (4 spaces): {html}"); // 4 chars → 4 pad
        assert!(html.contains(" 1200.00"), "1200.00 padded (1 space): {html}"); // 7 chars → 1 pad

        // Real Decimal fold-total: 12.50 + 0.05 + 1200.00 = 1212.55 (proves real arithmetic, not String).
        assert!(html.contains("TOTAL 1212.55"), "exact Decimal fold-total: {html}");

        // Escaping stays renderer-owned for the user-controlled label.
        assert!(html.contains("Coffee &lt;script&gt;"), "label escaped: {html}");
        assert!(!html.contains("<script>"), "no raw script: {html}");

        assert_eq!(adapter.query_count(), 1);
    });
}

// ── scale drift (host Decimal{3} vs app Decimal[2]) fails closed BEFORE any HTML rendering ──────────

#[test]
fn scale_drift_fails_before_render() {
    let app = load_app();
    let adapter = Arc::new(FakePostgresAdapter::new().with_table("lines", money_rows()));
    let host = make_read_host(adapter.clone(), money_policy(3)); // host scale 3 ≠ app Decimal[2]
    rt().block_on(async {
        let (status, ctype, body) = html_of(app.dispatch_with_read(get_req(), &host).await);
        assert_eq!(status, 500, "scale drift → fail closed");
        assert!(!ctype.contains("text/html"), "no HTML produced on drift");
        assert!(body.contains("projection_schema_drift"), "{body}");
        assert_eq!(adapter.query_count(), 0, "reconcile fails before the read");
    });
}
