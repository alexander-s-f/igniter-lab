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
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy, PostgresReadValueKind,
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

// ── P10: fake adapter preserves typed JSON values through projection + receipt ─

#[test]
fn fake_typed_values_survive_projection_and_receipt() {
    use PostgresReadValueKind::*;
    rt().block_on(async {
        // one fake row with every value kind the typed policy declares.
        let rows = vec![json!({
            "id": 7,                                   // Integer  → JSON number
            "active": true,                            // Boolean  → JSON bool
            "meta": {"k": "v", "n": 3},                // Json     → JSON object
            "tags": ["a", "b"],                        // Array    → JSON array
            "created_at": "2026-06-19T00:00:00Z",      // Timestamp→ lossless string
            "amount": "1234.5678901234567890",         // Decimal  → String (never f64)
            "note": serde_json::Value::Null            // NULL     → null for any kind
        })];
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("typed_todos", rows));
        let policy = PostgresReadPolicy::new(100)
            .allow_ops(&["select"])
            .allow_source_typed(
                "typed_todos",
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
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), policy));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req(
                "typed",
                json!({
                    "source": "typed_todos", "op": "select",
                    "projection": ["id", "active", "meta", "tags", "created_at", "amount", "note"]
                }),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        let r = &out.result["rows"][0];
        // the fake passes typed values through UNCHANGED (P10: types preserved end-to-end).
        assert_eq!(r["id"], json!(7));
        assert!(r["id"].is_i64());
        assert_eq!(r["active"], json!(true));
        assert!(r["active"].is_boolean());
        assert_eq!(r["meta"], json!({"k": "v", "n": 3}));
        assert!(r["meta"].is_object());
        assert_eq!(r["tags"], json!(["a", "b"]));
        assert!(r["tags"].is_array());
        assert_eq!(r["created_at"], json!("2026-06-19T00:00:00Z"));
        assert_eq!(r["amount"], json!("1234.5678901234567890")); // decimal stays a String
        assert!(r["amount"].is_string());
        assert_eq!(r["note"], serde_json::Value::Null);

        // and the typed values are preserved in the persisted receipt fact.
        let fact = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:typed"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["result"]["rows"][0]["id"], json!(7));
        assert_eq!(fact.value["result"]["rows"][0]["active"], json!(true));
    });
}

// ── P11: typed predicates (eq/in/range) + order_by, evaluated by the fake adapter ─────────────

fn typed_todo_rows() -> Vec<serde_json::Value> {
    vec![
        json!({"id": 1, "account_id": "a-7", "title": "alpha", "done": false}),
        json!({"id": 2, "account_id": "a-7", "title": "bravo", "done": true}),
        json!({"id": 3, "account_id": "a-9", "title": "charlie", "done": false}),
        json!({"id": 4, "account_id": "a-7", "title": "delta", "done": false}),
    ]
}

fn typed_policy() -> PostgresReadPolicy {
    use PostgresReadValueKind::*;
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source_typed(
            "todos",
            &[
                ("id", Integer),
                ("account_id", Text),
                ("title", Text),
                ("done", Boolean),
            ],
        )
}

fn run_typed(plan: serde_json::Value, key: &str) -> igniter_machine::capability::EffectOutcome {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter, typed_policy()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();
        run_effect(&reg, &store, &req(key, plan), RunMode::Live)
            .await
            .unwrap()
    })
}

/// Test 1 — `eq` still works with a scalar string `value` (backward-compatible).
#[test]
fn eq_filter_backward_compatible() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "account_id", "op": "eq", "value": "a-9"}]}),
        "eq",
    );
    assert_eq!(out.kind, OutcomeKind::Succeeded);
    assert_eq!(out.result["count"], json!(1));
    assert_eq!(out.result["rows"][0]["id"], json!(3));
}

/// Test 2 — `in` filters by text and by integer.
#[test]
fn in_filter_text_and_integer() {
    let by_text = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "account_id", "op": "in", "values": ["a-9", "a-nope"]}]}),
        "in-text",
    );
    assert_eq!(by_text.result["count"], json!(1));

    let by_int = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "id", "op": "in", "values": [1, 3]}]}),
        "in-int",
    );
    assert_eq!(by_int.result["count"], json!(2));
}

/// Test 3 — range filters by integer.
#[test]
fn range_filter_integer() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "id", "op": "gte", "value": 3}]}),
        "range",
    );
    assert_eq!(out.result["count"], json!(2)); // ids 3, 4
}

/// Test 4 — `order_by` sorts deterministically before the limit.
#[test]
fn order_by_sorts_before_limit() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id"], "order_by": [{"field": "id", "dir": "desc"}], "limit": 2}),
        "order",
    );
    assert_eq!(out.result["count"], json!(2));
    assert_eq!(out.result["rows"][0]["id"], json!(4));
    assert_eq!(out.result["rows"][1]["id"], json!(3));
}

/// Test 5 — order_by on a non-allowlisted field is denied before the adapter.
#[test]
fn order_by_non_allowlisted_field_denied() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id"], "order_by": [{"field": "ssn", "dir": "asc"}]}),
        "order-bad",
    );
    assert_eq!(out.kind, OutcomeKind::Denied); // field allowlist gate
}

/// Test 6 — invalid `in` (empty / too long) is a permanent failure before the adapter.
#[test]
fn invalid_in_is_permanent() {
    let empty = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "id", "op": "in", "values": []}]}),
        "in-empty",
    );
    assert_eq!(empty.kind, OutcomeKind::PermanentFailure);

    // a tight policy bound, exceeded.
    let out = rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", typed_todo_rows()));
        let pol = typed_policy().with_predicate_limits(2, 3);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter, pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();
        run_effect(
            &reg,
            &store,
            &req("in-long", json!({"source": "todos", "projection": ["id"], "filters": [{"field": "id", "op": "in", "values": [1, 2, 3]}]})),
            RunMode::Live,
        )
        .await
        .unwrap()
    });
    assert_eq!(out.kind, OutcomeKind::PermanentFailure);
}

/// Test 7 — a range op on a kind that forbids it (Boolean) is refused before the adapter.
#[test]
fn invalid_range_kind_refused() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id"], "filters": [{"field": "done", "op": "gt", "value": true}]}),
        "range-bad",
    );
    assert_eq!(out.kind, OutcomeKind::PermanentFailure);
}

/// Test 10 — typed values survive projection + predicate/order evaluation in the receipt.
#[test]
fn typed_values_survive_predicate_and_order() {
    let out = run_typed(
        json!({"source": "todos", "projection": ["id", "done"], "filters": [{"field": "done", "op": "eq", "value": false}], "order_by": [{"field": "id", "dir": "asc"}]}),
        "typed-pred",
    );
    assert_eq!(out.kind, OutcomeKind::Succeeded);
    assert_eq!(out.result["count"], json!(3)); // ids 1,3,4 are done=false
    assert_eq!(out.result["rows"][0]["id"], json!(1));
    assert!(out.result["rows"][0]["id"].is_i64());
    assert_eq!(out.result["rows"][0]["done"], json!(false));
    assert!(out.result["rows"][0]["done"].is_boolean());
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
