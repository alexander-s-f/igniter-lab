//! LAB-MACHINE-POSTGRES-LOCAL-READ-P6 — real local Postgres read adapter (opt-in integration).
//!
//! Compiled ONLY under `--features postgres`, and each test SKIPS cleanly when no `IGNITER_PG_DSN`
//! is set (the `tls` offline-precheck pattern). Proves the P2 read boundary against a REAL local
//! Postgres — read-only SELECT — with the SAME observable contract as the fake adapter.
//!
//! Run (developer machine, local Postgres):
//!   IGNITER_PG_DSN="host=localhost user=alex dbname=spark_dev_db_15_05_2026_v2" \
//!     cargo test --no-default-features --features postgres --test postgres_real_read_tests
//!
//! Target: the dev SparkCRM `companies` table (id bigint, name varchar, status varchar). Assertions
//! are STRUCTURAL (shape / subset / counts-bounded), never exact values — dev data evolves.

#![cfg(feature = "postgres")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::postgres_read::{PostgresReadExecutor, PostgresReadPolicy};
use igniter_machine::postgres_real::TokioPostgresReadAdapter;
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.PostgresRead";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

/// `companies(id,name,status)` selects, capped at 100 rows.
fn policy() -> PostgresReadPolicy {
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("companies", &["id", "name", "status"])
}

fn req(key: &str, args: serde_json::Value) -> EffectRequest {
    EffectRequest {
        capability_id: CAP.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

/// Connect using `IGNITER_PG_DSN`, or `None` to signal "skip this test".
async fn connect_or_skip() -> Option<Arc<TokioPostgresReadAdapter>> {
    let dsn = match std::env::var("IGNITER_PG_DSN") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            eprintln!("SKIP: IGNITER_PG_DSN not set — real Postgres test skipped");
            return None;
        }
    };
    match TokioPostgresReadAdapter::connect(&dsn).await {
        Ok(a) => Some(Arc::new(a)),
        Err(e) => panic!("IGNITER_PG_DSN set but connection failed: {e}"),
    }
}

// ── allowlisted SELECT returns rows through the real DB + receipt ─────────────

#[test]
fn real_companies_select_returns_rows() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "c1",
                json!({"source": "companies", "projection": ["id", "name", "status"], "limit": 5}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["kind"], json!("rows"));
        let rows = out.result["rows"].as_array().unwrap();
        assert!(!rows.is_empty(), "companies has data");
        assert!(rows.len() <= 5);
        // projection shape: each row has exactly id/name/status (TEXT-rendered).
        for r in rows {
            assert!(r.get("id").is_some() && r.get("name").is_some() && r.get("status").is_some());
        }
        assert_eq!(adapter.query_count(), 1);

        // receipt persisted through the unchanged capability machinery.
        let f = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:c1"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(f.value["outcome_kind"], json!("succeeded"));
    });
}

// ── row-limit clamp reflected against the real query ──────────────────────────

#[test]
fn real_limit_clamp() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let pol = PostgresReadPolicy::new(2)
            .allow_ops(&["select"])
            .allow_source("companies", &["id", "name", "status"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "c-clamp",
                json!({"source": "companies", "projection": ["id"], "limit": 100}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["effective_limit"], json!(2));
        assert_eq!(out.result["row_limit_clamped"], json!(true));
        assert!(out.result["rows"].as_array().unwrap().len() <= 2);
    });
}

// ── eq filter returns a correct (parameter-bound) subset ──────────────────────

#[test]
fn real_eq_filter_subset() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "c-filter",
                json!({
                    "source": "companies",
                    "projection": ["id", "status"],
                    "filters": [{"field": "status", "op": "eq", "value": "active"}],
                    "limit": 50,
                }),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        // every returned row must match the bound parameter (no SQL injection, correct WHERE).
        for r in out.result["rows"].as_array().unwrap() {
            assert_eq!(r["status"], json!("active"));
        }
    });
}

// ── gate parity: forbidden field / unknown source refused before the adapter ──

#[test]
fn real_gate_parity_refuses_before_adapter() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        // `balance` is a real column but NOT allowlisted → gate denies before any query.
        let out = run_effect(
            &reg,
            &store,
            &req(
                "c-forbid",
                json!({"source": "companies", "projection": ["id", "balance"]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);

        // unknown source.
        let out2 = run_effect(
            &reg,
            &store,
            &req("c-unk", json!({"source": "admin_users"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out2.kind, OutcomeKind::Denied);

        assert_eq!(
            adapter.query_count(),
            0,
            "gate refusals never reach the real DB"
        );
    });
}

// ── replay same idempotency key bypasses the real adapter ─────────────────────

#[test]
fn real_replay_bypasses_adapter() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let a = req(
            "same",
            json!({"source": "companies", "projection": ["id"], "limit": 3}),
        );
        let b = req(
            "same",
            json!({"source": "companies", "projection": ["id"], "limit": 3}),
        );
        let r1 = run_effect(&reg, &store, &a, RunMode::Live).await.unwrap();
        let r2 = run_effect(&reg, &store, &b, RunMode::Live).await.unwrap();

        assert_eq!(r1.kind, OutcomeKind::Succeeded);
        assert_eq!(r1.result, r2.result, "replay returns the receipt result");
        assert_eq!(
            adapter.query_count(),
            1,
            "real DB queried exactly once per idempotency key"
        );
    });
}

// ── DB error (undefined column) → permanent (taxonomy parity) ─────────────────

#[test]
fn real_db_error_is_permanent() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        // allowlist a column that does NOT exist → passes the gate → real SQL errors (42703).
        let pol = PostgresReadPolicy::new(100)
            .allow_ops(&["select"])
            .allow_source("companies", &["nope_not_a_column"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "c-dberr",
                json!({"source": "companies", "projection": ["nope_not_a_column"]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(
            out.kind,
            OutcomeKind::PermanentFailure,
            "a SQLSTATE error is a definite query failure"
        );
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── P10: typed reads — projection decodes per host-declared field kind (gated, local-only) ───
//
// Requires a dedicated local test DB in `IGNITER_PG_DSN` containing a pre-seeded fixture table.
// One-time developer setup (NOT run by this test; never against SparkCRM/dev business tables):
//
//   CREATE TABLE igniter_typed_read (
//     id         bigint  PRIMARY KEY,
//     active     boolean,
//     meta       jsonb,
//     tags       jsonb,
//     created_at timestamptz,
//     amount     numeric,
//     note       text
//   );
//   INSERT INTO igniter_typed_read VALUES
//     (7, true, '{"k":"v"}'::jsonb, '["a","b"]'::jsonb, '2026-06-19T00:00:00Z', 1234.56, NULL);
//
// Skips cleanly when IGNITER_PG_DSN is unset (the same pattern as the other real tests).
#[test]
fn real_typed_read_decodes_by_kind() {
    use igniter_machine::postgres_read::PostgresReadValueKind::*;
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let pol = PostgresReadPolicy::new(100).allow_ops(&["select"]).allow_source_typed(
            "igniter_typed_read",
            &[
                ("id", Integer),
                ("active", Boolean),
                ("meta", Json),
                ("tags", Array),
                ("created_at", Timestamp),
                ("amount", DecimalString),
                ("note", Text),
            ],
        );
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "typed-real",
                json!({
                    "source": "igniter_typed_read", "op": "select",
                    "projection": ["id", "active", "meta", "tags", "created_at", "amount", "note"],
                    "limit": 1
                }),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        // If the fixture table is absent the SELECT errors (42P01) — surface that as a setup hint.
        assert_eq!(
            out.kind,
            OutcomeKind::Succeeded,
            "expected the `igniter_typed_read` fixture table to exist (see the test header SQL)"
        );
        let rows = out.result["rows"].as_array().expect("rows array");
        if rows.is_empty() {
            eprintln!("SKIP-ASSERT: igniter_typed_read present but empty — seed one row to assert types");
            return;
        }
        // STRUCTURAL type assertions (P10): each field decodes to its declared JSON kind.
        let r = &rows[0];
        assert!(r["id"].is_i64(), "Integer → JSON number, got {:?}", r["id"]);
        assert!(r["active"].is_boolean(), "Boolean → JSON bool, got {:?}", r["active"]);
        assert!(
            r["meta"].is_object() || r["meta"].is_array() || r["meta"].is_null(),
            "Json → decoded value, got {:?}",
            r["meta"]
        );
        assert!(
            r["tags"].is_array() || r["tags"].is_null(),
            "Array (json) → JSON array, got {:?}",
            r["tags"]
        );
        assert!(
            r["created_at"].is_string() || r["created_at"].is_null(),
            "Timestamp → lossless string, got {:?}",
            r["created_at"]
        );
        assert!(
            r["amount"].is_string() || r["amount"].is_null(),
            "Decimal → String, never f64, got {:?}",
            r["amount"]
        );
        assert!(
            r["note"].is_string() || r["note"].is_null(),
            "Text/NULL → string or null, got {:?}",
            r["note"]
        );
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── P11: typed in/range/order_by against a real DB (gated, local-only; skips without DSN) ────
//
// Reuses the `igniter_typed_read` fixture from the P10 test header. Proves the real adapter renders
// `= ANY($n)`, `<cast> <op> $n`, and `ORDER BY <cast> DIR` as parameterized SQL. Skips cleanly when
// IGNITER_PG_DSN is unset.
#[test]
fn real_typed_predicates_and_order() {
    use igniter_machine::postgres_read::PostgresReadValueKind::*;
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else {
            return;
        };
        let pol = PostgresReadPolicy::new(100).allow_ops(&["select"]).allow_source_typed(
            "igniter_typed_read",
            &[("id", Integer), ("active", Boolean), ("note", Text)],
        );
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        // in(id) + range(id) + order_by(id desc) — all parameterized, allowlisted.
        let out = run_effect(
            &reg,
            &store,
            &req(
                "typed-pred",
                json!({
                    "source": "igniter_typed_read",
                    "projection": ["id", "active"],
                    "filters": [
                        {"field": "id", "op": "in", "values": [1, 2, 7]},
                        {"field": "id", "op": "gte", "value": 1}
                    ],
                    "order_by": [{"field": "id", "dir": "desc"}],
                    "limit": 10
                }),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(
            out.kind,
            OutcomeKind::Succeeded,
            "expected `igniter_typed_read` fixture (see P10 test header SQL)"
        );
        let rows = out.result["rows"].as_array().expect("rows array");
        // structural: ids are integers and (if ≥2 rows) descending.
        for r in rows {
            assert!(r["id"].is_i64(), "Integer projection stays a number");
        }
        if rows.len() >= 2 {
            let a = rows[0]["id"].as_i64().unwrap();
            let b = rows[1]["id"].as_i64().unwrap();
            assert!(a >= b, "order_by id desc must be non-increasing");
        }
        assert_eq!(adapter.query_count(), 1);
    });
}
