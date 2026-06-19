//! LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2 — fake-adapter Postgres read executor.
//!
//! Proves the connector boundary + safety gates WITHOUT a real database: a `PostgresReadExecutor`
//! is a `CapabilityExecutor`, so it rides the existing `run_effect` machinery (authority,
//! idempotency, receipt-as-fact, replay). No `tokio-postgres`/`sqlx`/`diesel`, no SQL, no network.
//!
//! Verify-first (this card): before P2 there was NO Postgres connector in the crate — a whole-crate
//! search for `postgres`/`sql`/`sqlx`/`tokio-postgres`/`diesel` returned zero hits (recorded in the
//! P1 readiness packet). This file adds the first one, fake-only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
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

/// A policy allowing `leads(id,name,status)` selects, capped at 100 rows.
fn policy() -> PostgresReadPolicy {
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("leads", &["id", "name", "status"])
}

fn req(key: &str, args: serde_json::Value) -> EffectRequest {
    EffectRequest {
        capability_id: CAP.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

fn lead_rows() -> Vec<serde_json::Value> {
    vec![
        json!({"id": 1, "name": "Ada", "status": "new"}),
        json!({"id": 2, "name": "Grace", "status": "won"}),
        json!({"id": 3, "name": "Lin", "status": "new"}),
    ]
}

// ── #2 (impl) + #4: executor IS a CapabilityExecutor; allowlisted source returns rows ──

#[test]
fn allowlisted_source_succeeds_and_returns_rows() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        // It is genuinely a CapabilityExecutor (acceptance #2).
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "q1",
                json!({"source": "leads", "op": "select", "projection": ["id", "name"]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["kind"], json!("rows"));
        assert_eq!(out.result["count"], json!(3));
        // projection-shaped: only id+name present, status dropped.
        assert_eq!(out.result["rows"][0], json!({"id": 1, "name": "Ada"}));
        assert_eq!(adapter.query_count(), 1);

        // receipt persisted as a fact through the existing machinery.
        let fact = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:q1"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["outcome_kind"], json!("succeeded"));
    });
}

// ── #6: empty result maps to success/empty, not failure ───────────────────────

#[test]
fn empty_result_is_success_empty() {
    rt().block_on(async {
        // allowlisted source, but the fake has no data for it → definite empty.
        let adapter = Arc::new(FakePostgresAdapter::new());
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-empty", json!({"source": "leads"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(
            out.kind,
            OutcomeKind::Succeeded,
            "empty is success, not failure"
        );
        assert_eq!(out.result["kind"], json!("empty"));
        assert_eq!(out.result["count"], json!(0));
        assert_eq!(adapter.query_count(), 1);
    });
}

// ── #5 (raw SQL): raw SQL input refused structurally, adapter untouched ────────

#[test]
fn raw_sql_input_refused_structurally() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "q-sql",
                json!({"sql": "SELECT * FROM leads; DROP TABLE leads;"}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::PermanentFailure);
        assert!(out.failure_kind.unwrap().contains("raw SQL refused"));
        assert_eq!(
            adapter.query_count(),
            0,
            "adapter must never see a raw-SQL request"
        );
    });
}

// ── #7: unknown source refused before the adapter ─────────────────────────────

#[test]
fn unknown_source_refused_before_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-bad-src", json!({"source": "secrets"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Denied);
        assert!(out.failure_kind.unwrap().contains("source not allowed"));
        assert_eq!(adapter.query_count(), 0);
    });
}

// ── #7: forbidden field refused before the adapter ────────────────────────────

#[test]
fn forbidden_field_refused_before_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        // `ssn` is not in the leads field allowlist.
        let out = run_effect(
            &reg,
            &store,
            &req(
                "q-bad-field",
                json!({"source": "leads", "projection": ["id", "ssn"]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Denied);
        assert!(out.failure_kind.unwrap().contains("forbidden field: ssn"));
        assert_eq!(adapter.query_count(), 0);

        // a forbidden FILTER field is likewise refused before the adapter.
        let out2 = run_effect(
            &reg,
            &store,
            &req(
                "q-bad-filter",
                json!({"source": "leads", "filters": [{"field": "ssn", "op": "eq", "value": "x"}]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out2.kind, OutcomeKind::Denied);
        assert_eq!(adapter.query_count(), 0);
    });
}

// ── #7: mutation attempt refused before the adapter (read-only) ───────────────

#[test]
fn mutation_attempt_refused_before_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-write", json!({"source": "leads", "op": "update"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Denied);
        assert!(out
            .failure_kind
            .unwrap()
            .contains("read-only: mutation refused"));
        assert_eq!(adapter.query_count(), 0);
    });
}

// ── #8: row limit clamped by policy, reflected in result AND receipt ──────────

#[test]
fn row_limit_clamped_and_reflected() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        // tight cap of 2 so the 3-row table is clamped.
        let pol = PostgresReadPolicy::new(2)
            .allow_ops(&["select"])
            .allow_source("leads", &["id", "name", "status"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-clamp", json!({"source": "leads", "limit": 100})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["effective_limit"], json!(2));
        assert_eq!(out.result["row_limit_clamped"], json!(true));
        assert_eq!(
            out.result["count"],
            json!(2),
            "only the clamped number of rows returned"
        );

        // the clamp is also visible in the persisted receipt.
        let fact = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:q-clamp"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["result"]["row_limit_clamped"], json!(true));
        assert_eq!(fact.value["result"]["effective_limit"], json!(2));
    });
}

// ── #9: adapter unavailable → unknown; transient → retryable ──────────────────

#[test]
fn adapter_unavailable_maps_to_unknown_and_transient_to_retryable() {
    rt().block_on(async {
        let store = receipts();

        let down = Arc::new(FakePostgresAdapter::new().unavailable("leads", "connection refused"));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(PostgresReadExecutor::new(CAP, down, policy())));
        let out = run_effect(
            &reg,
            &store,
            &req("q-down", json!({"source": "leads"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.kind, OutcomeKind::UnknownExternalState);

        let flaky = Arc::new(FakePostgresAdapter::new().transient("leads", "pool exhausted"));
        let mut reg2 = CapabilityExecutorRegistry::new();
        reg2.register(Arc::new(PostgresReadExecutor::new(CAP, flaky, policy())));
        let out2 = run_effect(
            &reg2,
            &store,
            &req("q-flaky", json!({"source": "leads"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out2.kind, OutcomeKind::Retryable);
    });
}

// ── #10: replay with same idempotency key bypasses the adapter (count stays 1) ─

#[test]
fn replay_same_key_bypasses_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("leads", lead_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let a = req("same", json!({"source": "leads", "projection": ["id"]}));
        let b = req("same", json!({"source": "leads", "projection": ["id"]}));

        let first = run_effect(&reg, &store, &a, RunMode::Live).await.unwrap();
        let second = run_effect(&reg, &store, &b, RunMode::Live).await.unwrap();

        assert_eq!(first.kind, OutcomeKind::Succeeded);
        assert_eq!(second.kind, OutcomeKind::Succeeded);
        assert_eq!(
            first.result, second.result,
            "replay returns the receipt result"
        );
        assert_eq!(
            adapter.query_count(),
            1,
            "adapter must run exactly once for one idempotency key"
        );
    });
}
