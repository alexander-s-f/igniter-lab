//! decimal_crossing_tests.rs — LAB-IGNITER-DATA-PROJECTION-DECIMAL-CROSSING-P23
//!
//! A host `numeric` column (the adapter's exact decimal STRING) crosses as an EXACT `.ig Decimal[2]`: the
//! host materializer parses `"12.50"` against the declared scale into `{value:1250, scale:2}`, which the VM's
//! `from_json` lands as `Value::Decimal`. The continuation does REAL Decimal work (`to_text` exact + a
//! `fold`-sum), proving the values are real Decimals, not Strings. Scale drift fails closed; a Float/bad
//! string is refused before continuation dispatch. DB-free (fake adapter), `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityExecutorRegistry;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
};
use igniter_server::protocol::{ServerRequest, PROTOCOL_VERSION};
use igniter_web::read_continuation::app_row_shape;
use igniter_web::read_dispatch::{StagedReadHost, TypedReadResult};
use igniter_web::read_materialize::{reconcile_projection, AppFieldType, ProjectionSpec};
use serde_json::{json, Value};
use std::sync::Arc;

const FIXTURE: &str = include_str!("fixtures/decimal_crossing/decimal_crossing.ig");
const READ_CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn load_machine() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_p23_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let fx = dir.join("decimal_crossing.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    std::fs::write(&fx, FIXTURE).unwrap();
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[pl.to_string_lossy().to_string(), fx.to_string_lossy().to_string()],
        "DecimalProbe",
    )
    .expect("load decimal_crossing fixture");
    m
}

/// SELECT-only policy on `lines`: `label` as Text, `amount` as a typed `Decimal{scale}`.
fn decimal_policy(scale: u32) -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(100).allow_ops(&["select"]).allow_source_typed(
        "lines",
        &[("label", Text), ("amount", Decimal { scale })],
    )
}

fn projection() -> Vec<String> {
    vec!["label".to_string(), "amount".to_string()]
}

/// Adapter rows as a Text-decoding `numeric` column yields them — `amount` is the exact decimal STRING.
fn decimal_rows() -> Vec<Value> {
    vec![
        json!({"label": "Coffee", "amount": "12.50"}),
        json!({"label": "Books",  "amount": "0.05"}),
        json!({"label": "Gift",   "amount": "1200.00"}),
    ]
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
        path: "/lines".to_string(),
        body: Value::Null,
        correlation_id: Some("p23".to_string()),
        idempotency_key: None,
        headers: Default::default(),
        query: Default::default(),
    }
}

fn min_req() -> Value {
    json!({"method":"GET","path":"/lines","body":"","body_kind":"empty",
           "correlation_id":"","idempotency_key":"","surrogate_id":"","body_json":{},"query":{}})
}

fn plan() -> Value {
    json!({ "source": "lines", "op": "select", "projection": ["label", "amount"], "filters": [], "limit": 50 })
}

// ── the full exact crossing: numeric strings → Decimal[2], render + sum exactly ─────────────────────

#[test]
fn numeric_strings_cross_as_exact_decimal_and_sum() {
    rt().block_on(async {
        let m = load_machine();
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("lines", decimal_rows()));
        let policy = decimal_policy(2);
        let host = make_read_host(adapter.clone(), policy.clone());
        let spec = ProjectionSpec::from_policy(&policy, "lines", &projection());

        let (rows, _meta) = match host.execute_typed(&plan(), &get_req(), &spec).await {
            TypedReadResult::Rows { rows, meta } => (rows, meta),
            other => panic!("expected typed Rows, got {other:?}"),
        };
        assert_eq!(adapter.query_count(), 1);

        // The host reshaped "12.50" into the {value,scale} Decimal shape (NOT a passed-through string).
        let arr = rows.as_array().unwrap();
        assert_eq!(arr[0]["amount"], json!({"value": 1250, "scale": 2}), "12.50 → 1250@2");
        assert_eq!(arr[1]["amount"], json!({"value": 5, "scale": 2}), "0.05 → 5@2");
        assert_eq!(arr[2]["amount"], json!({"value": 120000, "scale": 2}), "1200.00 → 120000@2");

        // The continuation does REAL Decimal work over the crossed rows.
        let proof = m
            .dispatch("DecimalProbe", json!({"req": min_req(), "rows": rows, "meta": _meta}))
            .await
            .unwrap();
        assert_eq!(proof["n"], json!(3));
        // exact sum 12.50 + 0.05 + 1200.00 = 1212.55 (proves real Decimal arithmetic, not String concat).
        assert_eq!(proof["total_text"], json!("1212.55"), "fold-sum is exact Decimal");
        // per-row to_text is exact with trailing zeroes preserved.
        let joined = proof["joined"].as_str().unwrap();
        assert!(joined.contains("12.50") && joined.contains("0.05") && joined.contains("1200.00"), "{joined}");
    });
}

// ── scale-drift fails closed: host Decimal{scale:3} vs app Decimal[2] ────────────────────────────────

#[test]
fn scale_drift_is_rejected_by_reconciler() {
    let m = load_machine();
    let approw = app_row_shape(&m, "LineRow").expect("recover LineRow shape");
    // The app declares amount : Decimal[2].
    assert!(
        approw.iter().any(|(f, t)| f == "amount" && *t == AppFieldType::Decimal(2)),
        "LineRow.amount recovered as Decimal(2): {approw:?}"
    );

    // Matched scale reconciles clean.
    let ok_spec = ProjectionSpec::from_policy(&decimal_policy(2), "lines", &projection());
    assert!(reconcile_projection(&ok_spec, &approw).is_ok());

    // Host Decimal{scale:3} ≠ app Decimal[2] → ProjectionSchemaDrift.
    let drift_spec = ProjectionSpec::from_policy(&decimal_policy(3), "lines", &projection());
    let err = reconcile_projection(&drift_spec, &approw).unwrap_err();
    assert!(err.starts_with("ProjectionSchemaDrift"), "{err}");
    assert!(err.contains("amount"), "{err}");
}

// ── no Float path: a numeric (Float) value for the Decimal field is refused ──────────────────────────

#[test]
fn float_value_for_decimal_field_is_refused() {
    rt().block_on(async {
        let m = load_machine();
        let _ = &m;
        // amount as a JSON NUMBER (Float) instead of the exact decimal string → wrong kind.
        let bad = vec![json!({"label": "Coffee", "amount": 12.5})];
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("lines", bad));
        let policy = decimal_policy(2);
        let host = make_read_host(adapter, policy.clone());
        let spec = ProjectionSpec::from_policy(&policy, "lines", &projection());
        match host.execute_typed(&plan(), &get_req(), &spec).await {
            TypedReadResult::SchemaMismatch(e) => assert!(e.contains("`amount` wrong kind"), "{e}"),
            other => panic!("expected SchemaMismatch (no Float path), got {other:?}"),
        }
    });
}

// ── bad decimal strings fail closed before continuation ─────────────────────────────────────────────

#[test]
fn bad_decimal_strings_fail_closed() {
    rt().block_on(async {
        let policy = decimal_policy(2);
        let spec = ProjectionSpec::from_policy(&policy, "lines", &projection());
        // over-scale: 3 fractional digits for a scale-2 field.
        for (amount, why) in [
            ("12.500", "more fractional digits than scale"),
            ("1e2", "exponent"),
            ("abc", "non-numeric"),
            ("12.", "trailing dot ok? frac empty — actually valid"), // sanity below
        ] {
            let _ = why;
            let bad = vec![json!({"label": "X", "amount": amount})];
            let adapter = Arc::new(FakePostgresAdapter::new().with_table("lines", bad));
            let host = make_read_host(adapter, policy.clone());
            let r = host.execute_typed(&plan(), &get_req(), &spec).await;
            if amount == "12." {
                // "12." → int "12", frac "" → 1200@2 — a valid canonical form (no fractional digits).
                assert!(matches!(r, TypedReadResult::Rows { .. }), "`12.` is valid: {r:?}");
            } else {
                assert!(matches!(r, TypedReadResult::SchemaMismatch(_)), "`{amount}` must fail: {r:?}");
            }
        }
    });
}
