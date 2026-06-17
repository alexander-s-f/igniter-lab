//! LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8 — real local Postgres write + reconcile (opt-in integration).
//!
//! Compiled ONLY under `--features postgres`; each test SKIPS when no `IGNITER_PG_WRITE_DSN` is set.
//! Proves the P3 write boundary + P4 reconcile against a REAL local Postgres, with the SAME
//! observable contract as the fakes. **Dedicated test DB only** — a SEPARATE env var
//! (`IGNITER_PG_WRITE_DSN`, never the read DSN) so these can never touch SparkCRM business tables.
//!
//! Run (dedicated DB):
//!   IGNITER_PG_WRITE_DSN="host=localhost user=alex dbname=igniter_pg_test" \
//!     cargo test --no-default-features --features postgres --test postgres_real_write_tests
//!
//! One effect = one atomic statement (effect_receipts ON CONFLICT + conditional business upsert).

#![cfg(feature = "postgres")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::postgres_real::TokioPostgresWriteAdapter;
use igniter_machine::postgres_write::{
    reconcile_postgres_unknown_write, PostgresReconcileResult, PostgresWriteExecutor, PostgresWritePolicy,
};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::json;
use std::sync::Arc;
use tokio::sync::OnceCell;
use tokio_postgres::NoTls;

const CAP: &str = "IO.PostgresWrite";

const DDL: &str = "\
    CREATE TABLE IF NOT EXISTS effect_receipts (\
      idempotency_key TEXT PRIMARY KEY, correlation_id TEXT, target TEXT NOT NULL,\
      business_key TEXT NOT NULL, committed_at TIMESTAMPTZ NOT NULL DEFAULT now());\
    CREATE TABLE IF NOT EXISTS leads (\
      id TEXT PRIMARY KEY, name TEXT, status TEXT NOT NULL);";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".into(), capability_id: CAP.into(), scopes: vec!["write".into()],
        issued_at: 0.0, expires_at: Some(1_000_000.0), revoked: false, evidence_digest: "sig".into(),
    }
}
fn policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new().allow_target("leads").allow_ops(&["insert", "upsert"])
}
fn registry(adapter: Arc<TokioPostgresWriteAdapter>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(PostgresWriteExecutor::new(CAP, adapter, policy())));
    reg
}
fn write_req(key: &str, name: &str, status: Option<&str>) -> WriteRequest {
    let mut values = json!({ "name": name });
    if let Some(s) = status {
        values["status"] = json!(s);
    }
    WriteRequest {
        capability_id: CAP.into(), operation: "insert".into(), idempotency_key: key.into(),
        payload: json!({ "operation": "insert", "target": "leads", "key": format!("lead-{key}"),
                         "values": values, "correlation_id": format!("corr-{key}") }),
    }
}

/// Connect + ensure schema + clean THIS test's keys/ids (parallel-safe isolation), or skip.
async fn prepare(idem_keys: &[&str]) -> Option<Arc<TokioPostgresWriteAdapter>> {
    let dsn = match std::env::var("IGNITER_PG_WRITE_DSN") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            eprintln!("SKIP: IGNITER_PG_WRITE_DSN not set — real Postgres write test skipped");
            return None;
        }
    };
    let (client, conn) = tokio_postgres::connect(&dsn, NoTls).await.expect("connect for setup");
    tokio::spawn(async move { let _ = conn.await; });
    // Run the schema DDL EXACTLY ONCE per process — concurrent `CREATE TABLE IF NOT EXISTS` from
    // parallel tests races on `pg_type` (SQLSTATE 23505); the OnceCell serializes it away.
    static SCHEMA_READY: OnceCell<()> = OnceCell::const_new();
    SCHEMA_READY.get_or_init(|| async { client.batch_execute(DDL).await.expect("DDL"); }).await;
    for k in idem_keys {
        client.execute("DELETE FROM effect_receipts WHERE idempotency_key = $1", &[k]).await.unwrap();
        client.execute("DELETE FROM leads WHERE id = $1", &[&format!("lead-{k}")]).await.unwrap();
    }
    let a = TokioPostgresWriteAdapter::connect(&dsn, "leads", "id", &["name", "status"]).await.expect("adapter connect");
    Some(Arc::new(a))
}

async fn receipt_state(store: &Arc<dyn TBackend>, key: &str) -> WriteState {
    let f = store.read_as_of(RECEIPTS_STORE, &format!("{CAP}:{key}"), f64::MAX).await.unwrap().unwrap();
    WriteState::from_str(f.value.get("state").and_then(|s| s.as_str()).unwrap_or(""))
}

async fn plant_unknown(store: &Arc<dyn TBackend>, key: &str) {
    let rkey = format!("{CAP}:{key}");
    let value = json!({
        "capability_id": CAP, "operation": "insert", "idempotency_key": key,
        "authority_digest": "AUTH", "payload_digest": "PD", "correlation_id": format!("corr-{key}"),
        "state": "unknown_external_state", "result": serde_json::Value::Null, "detail": serde_json::Value::Null,
    });
    store.write_fact(Fact {
        id: format!("write-receipt:{rkey}:unknown"), store: RECEIPTS_STORE.into(), key: rkey, value,
        value_hash: String::new(), causation: None, transaction_time: 200.0, valid_time: None,
        schema_version: 1, producer: None, derivation: None,
    }).await.unwrap();
}

// ── commit lifecycle: machine committed + real business row + real effect receipt ──

#[test]
fn real_commit_lifecycle() {
    rt().block_on(async {
        let Some(adapter) = prepare(&["p8c"]).await else { return };
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(&reg, &store, &clock(), &passport(), "write", &write_req("p8c", "Ada", Some("new")), RunMode::Live).await.unwrap();

        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(adapter.attempts(), 1);
        // real business row written + real PG effect receipt present.
        assert_eq!(adapter.read_business_text("lead-p8c", "name").await.as_deref(), Some("Ada"));
        assert_eq!(adapter.read_business_text("lead-p8c", "status").await.as_deref(), Some("new"));
        assert_eq!(receipt_state(&store, "p8c").await, WriteState::Committed);
    });
}

// ── PG-side dedup blocks a 2nd business mutation when the machine receipt is LOST ──

#[test]
fn real_pg_side_dedup_blocks_second_mutation() {
    rt().block_on(async {
        let Some(adapter) = prepare(&["p8d"]).await else { return };
        let reg = registry(adapter.clone());

        // First commit (store A): business row "Ada", PG effect receipt recorded.
        let store_a = receipts();
        let a = run_write_effect(&reg, &store_a, &clock(), &passport(), "write", &write_req("p8d", "Ada", Some("new")), RunMode::Live).await.unwrap();
        assert_eq!(a.state, WriteState::Committed);

        // Machine receipt LOST (fresh store B) + a DIFFERENT name on the same idempotency key.
        let store_b = receipts();
        let b = run_write_effect(&reg, &store_b, &clock(), &passport(), "write", &write_req("p8d", "EVIL", Some("won")), RunMode::Live).await.unwrap();

        assert_eq!(b.state, WriteState::Committed);
        assert_eq!(b.result["duplicate"], json!(true), "PG-side dedup");
        assert_eq!(adapter.attempts(), 2, "executor reached twice (machine receipt lost)");
        // the business row was NOT overwritten — exactly one mutation despite two attempts.
        assert_eq!(adapter.read_business_text("lead-p8d", "name").await.as_deref(), Some("Ada"), "no second mutation");
    });
}

// ── replay same key+payload bypasses the adapter via the machine receipt ──────

#[test]
fn real_replay_bypasses_adapter() {
    rt().block_on(async {
        let Some(adapter) = prepare(&["p8r"]).await else { return };
        let reg = registry(adapter.clone());
        let store = receipts();

        run_write_effect(&reg, &store, &clock(), &passport(), "write", &write_req("p8r", "Ada", Some("new")), RunMode::Live).await.unwrap();
        let b = run_write_effect(&reg, &store, &clock(), &passport(), "write", &write_req("p8r", "Ada", Some("new")), RunMode::Live).await.unwrap();

        assert_eq!(b.state, WriteState::Committed);
        assert_eq!(adapter.attempts(), 1, "machine receipt replay never reaches the DB");
    });
}

// ── constraint violation (NOT NULL status) → permanent; atomic rollback (no receipt) ──

#[test]
fn real_constraint_violation_is_permanent() {
    rt().block_on(async {
        let Some(adapter) = prepare(&["p8x"]).await else { return };
        let reg = registry(adapter.clone());
        let store = receipts();

        // omit status → NOT NULL violation (23502) inside the atomic statement.
        let out = run_write_effect(&reg, &store, &clock(), &passport(), "write", &write_req("p8x", "NoStatus", None), RunMode::Live).await.unwrap();

        assert_eq!(out.state, WriteState::PermanentFailure);
        // atomic: neither the business row nor the effect receipt landed.
        assert_eq!(adapter.read_business_text("lead-p8x", "name").await, None);
    });
}

// ── reconcile: unknown + real PG effect receipt found → committed (read-only) ──

#[test]
fn real_reconcile_found_commits_not_found_permanent() {
    rt().block_on(async {
        let Some(adapter) = prepare(&["p8rec", "p8miss"]).await else { return };
        let reg = registry(adapter.clone());
        let store = receipts();

        // a real committed write → PG effect receipt for p8rec exists.
        run_write_effect(&reg, &store, &clock(), &passport(), "write", &write_req("p8rec", "Ada", Some("new")), RunMode::Live).await.unwrap();
        let attempts_after_write = adapter.attempts();

        // plant an UNKNOWN machine receipt over p8rec at tt=200; reconcile at tt=300 so the
        // resolved terminal wins the as-of read.
        let c300: Arc<dyn ClockProvider> = Arc::new(FixedClock::new(300.0));
        plant_unknown(&store, "p8rec").await;
        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &c300, CAP, "p8rec").await.unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedCommitted);
        assert_eq!(receipt_state(&store, "p8rec").await, WriteState::Committed);

        // a key with NO PG effect receipt → permanent_failure.
        plant_unknown(&store, "p8miss").await;
        let r2 = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &c300, CAP, "p8miss").await.unwrap();
        assert_eq!(r2, PostgresReconcileResult::ResolvedPermanentFailure);

        // reconcile is READ-ONLY: no new transaction / business mutation.
        assert_eq!(adapter.attempts(), attempts_after_write, "reconcile does not transact");
    });
}
