//! igniter-web/tests/todo_postgres_local_e2e_tests.rs — LAB-TODOAPP-API-LOCAL-POSTGRES-P8
//!
//! The product Todo API over a REAL local Postgres, end-to-end, with ZERO app Rust and the SAME
//! authority model proven on fakes (P3 read / P4 write / P5 e2e / P7 structured input):
//!
//!   READ  : app `ListTodosByAccount` -> QueryPlan -> host `PostgresReadExecutor` + real
//!           `TokioPostgresReadAdapter` -> rows -> app `AccountTodoIndexFromRows` -> 200 / 404
//!   WRITE : app `BuildCreateTodoIntent` -> structured `WriteIntent` (P7) -> host
//!           `PostgresWriteExecutor` + real `TokioPostgresWriteAdapter` -> business `todos` row +
//!           PG `effect_receipts` row + machine receipt; replay same key -> NO 2nd business mutation
//!
//! Authority split: the `.ig` app owns the QueryPlan / WriteIntent / domain 200/404; the HOST owns the
//! DSN, schema, allowlists, adapter, receipts, idempotency. The app names NO DSN/SQL/capability id.
//!
//! Compiled ONLY under `--features "machine postgres"`; every test SKIPS cleanly when `IGNITER_TODO_PG_DSN`
//! is unset (operator-gated — a dedicated test DB, never a shared/business DB). Test-owned DDL only; cleans
//! ONLY the keys/ids it owns. NO migration framework, NO raw SQL from `.ig`, NO canon claim.
//!
//! Run (operator, local Postgres):
//!   IGNITER_TODO_PG_DSN="host=localhost user=alex dbname=igniter_todo_test" \
//!     cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests
#![cfg(all(feature = "machine", feature = "postgres"))]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, CapabilityPassport, EffectRequest, OutcomeKind,
    RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{PostgresReadExecutor, PostgresReadPolicy};
use igniter_machine::postgres_real::{TokioPostgresReadAdapter, TokioPostgresWriteAdapter};
use igniter_machine::postgres_write::{
    PostgresWriteExecutor, PostgresWriteIntent, PostgresWritePolicy,
};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};

use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::OnceCell;
use tokio_postgres::{Client, NoTls};

const READ_CAP: &str = "IO.PostgresRead"; // host read capability — never named by the app.
const WRITE_CAP: &str = "IO.TodoWrite"; // host write capability — never named by the app.

// ── operator-owned, test-owned DDL (NOT language-owned; no migration framework) ───────────────────
// `done` is TEXT because the app's authored `WriteValues.done` is a string ("false"/"true") in this
// fixture — the schema mirrors the app's shape rather than the app bending to the DB.
const DDL: &str = "\
    CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL);\
    CREATE TABLE IF NOT EXISTS todos (\
      id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),\
      title TEXT, done TEXT NOT NULL DEFAULT 'false', inserted_at TIMESTAMPTZ DEFAULT now());\
    CREATE TABLE IF NOT EXISTS effect_receipts (\
      idempotency_key TEXT PRIMARY KEY, correlation_id TEXT, target TEXT NOT NULL,\
      business_key TEXT NOT NULL, committed_at TIMESTAMPTZ NOT NULL DEFAULT now());";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}
fn write_passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".into(),
        capability_id: WRITE_CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn read_policy() -> PostgresReadPolicy {
    PostgresReadPolicy::new(100)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}
fn write_policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new()
        .allow_target("todos")
        .allow_ops(&["insert", "upsert"])
}

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

/// Load the prelude + the PRODUCT app's authored `todo_handlers.ig` so its query / continuation / command
/// contracts can be dispatched directly (ZERO app Rust).
fn load_app_contracts() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_local_p8_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    let handlers = app_dir().join("todo_handlers.ig");
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            handlers.to_string_lossy().to_string(),
        ],
        "ListTodosByAccount",
    )
    .expect("load todo_postgres_app contracts");
    m
}

/// Connect (or SKIP), ensure schema once, and clean ONLY this test's keys/ids/account (parallel-safe).
/// Returns a raw client for seeding + the DSN for the real adapters, or `None` to skip.
async fn prepare(account: &str, todo_ids: &[&str], idem_keys: &[&str]) -> Option<(Client, String)> {
    let dsn = match std::env::var("IGNITER_TODO_PG_DSN") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            eprintln!("SKIP: IGNITER_TODO_PG_DSN not set — local Postgres Todo e2e skipped");
            return None;
        }
    };
    let (client, conn) = tokio_postgres::connect(&dsn, NoTls)
        .await
        .expect("connect for setup");
    tokio::spawn(async move {
        let _ = conn.await;
    });
    // Run the schema DDL EXACTLY ONCE per process — concurrent `CREATE TABLE IF NOT EXISTS` from parallel
    // tests races on `pg_type` (SQLSTATE 23505); the OnceCell serializes it away (mirrors the machine
    // real-write harness).
    static SCHEMA_READY: OnceCell<()> = OnceCell::const_new();
    SCHEMA_READY
        .get_or_init(|| async {
            client.batch_execute(DDL).await.expect("DDL");
        })
        .await;
    // clean only what THIS test owns (children first for the FK).
    for k in idem_keys {
        client
            .execute(
                "DELETE FROM effect_receipts WHERE idempotency_key = $1",
                &[k],
            )
            .await
            .unwrap();
    }
    for id in todo_ids {
        client
            .execute("DELETE FROM todos WHERE id = $1", &[id])
            .await
            .unwrap();
    }
    client
        .execute("DELETE FROM accounts WHERE id = $1", &[&account])
        .await
        .unwrap();
    client
        .execute(
            "INSERT INTO accounts (id, name) VALUES ($1, $2)",
            &[&account, &"Test Account"],
        )
        .await
        .unwrap();
    Some((client, dsn))
}

async fn receipt_state(store: &Arc<dyn TBackend>, cap: &str, key: &str) -> WriteState {
    let f = store
        .read_as_of(RECEIPTS_STORE, &format!("{cap}:{key}"), f64::MAX)
        .await
        .unwrap()
        .unwrap();
    WriteState::from_str(f.value.get("state").and_then(|s| s.as_str()).unwrap_or(""))
}

/// Run the app QueryPlan through the host read contour (real adapter) and return the executor outcome.
async fn host_read(dsn: &str, plan: &Value) -> igniter_machine::capability::EffectOutcome {
    let adapter = Arc::new(
        TokioPostgresReadAdapter::connect(dsn)
            .await
            .expect("read adapter connect"),
    );
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(PostgresReadExecutor::new(
        READ_CAP,
        adapter,
        read_policy(),
    )));
    let store: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let req = EffectRequest {
        capability_id: READ_CAP.to_string(),
        idempotency_key: "rq".to_string(),
        authority_ref: Some("passport:test".to_string()),
        args: plan.clone(),
    };
    run_effect(&reg, &store, &req, RunMode::Live).await.unwrap()
}

fn min_req(account: &str) -> Value {
    json!({"method": "GET", "path": format!("/accounts/{account}/todos"), "body": "",
           "correlation_id": "", "idempotency_key": ""})
}

// ── 1: found read → real rows → app-owned 200 ─────────────────────────────────────────────────────

#[test]
fn local_read_found_returns_app_200() {
    rt().block_on(async {
        let Some((client, dsn)) = prepare("acct-7", &["todo-1", "todo-2"], &[]).await else {
            return;
        };
        // seed two real rows for this account.
        for (id, title) in [("todo-1", "Buy milk"), ("todo-2", "Write spec")] {
            client
                .execute(
                    "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                    &[&id, &"acct-7", &title],
                )
                .await
                .unwrap();
        }
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7"}))
            .await
            .unwrap();
        assert_eq!(
            plan["source"],
            json!("todos"),
            "app QueryPlan, not Rust SQL"
        );
        assert_eq!(plan["op"], json!("select"));

        let out = host_read(&dsn, &plan).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert!(
            out.result["count"].as_i64().unwrap() >= 2,
            "real rows returned"
        );

        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let found = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req("acct-7"), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(found["__arm"], json!("Respond"));
        assert_eq!(found["status"], json!(200), "found rows → app 200");
        assert!(found["body"].as_str().unwrap().contains("todo-1"));
    });
}

// ── 2: empty read → app-owned 404 (product decision, not infra failure) ───────────────────────────

#[test]
fn local_read_empty_returns_app_404() {
    rt().block_on(async {
        let Some((_client, dsn)) = prepare("acct-empty", &[], &[]).await else {
            return;
        };
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-empty"}))
            .await
            .unwrap();
        let out = host_read(&dsn, &plan).await;
        assert_eq!(out.result["count"], json!(0), "no rows for this account");
        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let not_found = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req("acct-empty"), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(
            not_found["status"],
            json!(404),
            "empty rows → app 404, not infra error"
        );
    });
}

// ── 3: write → real business row + PG effect_receipts row + machine receipt ───────────────────────

#[test]
fn local_write_creates_business_row_and_receipt() {
    rt().block_on(async {
        let key = "evt-local-create-1";
        let Some((client, dsn)) = prepare("acct-7", &[key], &[key]).await else {
            return;
        };
        let m = load_app_contracts();
        // the app builds the structured WriteIntent (P7) — the value `InvokeEffect.input` carries.
        let intent = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "idempotency_key": key}),
            )
            .await
            .unwrap();
        assert!(intent.is_object());

        // host write contour: real adapter bound to `todos(id; account_id,title,done)`.
        let adapter = Arc::new(
            TokioPostgresWriteAdapter::connect(
                &dsn,
                "todos",
                "id",
                &["account_id", "title", "done"],
            )
            .await
            .expect("write adapter connect"),
        );
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(PostgresWriteExecutor::new(
            WRITE_CAP,
            adapter.clone(),
            write_policy(),
        )));
        let store = receipts();
        let req = WriteRequest {
            capability_id: WRITE_CAP.into(),
            operation: "insert".into(),
            idempotency_key: key.into(),
            payload: intent.clone(),
        };
        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(adapter.attempts(), 1, "exactly one real transaction");
        // real business row present, with the app-authored values.
        assert_eq!(
            adapter
                .read_business_text(key, "account_id")
                .await
                .as_deref(),
            Some("acct-7")
        );
        // machine receipt records committed.
        assert_eq!(
            receipt_state(&store, WRITE_CAP, key).await,
            WriteState::Committed
        );
        // PG-side effect_receipts row present for this key.
        let n: i64 = client
            .query_one(
                "SELECT count(*) FROM effect_receipts WHERE idempotency_key = $1",
                &[&key],
            )
            .await
            .unwrap()
            .get(0);
        assert_eq!(n, 1, "PG effect_receipts row written");
    });
}

// ── 4: replay same idempotency key → NO second business mutation ──────────────────────────────────

#[test]
fn local_write_replay_no_second_mutation() {
    rt().block_on(async {
        let key = "evt-local-replay-1";
        let Some((_client, dsn)) = prepare("acct-7", &[key], &[key]).await else {
            return;
        };
        let m = load_app_contracts();
        let intent = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "idempotency_key": key}),
            )
            .await
            .unwrap();
        let adapter = Arc::new(
            TokioPostgresWriteAdapter::connect(
                &dsn,
                "todos",
                "id",
                &["account_id", "title", "done"],
            )
            .await
            .expect("write adapter connect"),
        );
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(Arc::new(PostgresWriteExecutor::new(
            WRITE_CAP,
            adapter.clone(),
            write_policy(),
        )));
        let store = receipts();
        let req = WriteRequest {
            capability_id: WRITE_CAP.into(),
            operation: "insert".into(),
            idempotency_key: key.into(),
            payload: intent,
        };
        // SAME store + SAME key twice: the machine receipt makes the 2nd call a replay (no executor hit).
        let a = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(a.state, WriteState::Committed);
        let b = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &req,
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(
            b.state,
            WriteState::Committed,
            "replay still reports committed"
        );
        assert_eq!(
            adapter.attempts(),
            1,
            "same key → exactly one real mutation"
        );
    });
}

// ── 5: raw SQL in the structured intent is refused BEFORE any adapter (pure gate; no DSN needed) ──

#[test]
fn write_intent_raw_sql_refused_before_adapter() {
    // host gate is pure — provable without a live DB, so this asserts even in the no-DSN skip path.
    let malicious = json!({
        "operation": "insert", "target": "todos", "key": "k",
        "values": {"title": "x"}, "raw_sql": "DROP TABLE todos"
    });
    let err = PostgresWriteIntent::from_args(&malicious).unwrap_err();
    assert!(
        err.contains("raw SQL refused"),
        "raw SQL refused before adapter: {err}"
    );
}
