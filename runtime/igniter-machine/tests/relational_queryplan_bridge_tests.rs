//! LAB-IGNITER-RELATIONAL-QUERYPLAN-BRIDGE-P3 — `.ig` relational QueryPlan → fake Postgres read executor.
//!
//! Bridges the P2 language shape (`lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig`,
//! a pure `.ig` `QueryPlan` mirror type) to the EXISTING fake `PostgresReadExecutor`, with NO live DB, NO
//! `postgres` feature, NO SQL. Proof shape **B (host-side mirror)**: executing compiled `.ig` from a
//! machine test would need the compiler crate + `.igapp` load + VM dispatch + value extraction — not a
//! small existing path — so we do NOT invent a runtime bridge. Instead we feed the executor a `QueryPlan`
//! JSON that is shape-aligned to the P2 fixture, and TIE the two by `include_str!`-ing the fixture and
//! asserting its type declares exactly the fields the executor's `QueryPlan::from_args` reads. Actual
//! VM-result extraction is deferred to `LAB-IGNITER-RELATIONAL-VM-EXECUTION-BRIDGE-P4`.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode, RECEIPTS_STORE,
};
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use serde_json::{json, Value};
use std::sync::Arc;

const CAP: &str = "IO.PostgresRead";

/// The P2 relational fixture — the source of truth for the `.ig` `QueryPlan` shape this card bridges.
const P2_FIXTURE: &str = include_str!(
    "../../../lang/igniter-compiler/tests/fixtures/relational_todo/relational_todo.ig"
);

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

/// Policy mirroring what a host would publish for the P2 `todos` relation: select-only, the four allowed
/// columns, capped at 100 rows (so the fixture's `limit: 50` is NOT clamped).
fn todos_policy() -> PostgresReadPolicy {
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}

fn req(key: &str, args: Value) -> EffectRequest {
    EffectRequest {
        capability_id: CAP.to_string(),
        idempotency_key: key.to_string(),
        authority_ref: Some("passport:test".to_string()),
        args,
    }
}

fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": "acct-7", "title": "ship P3", "done": "false"}),
        json!({"id": "t2", "account_id": "acct-7", "title": "write proof", "done": "true"}),
    ]
}

/// The `QueryPlan` JSON the P2 `TodosByAccount("acct-7")` contract produces — field-for-field aligned to
/// `RelationalTodo.QueryPlan` (`source`, `op`, `projection`, `filters: [{field, op, value}]`, `limit`).
fn todos_by_account_plan(account_id: &str) -> Value {
    json!({
        "source": "todos",
        "op": "select",
        "projection": ["id", "account_id", "title", "done"],
        "filters": [{"field": "account_id", "op": "eq", "value": account_id}],
        "limit": 50
    })
}

// ── Shape tie: the machine input keys are exactly the P2 `.ig` QueryPlan/QueryFilter fields ────────────

#[test]
fn p2_fixture_declares_the_queryplan_shape_the_executor_reads() {
    // The executor's `QueryPlan::from_args` reads: source / op / projection / filters / field / value /
    // limit. The P2 fixture must declare those as the `QueryPlan` + `QueryFilter` type fields, and its
    // `TodosByAccount` must use source "todos", an eq filter on account_id, and the four columns.
    for token in [
        "type QueryPlan {",
        "type QueryFilter {",
        "source     : String",
        "op         : String",
        "projection : Collection[String]",
        "filters    : Collection[QueryFilter]",
        "limit      : Integer",
        "field : String",
        "value : String",
        "pure contract TodosByAccount",
        "\"todos\"",
        "\"account_id\", \"eq\"",
        "\"id\", \"account_id\", \"title\", \"done\"",
    ] {
        assert!(
            P2_FIXTURE.contains(token),
            "P2 fixture must declare `{token}` (the shape this bridge feeds the executor)"
        );
    }
}

// ── 1 + 3: a P2-shaped plan reaches the executor and returns rows through the receipt machinery ────────

#[test]
fn p2_queryplan_reaches_executor_and_returns_rows() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(
            CAP,
            adapter.clone(),
            todos_policy(),
        ));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-todos", todos_by_account_plan("acct-7")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["kind"], json!("rows"));
        assert_eq!(out.result["count"], json!(2));
        // projection-shaped rows (all four allowed columns present).
        assert_eq!(
            out.result["rows"][0],
            json!({"id": "t1", "account_id": "acct-7", "title": "ship P3", "done": "false"})
        );
        assert_eq!(adapter.query_count(), 1);

        // receipt persisted as a fact through the existing capability machinery.
        let fact = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:q-todos"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(fact.value["outcome_kind"], json!("succeeded"));
    });
}

// ── 2: allowlist gates — bad source / projection field / filter field / mutating op, all before adapter ─

#[test]
fn allowlist_source_field_and_op_gates() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(
            CAP,
            adapter.clone(),
            todos_policy(),
        ));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        // unknown source → denied before the adapter.
        let bad_src = run_effect(
            &reg,
            &store,
            &req("g-src", json!({"source": "secrets"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(bad_src.kind, OutcomeKind::Denied);

        // projection field not in the allowlist → denied.
        let bad_proj = run_effect(
            &reg,
            &store,
            &req(
                "g-proj",
                json!({"source": "todos", "projection": ["id", "secret_col"]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(bad_proj.kind, OutcomeKind::Denied);

        // filter field not in the allowlist → denied.
        let bad_filt = run_effect(
            &reg,
            &store,
            &req(
                "g-filt",
                json!({"source": "todos", "filters": [{"field": "ssn", "op": "eq", "value": "x"}]}),
            ),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(bad_filt.kind, OutcomeKind::Denied);

        // mutating op → denied (read-only).
        let bad_op = run_effect(
            &reg,
            &store,
            &req("g-op", json!({"source": "todos", "op": "update"})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(bad_op.kind, OutcomeKind::Denied);

        // none of the refusals ever reached the adapter.
        assert_eq!(adapter.query_count(), 0);
    });
}

// ── 4: limit clamp — the fixture's limit:50 is clamped to a tight policy cap ───────────────────────────

#[test]
fn limit_clamped_to_policy() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let pol = PostgresReadPolicy::new(1)
            .allow_ops(&["select"])
            .allow_source("todos", &["id", "account_id", "title", "done"]);
        let exec = Arc::new(PostgresReadExecutor::new(CAP, adapter.clone(), pol));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let out = run_effect(
            &reg,
            &store,
            &req("q-clamp", todos_by_account_plan("acct-7")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["effective_limit"], json!(1));
        assert_eq!(out.result["row_limit_clamped"], json!(true));
        assert_eq!(out.result["count"], json!(1));
    });
}

// ── 5: replay with same idempotency key + payload bypasses the adapter (count stays 1) ────────────────

#[test]
fn replay_same_key_bypasses_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(
            CAP,
            adapter.clone(),
            todos_policy(),
        ));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        let first = run_effect(
            &reg,
            &store,
            &req("same", todos_by_account_plan("acct-7")),
            RunMode::Live,
        )
        .await
        .unwrap();
        let second = run_effect(
            &reg,
            &store,
            &req("same", todos_by_account_plan("acct-7")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(first.kind, OutcomeKind::Succeeded);
        assert_eq!(second.kind, OutcomeKind::Succeeded);
        assert_eq!(
            first.result, second.result,
            "replay returns the receipt result"
        );
        assert_eq!(
            adapter.query_count(),
            1,
            "adapter runs once per idempotency key"
        );
    });
}

// ── 6: raw SQL refused structurally for every smuggling key, adapter untouched ────────────────────────

#[test]
fn raw_sql_refused_structurally() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let exec = Arc::new(PostgresReadExecutor::new(
            CAP,
            adapter.clone(),
            todos_policy(),
        ));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let store = receipts();

        for (i, key) in ["sql", "raw_sql", "query"].iter().enumerate() {
            let mut m = serde_json::Map::new();
            m.insert(
                (*key).to_string(),
                json!("SELECT * FROM todos; DROP TABLE todos;"),
            );
            let out = run_effect(
                &reg,
                &store,
                &req(&format!("q-sql-{i}"), Value::Object(m)),
                RunMode::Live,
            )
            .await
            .unwrap();
            assert_eq!(
                out.kind,
                OutcomeKind::PermanentFailure,
                "`{key}` must be refused"
            );
            assert!(out.failure_kind.unwrap().contains("raw SQL refused"));
        }
        assert_eq!(
            adapter.query_count(),
            0,
            "adapter never sees a raw-SQL request"
        );
    });
}
