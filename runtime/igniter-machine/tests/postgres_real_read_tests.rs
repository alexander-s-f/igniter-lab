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
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
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
        let Some(adapter) = connect_or_skip().await else { return };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("c1", json!({"source": "companies", "projection": ["id", "name", "status"], "limit": 5})),
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
        let f = store.read_as_of(RECEIPTS_STORE, &format!("{CAP}:c1"), f64::MAX).await.unwrap().unwrap();
        assert_eq!(f.value["outcome_kind"], json!("succeeded"));
    });
}

// ── row-limit clamp reflected against the real query ──────────────────────────

#[test]
fn real_limit_clamp() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else { return };
        let pol = PostgresReadPolicy::new(2).allow_ops(&["select"]).allow_source("companies", &["id", "name", "status"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("c-clamp", json!({"source": "companies", "projection": ["id"], "limit": 100})),
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
        let Some(adapter) = connect_or_skip().await else { return };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("c-filter", json!({
                "source": "companies",
                "projection": ["id", "status"],
                "filters": [{"field": "status", "op": "eq", "value": "active"}],
                "limit": 50,
            })),
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
        let Some(adapter) = connect_or_skip().await else { return };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        // `balance` is a real column but NOT allowlisted → gate denies before any query.
        let out = run_effect(
            &reg,
            &store,
            &req("c-forbid", json!({"source": "companies", "projection": ["id", "balance"]})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::Denied);

        // unknown source.
        let out2 = run_effect(&reg, &store, &req("c-unk", json!({"source": "admin_users"})), RunMode::Live).await.unwrap();
        assert_eq!(out2.kind, OutcomeKind::Denied);

        assert_eq!(adapter.query_count(), 0, "gate refusals never reach the real DB");
    });
}

// ── replay same idempotency key bypasses the real adapter ─────────────────────

#[test]
fn real_replay_bypasses_adapter() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else { return };
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let a = req("same", json!({"source": "companies", "projection": ["id"], "limit": 3}));
        let b = req("same", json!({"source": "companies", "projection": ["id"], "limit": 3}));
        let r1 = run_effect(&reg, &store, &a, RunMode::Live).await.unwrap();
        let r2 = run_effect(&reg, &store, &b, RunMode::Live).await.unwrap();

        assert_eq!(r1.kind, OutcomeKind::Succeeded);
        assert_eq!(r1.result, r2.result, "replay returns the receipt result");
        assert_eq!(adapter.query_count(), 1, "real DB queried exactly once per idempotency key");
    });
}

// ── DB error (undefined column) → permanent (taxonomy parity) ─────────────────

#[test]
fn real_db_error_is_permanent() {
    rt().block_on(async {
        let Some(adapter) = connect_or_skip().await else { return };
        // allowlist a column that does NOT exist → passes the gate → real SQL errors (42703).
        let pol = PostgresReadPolicy::new(100).allow_ops(&["select"]).allow_source("companies", &["nope_not_a_column"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("c-dberr", json!({"source": "companies", "projection": ["nope_not_a_column"]})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::PermanentFailure, "a SQLSTATE error is a definite query failure");
        assert_eq!(adapter.query_count(), 1);
    });
}
