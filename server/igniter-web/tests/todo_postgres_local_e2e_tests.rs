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
use igniter_machine::clock::{ClockProvider, FixedClock, SystemClock};
use igniter_machine::coordination::CoordinationHub;
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{PostgresReadExecutor, PostgresReadPolicy};
use igniter_machine::postgres_real::{TokioPostgresReadAdapter, TokioPostgresWriteAdapter};
use igniter_machine::postgres_write::{
    PostgresWriteExecutor, PostgresWriteIntent, PostgresWritePolicy,
};
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};

use igniter_server::effect_host::MachineEffectHost;
use igniter_server::serving_loop::ServingPolicy;
use igniter_web::host_binding::{
    build_staged_read_host_from_resolved, build_write_host_from_resolved,
};
use igniter_web::host_config::{load_host_config, resolve_host_config};
use igniter_web::machine_runner;
use igniter_web::runner::build_loaded_app_from_dir;

use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
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
        // P38: the index route's stage-1 existence read needs the `accounts` source allowlisted.
        .allow_source("accounts", &["id", "name"])
}
fn write_policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new()
        .allow_target("todos")
        .allow_ops(&["insert", "upsert", "delete"])
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
    // Clear ANY residual todos under this test's account before removing the account row — the account
    // namespace is test-owned, so prior tests in the same family may have left children that would
    // otherwise trip the `todos_account_id_fkey` FK (order-independent, single-threaded DB tests).
    client
        .execute("DELETE FROM todos WHERE account_id = $1", &[&account])
        .await
        .unwrap();
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

/// Like `host_read` but with a caller-chosen row cap, so a small page size forces multi-page keyset
/// traversal (LAB-TODOAPP-API-PAGINATION-KEYSET-P47).
async fn host_read_capped(
    dsn: &str,
    plan: &Value,
    cap: i64,
) -> igniter_machine::capability::EffectOutcome {
    let adapter = Arc::new(
        TokioPostgresReadAdapter::connect(dsn)
            .await
            .expect("read adapter connect"),
    );
    let pol = PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"]);
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, pol)));
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
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7", "after": ""}))
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

// ── 2: empty read → 200 [] (a list, not a not-found) — P24 ────────────────────────────────────────

#[test]
fn local_read_empty_returns_200_empty_list() {
    rt().block_on(async {
        let Some((_client, dsn)) = prepare("acct-empty", &[], &[]).await else {
            return;
        };
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-empty", "after": ""}))
            .await
            .unwrap();
        let out = host_read(&dsn, &plan).await;
        assert_eq!(out.result["count"], json!(0), "no rows for this account");
        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let empty_list = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req("acct-empty"), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(
            empty_list["status"],
            json!(200),
            "empty list → 200 [], not a not-found"
        );
        assert_eq!(empty_list["body"], json!("[]"), "body carries the empty array");
    });
}

// ── 2b: keyset pagination pages every row exactly once, ordered, no dup/miss (P47) ────────────────
//
// Seeds 5 todos, pages with a server cap of 2 (pages of 2,2,1 then empty), threading the last `id` of
// each page as the next `?after=` cursor. Proves the real adapter's Text `id > $cursor` + `ORDER BY id
// COLLATE "C"` give a stable, gap-free, duplicate-free traversal.

#[test]
fn local_keyset_pagination_pages_all_rows_once() {
    rt().block_on(async {
        let ids = ["todo-ka", "todo-kb", "todo-kc", "todo-kd", "todo-ke"];
        let Some((client, dsn)) = prepare("acct-ks", &ids, &[]).await else {
            return;
        };
        for id in ids {
            client
                .execute(
                    "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                    &[&id, &"acct-ks", &"t"],
                )
                .await
                .unwrap();
        }
        let m = load_app_contracts();

        let mut seen: Vec<String> = Vec::new();
        let mut after = String::new();
        for _hop in 0..10 {
            let plan = m
                .dispatch(
                    "ListTodosByAccount",
                    json!({"account_id": "acct-ks", "after": after}),
                )
                .await
                .unwrap();
            let out = host_read_capped(&dsn, &plan, 2).await;
            assert_eq!(out.kind, OutcomeKind::Succeeded);
            let rows = out.result["rows"].as_array().unwrap();
            if rows.is_empty() {
                break;
            }
            assert!(rows.len() <= 2, "page bounded by the cap");
            for r in rows {
                seen.push(r["id"].as_str().unwrap().to_string());
            }
            after = rows.last().unwrap()["id"].as_str().unwrap().to_string();
        }

        assert_eq!(
            seen,
            vec!["todo-ka", "todo-kb", "todo-kc", "todo-kd", "todo-ke"],
            "keyset paged every row exactly once, ascending id, no duplicate/missing across boundaries"
        );
    });
}

// ── 3: write → real business row + PG effect_receipts row + machine receipt ───────────────────────

#[test]
fn local_write_creates_business_row_and_receipt() {
    rt().block_on(async {
        let key = "evt-local-create-1";
        // P36: the business row id is the host-minted surrogate (`todo_` + digest), DECOUPLED from the
        // idempotency key. The test plays the host: it mints the same surrogate the runner would and
        // reads the business row by THAT id — the idempotency key is only the receipt/replay identity.
        let surrogate = igniter_web::surrogate_id("POST", "/accounts/acct-7/todos", key);
        let business_id = format!("todo_{surrogate}");
        let Some((client, dsn)) = prepare("acct-7", &[&business_id], &[key]).await else {
            return;
        };
        let m = load_app_contracts();
        // the app builds the structured WriteIntent (P7) — the value `InvokeEffect.input` carries.
        let intent = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": surrogate, "title": "Buy milk"}),
            )
            .await
            .unwrap();
        assert!(intent.is_object());
        assert_eq!(
            intent["key"],
            json!(business_id),
            "P36: business key = host surrogate, not the idempotency key"
        );
        assert_eq!(
            intent["values"]["title"],
            json!("Buy milk"),
            "P16: title from body"
        );

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
        // real business row present under the SURROGATE id, with the app-authored values (incl. the
        // body-derived title — P16). Querying by the raw idempotency key would find nothing (P36).
        assert_eq!(
            adapter
                .read_business_text(&business_id, "account_id")
                .await
                .as_deref(),
            Some("acct-7")
        );
        assert_eq!(
            adapter
                .read_business_text(&business_id, "title")
                .await
                .as_deref(),
            Some("Buy milk"),
            "P16: real business row title = the create body"
        );
        // machine receipt records committed — still keyed by the idempotency key (P36 auditability).
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
        let surrogate = igniter_web::surrogate_id("POST", "/accounts/acct-7/todos", key);
        let business_id = format!("todo_{surrogate}");
        let Some((_client, dsn)) = prepare("acct-7", &[&business_id], &[key]).await else {
            return;
        };
        let m = load_app_contracts();
        let intent = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": surrogate, "title": "Buy milk"}),
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

// ── 4b: done → marks an EXISTING row done=true by business key (todo_id); replay = no 2nd mutation ─
//
// LAB-TODOAPP-API-DONE-BUSINESS-KEY-P15. The app's BuildMarkTodoDoneIntent keys the write by the route
// `todo_id` (the business row), with operation "upsert" (the adapter is INSERT … ON CONFLICT DO UPDATE).
// v0 is a full-row upsert: account_id is carried (so the FK stays valid) and done flips to "true"; the
// title is NOT preserved (no partial PATCH). The effect idempotency key is the request's.

#[test]
fn local_done_marks_existing_row_done() {
    rt().block_on(async {
        let key = "evt-local-done-1";
        let todo_id = "todo-p15-done";
        let Some((client, dsn)) = prepare("acct-p15", &[todo_id], &[key]).await else {
            return;
        };
        // an existing todo for this account, not yet done, with a real title.
        client
            .execute(
                "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                &[&todo_id, &"acct-p15", &"Original title"],
            )
            .await
            .unwrap();

        let m = load_app_contracts();
        let intent = m
            .dispatch(
                "BuildMarkTodoDoneIntent",
                json!({"account_id": "acct-p15", "todo_id": todo_id, "idempotency_key": key}),
            )
            .await
            .unwrap();
        assert_eq!(
            intent["key"],
            json!(todo_id),
            "business key = route todo_id"
        );
        assert_eq!(intent["operation"], json!("upsert"));

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
            operation: "upsert".into(),
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

        // the existing row is now done, with its FK-valid account preserved.
        assert_eq!(
            adapter.read_business_text(todo_id, "done").await.as_deref(),
            Some("true"),
            "existing row flipped to done=true"
        );
        assert_eq!(
            adapter
                .read_business_text(todo_id, "account_id")
                .await
                .as_deref(),
            Some("acct-p15"),
            "account_id preserved (FK intact)"
        );

        // replay same idempotency key → no second mutation (machine receipt short-circuits).
        let again = run_write_effect(
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
        assert_eq!(again.state, WriteState::Committed, "replay still committed");
        assert_eq!(
            adapter.attempts(),
            1,
            "same done key → exactly one real mutation"
        );

        // PG-side effect_receipts keyed by THIS done idempotency key (business_key = todo_id).
        let n: i64 = client
            .query_one(
                "SELECT count(*) FROM effect_receipts WHERE business_key = $1",
                &[&todo_id],
            )
            .await
            .unwrap()
            .get(0);
        assert_eq!(n, 1, "exactly one PG effect_receipts row for the done");
    });
}

// ── 4d: delete → removes an EXISTING row by business key (todo_id); idempotent; conflict refused ──
//
// LAB-TODOAPP-API-DELETE-P44. The app's BuildDeleteTodoIntent keys the write by the route `todo_id`,
// operation "delete" (the real adapter's DELETE branch under the same effect-receipt gate as upsert).
// Delete is idempotent: the row is gone after commit, a replay of the same key performs no second
// mutation, and the same key reused with a DIFFERENT payload is refused before the adapter (the 409).

#[test]
fn local_delete_removes_existing_row_idempotently() {
    rt().block_on(async {
        let key = "evt-local-delete-1";
        let todo_id = "todo-p44-del";
        let Some((client, dsn)) = prepare("acct-p44", &[todo_id, "todo-p44-other"], &[key]).await
        else {
            return;
        };
        client
            .execute(
                "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                &[&todo_id, &"acct-p44", &"To be deleted"],
            )
            .await
            .unwrap();

        let m = load_app_contracts();
        let intent = m
            .dispatch(
                "BuildDeleteTodoIntent",
                json!({"account_id": "acct-p44", "todo_id": todo_id, "idempotency_key": key}),
            )
            .await
            .unwrap();
        assert_eq!(intent["operation"], json!("delete"));
        assert_eq!(intent["key"], json!(todo_id), "business key = route todo_id");

        let adapter = Arc::new(
            TokioPostgresWriteAdapter::connect(&dsn, "todos", "id", &["account_id", "title", "done"])
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
            operation: "delete".into(),
            idempotency_key: key.into(),
            payload: intent.clone(),
        };
        let out =
            run_write_effect(&reg, &store, &clock(), &write_passport(), "write", &req, RunMode::Live)
                .await
                .unwrap();
        assert_eq!(out.state, WriteState::Committed);

        // the row is gone (delete actually removed it).
        assert_eq!(
            adapter.read_business_text(todo_id, "id").await,
            None,
            "row removed by delete"
        );

        // replay same idempotency key → no second mutation (machine receipt short-circuits).
        let again =
            run_write_effect(&reg, &store, &clock(), &write_passport(), "write", &req, RunMode::Live)
                .await
                .unwrap();
        assert_eq!(again.state, WriteState::Committed, "replay still committed");
        assert_eq!(adapter.attempts(), 1, "same delete key → exactly one real mutation");

        // same idempotency key + DIFFERENT payload (different business key) → refused before the adapter.
        let other_intent = m
            .dispatch(
                "BuildDeleteTodoIntent",
                json!({"account_id": "acct-p44", "todo_id": "todo-p44-other", "idempotency_key": key}),
            )
            .await
            .unwrap();
        let conflict_req = WriteRequest {
            capability_id: WRITE_CAP.into(),
            operation: "delete".into(),
            idempotency_key: key.into(),
            payload: other_intent,
        };
        let conflict = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &conflict_req,
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(
            conflict.state,
            WriteState::Denied,
            "same key + different payload → refused (the 409)"
        );
        assert_eq!(adapter.attempts(), 1, "conflict refused before the adapter — no new mutation");

        // PG-side effect_receipts keyed by THIS delete idempotency key (business_key = todo_id).
        let n: i64 = client
            .query_one(
                "SELECT count(*) FROM effect_receipts WHERE business_key = $1",
                &[&todo_id],
            )
            .await
            .unwrap()
            .get(0);
        assert_eq!(n, 1, "exactly one PG effect_receipts row for the delete");
    });
}

// ── 4c: read freshness — a same-plan list AFTER a write, in one process, returns the new row ──────
//
// LAB-TODOAPP-API-READ-FRESHNESS-P23. With NO client correlation, two identical-plan reads sharing one
// `StagedReadHost` (one receipts store, like a single server process) must each run fresh — so an empty
// list, then a write, then the same list, observes the new row instead of replaying the empty result.

#[test]
fn local_read_after_write_is_fresh_same_process() {
    rt().block_on(async {
        let acct = "fresh-p23";
        let todo_id = "todo-fresh-1";
        let Some((client, dsn)) = prepare(acct, &[todo_id], &[]).await else {
            return;
        };

        // One real read host, persisting receipts across reads (mirrors one server process).
        let radapter = Arc::new(
            TokioPostgresReadAdapter::connect(&dsn)
                .await
                .expect("read adapter connect"),
        );
        let mut rreg = CapabilityExecutorRegistry::new();
        rreg.register(Arc::new(PostgresReadExecutor::new(
            READ_CAP,
            radapter,
            read_policy(),
        )));
        let rrecs: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let read_host = igniter_web::read_dispatch::StagedReadHost::new(rreg, rrecs, READ_CAP);
        let (app, _) = build_loaded_app_from_dir(&app_dir()).unwrap();

        let list_req = || {
            igniter_server::protocol::ServerRequest::new(
                "GET",
                &format!("/accounts/{acct}/todos"),
                Value::Null,
            )
        };
        let respond_parts = |d: igniter_server::protocol::ServerDecision| -> (u16, Value) {
            match d {
                igniter_server::protocol::ServerDecision::Respond { response } => {
                    let body = match response.body {
                        igniter_server::protocol::ResponseBody::Json(v) => v,
                        _ => Value::Null,
                    };
                    (response.status, body)
                }
                other => panic!("expected Respond, got {other:?}"),
            }
        };

        // 1. empty account → 200 [] (P24: an empty list is a valid 200, not a 404)
        let (s1, b1) = respond_parts(app.dispatch_with_read(list_req(), &read_host).await);
        assert_eq!(s1, 200, "empty account lists 200 [] first");
        assert!(
            !b1.to_string().contains(todo_id),
            "first list is empty — no row yet; body={b1}"
        );

        // 2. a real row appears in the same DB
        client
            .execute(
                "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                &[&todo_id, &acct, &"Fresh row"],
            )
            .await
            .unwrap();

        // 3. same list, same read host (same receipts), no correlation → MUST be fresh: the new row
        //    appears, proving the prior empty result was NOT replayed (freshness, P23).
        let (s2, b2) = respond_parts(app.dispatch_with_read(list_req(), &read_host).await);
        assert_eq!(s2, 200, "post-write list still 200");
        assert!(
            b2.to_string().contains(todo_id),
            "fresh list carries the newly written row id (not a replayed empty list); body={b2}"
        );
    });
}

// ── 4d (P38): account existence — missing account → 404; existing account, zero todos → 200 [] ────
//
// LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38, against REAL Postgres. The index route is a two-stage read:
// stage 1 proves the account exists in `accounts`; only then is the `todos` list issued. This isolates
// the semantic the single-`todos` read could not express — "no such account → 404" vs "exists, empty → 200 []".

#[test]
fn local_account_existence_missing_404_and_existing_empty_200() {
    rt().block_on(async {
        let existing = "acct-p38-empty";
        let missing = "acct-p38-missing";
        let Some((client, dsn)) = prepare(existing, &[], &[]).await else {
            return;
        };
        // `prepare` cleans + inserts `existing`; ensure `missing` truly does not exist (children first).
        client
            .execute("DELETE FROM todos WHERE account_id = $1", &[&missing])
            .await
            .unwrap();
        client
            .execute("DELETE FROM accounts WHERE id = $1", &[&missing])
            .await
            .unwrap();

        let radapter = Arc::new(
            TokioPostgresReadAdapter::connect(&dsn)
                .await
                .expect("read adapter connect"),
        );
        let mut rreg = CapabilityExecutorRegistry::new();
        rreg.register(Arc::new(PostgresReadExecutor::new(
            READ_CAP,
            radapter,
            read_policy(),
        )));
        let rrecs: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let read_host = igniter_web::read_dispatch::StagedReadHost::new(rreg, rrecs, READ_CAP);
        let (app, _) = build_loaded_app_from_dir(&app_dir()).unwrap();

        let list = |acct: &str| {
            igniter_server::protocol::ServerRequest::new(
                "GET",
                &format!("/accounts/{acct}/todos"),
                Value::Null,
            )
        };
        let parts = |d: igniter_server::protocol::ServerDecision| -> (u16, Value) {
            match d {
                igniter_server::protocol::ServerDecision::Respond { response } => {
                    let body = match response.body {
                        igniter_server::protocol::ResponseBody::Json(v) => v,
                        _ => Value::Null,
                    };
                    (response.status, body)
                }
                other => panic!("expected Respond, got {other:?}"),
            }
        };

        // Existing account, zero todos → 200 [] (stage 1 found the account; stage 2 list is empty).
        let (s_empty, b_empty) = parts(app.dispatch_with_read(list(existing), &read_host).await);
        assert_eq!(s_empty, 200, "existing account, no todos → 200 []; body={b_empty}");
        assert_eq!(b_empty["body"], json!("[]"), "empty list body, not a 404");

        // Missing account → 404 (stage-1 existence read empty → app-owned 404; list never issued).
        let (s_missing, b_missing) = parts(app.dispatch_with_read(list(missing), &read_host).await);
        assert_eq!(s_missing, 404, "missing account → 404; body={b_missing}");
        // P43: app-authored errors carry the typed envelope {"error":{"code","message"}}.
        assert_eq!(
            b_missing["error"]["code"],
            json!("account_not_found"),
            "app-owned account-existence 404 code"
        );
        assert_eq!(
            b_missing["error"]["message"],
            json!("account not found"),
            "app-owned account-existence 404 message"
        );

        client
            .execute("DELETE FROM accounts WHERE id = $1", &[&existing])
            .await
            .ok();
    });
}

// ── 6: binary path — build_staged_read_host_from_resolved → real adapter → HTTP 200 ─────────────
//
// Proves the binary's actual construction path (P25): same function the binary calls under
// --features postgres when [postgres.read] is configured.  Skips cleanly without
// IGNITER_TODO_PG_DSN; no subprocess, no stable CLI claim.

#[test]
fn binary_path_readhost_from_config_found_200() {
    rt().block_on(async {
        let Some((client, dsn)) = prepare("acct-p25-cfg", &["todo-p25-1", "todo-p25-2"], &[]).await
        else {
            return;
        };
        for (id, title) in [("todo-p25-1", "P25 smoke A"), ("todo-p25-2", "P25 smoke B")] {
            client
                .execute(
                    "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                    &[&id, &"acct-p25-cfg", &title],
                )
                .await
                .unwrap();
        }

        // Write temp host.toml referencing a dedicated env var so resolution is self-contained.
        let dsn_env = "IGNITER_P25_PG_READ_DSN";
        std::env::set_var(dsn_env, &dsn);
        let toml = format!(
            "[postgres.read]\ndsn_env = \"{dsn_env}\"\nsource = \"todos\"\n\
             fields = \"id,account_id,title,done\"\nrow_limit = \"50\"\n\
             capability = \"IO.PostgresRead\"\n\
             \n[postgres.read.accounts]\nfields = \"id,name\"\n"
        );
        let tmp = std::env::temp_dir().join("igweb-p25-binary-path.toml");
        std::fs::write(&tmp, &toml).unwrap();

        // Binary path: load_host_config → resolve → build real StagedReadHost.
        let cfg = load_host_config(&tmp).unwrap();
        let resolved = resolve_host_config(&cfg).unwrap();
        assert!(
            resolved.postgres_read_dsn.is_some(),
            "DSN must resolve from env"
        );
        let read_host = build_staged_read_host_from_resolved(&cfg, &resolved)
            .await
            .expect("build_staged_read_host_from_resolved must succeed")
            .expect("[postgres.read] present → Some(host)");

        // No-op effect host: write not exercised; same infrastructure as binary's v0 path.
        let router = IngressRouter::new();
        let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let clk: Arc<dyn ClockProvider> = Arc::new(SystemClock);
        let hub = CoordinationHub::new(audit.clone(), Arc::clone(&clk));
        let reg = CapabilityExecutorRegistry::new();
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let ep = CapabilityPassport {
            subject: "host".to_string(),
            capability_id: "noop".to_string(),
            scopes: vec![],
            issued_at: 0.0,
            expires_at: None,
            revoked: false,
            evidence_digest: String::new(),
        };
        let sf = SingleFlight::new();
        let bridge_cfg = EffectBridgeConfig {
            registry: &reg,
            receipts: &receipts,
            effect_clock: &clk,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: "noop".to_string(),
            operation: "noop".to_string(),
            scope: "noop".to_string(),
        };
        let effect_host = MachineEffectHost::new(&router, &hub, &bridge_cfg);

        let app_dir =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/todo_postgres_app");
        let (app, _) = build_loaded_app_from_dir(&app_dir).unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client_task = tokio::spawn(async move {
            let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
            let req =
                "GET /accounts/acct-p25-cfg/todos HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n";
            s.write_all(req.as_bytes()).await.unwrap();
            s.flush().await.unwrap();
            let mut buf = Vec::new();
            s.read_to_end(&mut buf).await.unwrap();
            String::from_utf8_lossy(&buf).to_string()
        });

        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(
            &listener,
            &app,
            &effect_host,
            &read_host,
            &policy,
        )
        .await
        .unwrap();

        let raw = client_task.await.unwrap();
        let status: u16 = raw
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        assert_eq!(
            status, 200,
            "binary path build_staged_read_host_from_resolved → real read → 200; raw={raw}"
        );
        assert!(
            raw.contains("todo-p25-1"),
            "response must contain seeded todo id; raw={raw}"
        );

        std::env::remove_var(dsn_env);
        std::fs::remove_file(&tmp).ok();
    });
}

// ── 7: binary path — build_write_host_from_resolved → real adapter → HTTP 200 + replay ────────────
//
// Proves the binary's actual write construction path (P26): same function the binary calls under
// --features postgres when [postgres.write] + [effects.*] + passport_env are configured.
// Also proves: replay same idempotency key produces no second mutation (dedup_strict in recipe).
// Skips cleanly without IGNITER_TODO_PG_DSN; no subprocess, no stable CLI claim.

#[test]
fn binary_path_write_from_config_committed() {
    rt().block_on(async {
        let idem_key = "p26-write-k1";
        let Some((_client, dsn)) = prepare("acct-p26-cfg", &[idem_key], &[idem_key]).await else {
            return;
        };

        let tok_env = "IGNITER_P26_VENDOR_TOKEN";
        let write_env = "IGNITER_P26_PG_WRITE_DSN";
        let tok_val = "p26-vtok";
        std::env::set_var(tok_env, tok_val);
        std::env::set_var(write_env, &dsn);

        let toml = format!(
            "[postgres.write]\n\
             dsn_env = \"{write_env}\"\n\
             targets = \"todos\"\n\
             key_column = \"id\"\n\
             columns = \"account_id,title,done\"\n\
             ops = \"insert,upsert\"\n\
             capability = \"IO.TodoWrite\"\n\
             \n\
             [effects.todo-create]\n\
             route = \"/w\"\n\
             passport_env = \"{tok_env}\"\n\
             \n\
             [effects.todo-done]\n\
             route = \"/w\"\n\
             passport_env = \"{tok_env}\"\n"
        );
        let tmp = std::env::temp_dir().join("igweb-p26-binary-write.toml");
        std::fs::write(&tmp, &toml).unwrap();

        let cfg = load_host_config(&tmp).unwrap();
        let resolved = resolve_host_config(&cfg).unwrap();
        assert!(
            resolved.postgres_write_dsn.is_some(),
            "write DSN must resolve from env"
        );

        // Binary path: build_write_host_from_resolved.
        let state = build_write_host_from_resolved(&cfg, &resolved)
            .await
            .expect("build_write_host_from_resolved must succeed")
            .expect("[postgres.write] + passport_env present → Some(components)");

        use igniter_machine::ingress::EffectBridgeConfig;
        use igniter_server::effect_host::MachineEffectHost;
        let bridge_cfg = EffectBridgeConfig {
            registry: &state.registry,
            receipts: &state.receipts,
            effect_clock: &state.clk,
            effect_passport: &state.ep,
            single_flight: &state.sf,
            capability_id: state.capability_id.clone(),
            operation: "write_record".to_string(),
            scope: "write".to_string(),
        };
        let mut effect_host = MachineEffectHost::new(&state.router, &state.hub, &bridge_cfg);
        for (target, route) in &state.bind_targets {
            effect_host.bind_target(target, route);
        }

        // No-op read host (not exercised by POST requests).
        let read_reg = CapabilityExecutorRegistry::new();
        let read_recs: std::sync::Arc<dyn igniter_machine::backend::TBackend> =
            std::sync::Arc::new(InMemoryBackend::new());
        let read_host =
            igniter_web::read_dispatch::StagedReadHost::new(read_reg, read_recs, "IO.PostgresRead");

        let app_dir =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/todo_postgres_app");
        let (app, _) = build_loaded_app_from_dir(&app_dir).unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let build_post = |key: &str| {
            let tok = tok_val;
            // P45: the object create body is the ONLY accepted shape (legacy string body removed).
            let body = "{\"title\":\"Buy milk\"}";
            format!(
                "POST /accounts/acct-p26-cfg/todos HTTP/1.1\r\nHost: x\r\n\
                 Authorization: Bearer {tok}\r\n\
                 idempotency-key: {key}\r\n\
                 Content-Length: {}\r\n\r\n{}",
                body.len(),
                body
            )
        };

        // Client task: first POST (fresh write), then second POST (same key → dedup replay).
        let post1 = build_post(idem_key);
        let post2 = build_post(idem_key);
        let client_task = tokio::spawn(async move {
            let send_raw = |raw: String| async move {
                let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
                s.write_all(raw.as_bytes()).await.unwrap();
                s.flush().await.unwrap();
                let mut buf = Vec::new();
                s.read_to_end(&mut buf).await.unwrap();
                String::from_utf8_lossy(&buf).to_string()
            };
            let r1 = send_raw(post1).await;
            let r2 = send_raw(post2).await;
            (r1, r2)
        });

        let policy = ServingPolicy::new(2).loopback_only();
        machine_runner::serve_loop_loaded_with_read(
            &listener,
            &app,
            &effect_host,
            &read_host,
            &policy,
        )
        .await
        .unwrap();

        let (raw1, raw2) = client_task.await.unwrap();
        let status1: u16 = raw1
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        let status2: u16 = raw2
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        assert_eq!(status1, 200, "first POST → 200 committed; raw={raw1}");
        assert_eq!(
            status2, 200,
            "second POST (same key) → 200 dedup replay; raw={raw2}"
        );

        std::env::remove_var(tok_env);
        std::env::remove_var(write_env);
        std::fs::remove_file(&tmp).ok();
    });
}

// ── 8: REAL SUBPROCESS — the product command end-to-end (LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12)
//
// Unlike sections 6/7 (which call the binary's builder fns directly), this spawns the ACTUAL compiled
// `igweb-serve` binary as a subprocess and drives it over a real loopback socket — exercising CLI parsing,
// env-var resolution before bind, the combined [postgres.read] + [postgres.write] + [effects.*] wiring,
// and deterministic `--max-requests` exit. One operator-owned host.toml (env-var refs only); both DSN refs
// point at the same dedicated test DB. Proves all four product behaviors in one run:
//   read found  → 200    read empty → 200 [] (a list, not a not-found; P24)
//   write       → 200 committed (real business row + PG effect_receipts row)
//   replay key  → 200, NO second mutation (exactly one business row)
// The binary is located via CARGO_BIN_EXE_igweb-serve (compiled with the same --features as this test).
// Skips cleanly without IGNITER_TODO_PG_DSN. No stable CLI claim; no daemon left running.

#[test]
fn subprocess_product_command_read_write_replay_e2e() {
    use tokio::io::{AsyncBufReadExt, BufReader};
    use tokio::process::Command;
    use tokio::time::{timeout, Duration};

    rt().block_on(async {
        let write_key = "p12-write-k1";
        let seeded = ["todo-p12-a", "todo-p12-b"];
        // P36: the created business row lands under the host-minted surrogate id, not the idempotency
        // key. Recompute the SAME id the running binary mints, so the DB assertions target the real row.
        let written_id = format!(
            "todo_{}",
            igniter_web::surrogate_id("POST", "/accounts/acct-p12-sub/todos", write_key)
        );
        // prepare seeds the account + cleans the keys/ids this test owns (incl. the written row).
        let Some((client, dsn)) = prepare(
            "acct-p12-sub",
            &["todo-p12-a", "todo-p12-b", &written_id],
            &[write_key],
        )
        .await
        else {
            return;
        };
        for (id, title) in [(seeded[0], "P12 sub A"), (seeded[1], "P12 sub B")] {
            client
                .execute(
                    "INSERT INTO todos (id, account_id, title, done) VALUES ($1,$2,$3,'false')",
                    &[&id, &"acct-p12-sub", &title],
                )
                .await
                .unwrap();
        }
        // The ingress/coordination path keys PG `effect_receipts` by `intent.key + ":<attempt>"`, so the
        // exact-key clean in `prepare` (which only knows the un-suffixed key) cannot reach it. Clear it by
        // the stable `business_key` (== intent.key == the minted surrogate id, P36) so a re-run starts
        // from a genuinely fresh write.
        client
            .execute(
                "DELETE FROM effect_receipts WHERE business_key = $1",
                &[&written_id],
            )
            .await
            .unwrap();

        // Operator-owned host.toml: both read + write sections, env-var DSN refs only (no inline secret).
        let read_env = "IGNITER_P12_PG_READ_DSN";
        let write_env = "IGNITER_P12_PG_WRITE_DSN";
        let tok_env = "IGNITER_P12_VENDOR_TOKEN";
        let tok_val = "p12-vtok";
        let toml = format!(
            "[postgres.read]\n\
             dsn_env = \"{read_env}\"\n\
             source = \"todos\"\n\
             fields = \"id,account_id,title,done\"\n\
             row_limit = \"50\"\n\
             capability = \"IO.PostgresRead\"\n\
             \n\
             [postgres.read.accounts]\n\
             fields = \"id,name\"\n\
             \n\
             [postgres.write]\n\
             dsn_env = \"{write_env}\"\n\
             targets = \"todos\"\n\
             key_column = \"id\"\n\
             columns = \"account_id,title,done\"\n\
             ops = \"insert,upsert\"\n\
             capability = \"IO.TodoWrite\"\n\
             \n\
             [effects.todo-create]\n\
             route = \"/w\"\n\
             passport_env = \"{tok_env}\"\n\
             \n\
             [effects.todo-done]\n\
             route = \"/w\"\n\
             passport_env = \"{tok_env}\"\n"
        );
        let tmp =
            std::env::temp_dir().join(format!("igweb-p12-subprocess-{}.toml", std::process::id()));
        std::fs::write(&tmp, &toml).unwrap();

        let app_dir =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/todo_postgres_app");

        // Spawn the ACTUAL binary. Env vars set on the child only (parent env stays clean); both DSN refs
        // point at the same dedicated test DB.
        let mut child = Command::new(env!("CARGO_BIN_EXE_igweb-serve"))
            .arg("--host-config")
            .arg(&tmp)
            .arg("--addr")
            .arg("127.0.0.1:0")
            .arg("--max-requests")
            .arg("4")
            .arg(&app_dir)
            .env(read_env, &dsn)
            .env(write_env, &dsn)
            .env(tok_env, tok_val)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .expect("spawn igweb-serve");

        // Drain stderr into a shared buffer for diagnostics (and so a full pipe never blocks the child).
        let err_buf = Arc::new(std::sync::Mutex::new(String::new()));
        let err_task = {
            let buf = err_buf.clone();
            let stderr = child.stderr.take().unwrap();
            tokio::spawn(async move {
                let mut r = BufReader::new(stderr);
                let mut line = String::new();
                loop {
                    line.clear();
                    match r.read_line(&mut line).await {
                        Ok(0) | Err(_) => break,
                        Ok(_) => buf.lock().unwrap().push_str(&line),
                    }
                }
            })
        };
        let errs = {
            let buf = err_buf.clone();
            move || buf.lock().unwrap().clone()
        };

        fn parse_listen_addr(line: &str) -> Option<String> {
            let marker = "listening http://";
            let i = line.find(marker)? + marker.len();
            let rest = &line[i..];
            let end = rest.find(char::is_whitespace).unwrap_or(rest.len());
            Some(rest[..end].to_string())
        }

        // Read stdout until the binary prints its bound address (env resolves + DB connects before bind).
        let stdout = child.stdout.take().unwrap();
        let mut out = BufReader::new(stdout).lines();
        let addr = loop {
            match timeout(Duration::from_secs(30), out.next_line()).await {
                Ok(Ok(Some(l))) => {
                    if let Some(a) = parse_listen_addr(&l) {
                        break a;
                    }
                }
                Ok(Ok(None)) => {
                    panic!("igweb-serve exited before listening; stderr=\n{}", errs())
                }
                Ok(Err(e)) => panic!("stdout read error: {e}; stderr=\n{}", errs()),
                Err(_) => panic!("timeout waiting for listening line; stderr=\n{}", errs()),
            }
        };
        // Keep draining stdout so the child never blocks writing progress lines.
        let out_task =
            tokio::spawn(async move { while let Ok(Some(_)) = out.next_line().await {} });

        async fn http_send(addr: &str, raw: &str) -> String {
            let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
            s.write_all(raw.as_bytes()).await.unwrap();
            s.flush().await.unwrap();
            let mut buf = Vec::new();
            s.read_to_end(&mut buf).await.unwrap();
            String::from_utf8_lossy(&buf).to_string()
        }
        fn status_of(raw: &str) -> u16 {
            raw.split_whitespace()
                .nth(1)
                .and_then(|s| s.parse().ok())
                .unwrap_or(0)
        }

        // 4 requests, strictly sequential (one connection each, read to EOF) → bounded loop serves & exits.
        let get_found =
            "GET /accounts/acct-p12-sub/todos HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n";
        // P38: `acct-p12-missing` is never inserted → the two-stage read's stage-1 existence check is
        // empty → app-owned 404 (NOT the old conflated 200 []). Proves the fix through the real binary.
        let get_missing =
            "GET /accounts/acct-p12-missing/todos HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n";
        // v1 create body (P35): the preferred JSON OBJECT body `{ "title": … }`. Proves the object path
        // end-to-end through the REAL binary: host parses it to `req.body_json`, the app extracts `title`.
        let title_body = "{\"title\":\"Buy milk via P35\"}";
        let post = format!(
            "POST /accounts/acct-p12-sub/todos HTTP/1.1\r\nHost: x\r\n\
             Authorization: Bearer {tok_val}\r\nidempotency-key: {write_key}\r\n\
             Content-Length: {}\r\n\r\n{}",
            title_body.len(),
            title_body
        );

        let r_found = http_send(&addr, get_found).await;
        let r_missing = http_send(&addr, get_missing).await;
        let r_write = http_send(&addr, &post).await;
        let r_replay = http_send(&addr, &post).await;

        // Deterministic exit after exactly 4 requests (no daemon left running).
        let status = match timeout(Duration::from_secs(30), child.wait()).await {
            Ok(s) => s.expect("wait igweb-serve"),
            Err(_) => panic!(
                "igweb-serve did not exit after 4 requests; stderr=\n{}",
                errs()
            ),
        };
        out_task.await.ok();
        err_task.await.ok();
        assert!(
            status.success(),
            "igweb-serve exit status {status}; stderr=\n{}",
            errs()
        );

        // HTTP outcomes through the real binary.
        assert_eq!(status_of(&r_found), 200, "read found → 200; raw={r_found}");
        assert!(
            r_found.contains(seeded[0]),
            "found response carries a seeded todo id; raw={r_found}"
        );
        assert_eq!(
            status_of(&r_missing),
            404,
            "P38: missing account → app-owned 404 (not the old conflated 200 []); raw={r_missing}"
        );
        assert!(
            r_missing.contains("account not found"),
            "404 body is the app's account-existence message; raw={r_missing}"
        );
        assert_eq!(
            status_of(&r_write),
            200,
            "write create → 200 committed; raw={r_write}"
        );
        assert_eq!(
            status_of(&r_replay),
            200,
            "replay same key → 200 dedup; raw={r_replay}"
        );

        // DB truth: exactly one business row + one PG receipt for the MINTED id (replay = no 2nd
        // mutation). The row id is the surrogate (P36), NOT the idempotency key — proving the decouple.
        let n_row: i64 = client
            .query_one("SELECT count(*) FROM todos WHERE id = $1", &[&written_id])
            .await
            .unwrap()
            .get(0);
        assert_eq!(n_row, 1, "exactly one business row under the minted surrogate id");
        // The raw idempotency key is NOT a business row id (the coupling is gone).
        let n_by_key: i64 = client
            .query_one("SELECT count(*) FROM todos WHERE id = $1", &[&write_key])
            .await
            .unwrap()
            .get(0);
        assert_eq!(n_by_key, 0, "P36: the idempotency key is NOT stored as a Todo id");
        let acct: Option<String> = client
            .query_one("SELECT account_id FROM todos WHERE id = $1", &[&written_id])
            .await
            .unwrap()
            .get(0);
        assert_eq!(
            acct.as_deref(),
            Some("acct-p12-sub"),
            "business row carries the app-authored account_id"
        );
        // P35: the real business row title equals the `title` field of the submitted OBJECT body.
        let title: Option<String> = client
            .query_one("SELECT title FROM todos WHERE id = $1", &[&written_id])
            .await
            .unwrap()
            .get(0);
        assert_eq!(
            title.as_deref(),
            Some("Buy milk via P35"),
            "P35: real row title = the `title` field of the object create body"
        );
        // The PG effect_receipts row is keyed by the idempotency key (auditable) and records the minted
        // surrogate as its business_key (P36).
        let n_rcpt: i64 = client
            .query_one(
                "SELECT count(*) FROM effect_receipts WHERE business_key = $1",
                &[&written_id],
            )
            .await
            .unwrap()
            .get(0);
        assert_eq!(n_rcpt, 1, "exactly one PG effect_receipts row for the minted id");

        // Cleanup test-owned rows (children first for the FK), then the temp file.
        client
            .execute(
                "DELETE FROM effect_receipts WHERE business_key = $1",
                &[&written_id],
            )
            .await
            .ok();
        for id in [seeded[0], seeded[1], written_id.as_str()] {
            client
                .execute("DELETE FROM todos WHERE id = $1", &[&id])
                .await
                .ok();
        }
        client
            .execute("DELETE FROM accounts WHERE id = $1", &[&"acct-p12-sub"])
            .await
            .ok();
        std::fs::remove_file(&tmp).ok();
    });
}

// ── 9 (P19): same key + DIFFERENT payload → write-receipt conflict, real DB row UNCHANGED ─────────
//
// Defence-in-depth conflict at the write-receipt layer against a real Postgres adapter: the machine
// receipt binds the idempotency key to `payload_digest`. A reused key with a different payload is
// REFUSED before the executor (`WriteState::Denied`, detail "different payload") — the real business
// row keeps the FIRST payload's values and the adapter performs exactly one transaction. Skips cleanly
// without IGNITER_TODO_PG_DSN.

#[test]
fn local_write_same_key_different_payload_conflicts_row_unchanged() {
    rt().block_on(async {
        let key = "evt-local-conflict-1";
        // SAME idempotency key → SAME minted surrogate id for both attempts (P36); only the title differs.
        let surrogate = igniter_web::surrogate_id("POST", "/accounts/acct-7/todos", key);
        let business_id = format!("todo_{surrogate}");
        let Some((_client, dsn)) = prepare("acct-7", &[&business_id], &[key]).await else {
            return;
        };
        let m = load_app_contracts();
        // First intent: title "Buy milk". Second intent: SAME key, DIFFERENT title "Buy bread".
        let intent_a = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": surrogate, "title": "Buy milk"}),
            )
            .await
            .unwrap();
        let intent_b = m
            .dispatch(
                "BuildCreateTodoIntent",
                json!({"account_id": "acct-7", "surrogate_id": surrogate, "title": "Buy bread"}),
            )
            .await
            .unwrap();
        assert_eq!(intent_a["key"], json!(business_id), "same key → same surrogate id");
        assert_ne!(intent_a, intent_b, "different titles → different payloads");

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

        // First write commits the "Buy milk" row.
        let first = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &WriteRequest {
                capability_id: WRITE_CAP.into(),
                operation: "insert".into(),
                idempotency_key: key.into(),
                payload: intent_a.clone(),
            },
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.state, WriteState::Committed);

        // Second write: SAME key, DIFFERENT payload → refused at the receipt gate, executor NOT reached.
        let second = run_write_effect(
            &reg,
            &store,
            &clock(),
            &write_passport(),
            "write",
            &WriteRequest {
                capability_id: WRITE_CAP.into(),
                operation: "insert".into(),
                idempotency_key: key.into(),
                payload: intent_b.clone(),
            },
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(
            second.state,
            WriteState::Denied,
            "same key + different payload → Denied (conflict), not silent success"
        );
        assert!(
            second
                .detail
                .as_deref()
                .unwrap_or("")
                .contains("different payload"),
            "conflict detail names the payload mismatch; got {:?}",
            second.detail
        );

        assert_eq!(
            adapter.attempts(),
            1,
            "exactly one real transaction (conflict not executed)"
        );
        // The real business row keeps the FIRST payload's title — the conflicting write never mutated it.
        assert_eq!(
            adapter
                .read_business_text(&business_id, "title")
                .await
                .as_deref(),
            Some("Buy milk"),
            "conflicting write must NOT overwrite the row"
        );
    });
}

// ── P35: a title-less object body is rejected at the app; NO business row inserted (real DB) ──────
//
// Drives the REAL `igweb-serve` subprocess against local Postgres with a JSON OBJECT create body. The
// body contract fails closed to 400 in the app BEFORE any InvokeEffect, so no `todos` row and no PG
// `effect_receipts` row are written. Skips cleanly without IGNITER_TODO_PG_DSN.

#[test]
fn subprocess_non_string_create_body_writes_no_row() {
    use tokio::io::{AsyncBufReadExt, BufReader};
    use tokio::process::Command;
    use tokio::time::{timeout, Duration};

    rt().block_on(async {
        let bad_key = "p18-badbody-k1";
        // If a row were wrongly written it would land under the minted surrogate id (P36), so target that.
        let would_be_id = format!(
            "todo_{}",
            igniter_web::surrogate_id("POST", "/accounts/acct-p18-sub/todos", bad_key)
        );
        let Some((client, dsn)) = prepare("acct-p18-sub", &[&would_be_id], &[bad_key]).await else {
            return;
        };
        client
            .execute("DELETE FROM effect_receipts WHERE business_key = $1", &[&would_be_id])
            .await
            .unwrap();

        let read_env = "IGNITER_P35_PG_READ_DSN";
        let write_env = "IGNITER_P35_PG_WRITE_DSN";
        let tok_env = "IGNITER_P35_VENDOR_TOKEN";
        let tok_val = "p18-vtok";
        let toml = format!(
            "[postgres.read]\n\
             dsn_env = \"{read_env}\"\nsource = \"todos\"\n\
             fields = \"id,account_id,title,done\"\nrow_limit = \"50\"\ncapability = \"IO.PostgresRead\"\n\
             \n[postgres.write]\n\
             dsn_env = \"{write_env}\"\ntargets = \"todos\"\nkey_column = \"id\"\n\
             columns = \"account_id,title,done\"\nops = \"insert,upsert\"\ncapability = \"IO.TodoWrite\"\n\
             \n[effects.todo-create]\nroute = \"/w\"\npassport_env = \"{tok_env}\"\n\
             \n[effects.todo-done]\nroute = \"/w\"\npassport_env = \"{tok_env}\"\n"
        );
        let tmp = std::env::temp_dir().join(format!("igweb-p18-badbody-{}.toml", std::process::id()));
        std::fs::write(&tmp, &toml).unwrap();
        let app_dir =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/todo_postgres_app");

        let mut child = Command::new(env!("CARGO_BIN_EXE_igweb-serve"))
            .arg("--host-config").arg(&tmp)
            .arg("--addr").arg("127.0.0.1:0")
            .arg("--max-requests").arg("1")
            .arg(&app_dir)
            .env(read_env, &dsn).env(write_env, &dsn).env(tok_env, tok_val)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .expect("spawn igweb-serve");

        let stdout = child.stdout.take().unwrap();
        let mut out = BufReader::new(stdout).lines();
        let addr = loop {
            match timeout(Duration::from_secs(30), out.next_line()).await {
                Ok(Ok(Some(l))) => {
                    if let Some(i) = l.find("listening http://") {
                        let rest = &l[i + "listening http://".len()..];
                        break rest.split_whitespace().next().unwrap_or("").to_string();
                    }
                }
                _ => panic!("igweb-serve never reported a listening addr"),
            }
        };
        let out_task = tokio::spawn(async move { while let Ok(Some(_)) = out.next_line().await {} });

        // P35: object body MISSING a usable `title` — must be rejected with 400, no mutation.
        let body = "{\"note\":\"sneaky\"}";
        let raw = format!(
            "POST /accounts/acct-p18-sub/todos HTTP/1.1\r\nHost: x\r\n\
             Authorization: Bearer {tok_val}\r\nidempotency-key: {bad_key}\r\n\
             Content-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );
        let resp = {
            let mut s = tokio::net::TcpStream::connect(&addr).await.unwrap();
            s.write_all(raw.as_bytes()).await.unwrap();
            s.flush().await.unwrap();
            let mut buf = Vec::new();
            s.read_to_end(&mut buf).await.unwrap();
            String::from_utf8_lossy(&buf).to_string()
        };
        let status: u16 = resp.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        let _ = timeout(Duration::from_secs(30), child.wait()).await;
        out_task.await.ok();

        assert_eq!(status, 400, "object create body → 400; raw={resp}");
        // DB truth: no business row, no PG receipt for the id this request would have minted.
        let n_row: i64 = client
            .query_one("SELECT count(*) FROM todos WHERE id = $1", &[&would_be_id])
            .await
            .unwrap()
            .get(0);
        assert_eq!(n_row, 0, "rejected body must NOT insert a todos row");
        let n_rcpt: i64 = client
            .query_one("SELECT count(*) FROM effect_receipts WHERE business_key = $1", &[&would_be_id])
            .await
            .unwrap()
            .get(0);
        assert_eq!(n_rcpt, 0, "rejected body must NOT write a PG effect receipt");

        std::env::remove_var(read_env);
        std::env::remove_var(write_env);
        std::env::remove_var(tok_env);
        std::fs::remove_file(&tmp).ok();
        client.execute("DELETE FROM accounts WHERE id = $1", &[&"acct-p18-sub"]).await.ok();
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
