//! LAB-MACHINE-POSTGRES-RECONCILE-P4 — fake-adapter Postgres write reconcile.
//!
//! Closes the P3 `unknown_external_state` hole: an unknown (or dangling `prepared`) Postgres write
//! receipt is resolved by an EXACT, READ-ONLY lookup of the fake PG-side
//! `effect_receipts(idempotency_key)` table — found→committed, not-found→permanent_failure,
//! unavailable→still-unknown. The reconciler NEVER re-runs the write executor / `transact`. Lookup
//! is by idempotency-key identity (not values), so the P7 same-value false positive is impossible.
//!
//! Verify-first (this card): P3 added the PG-side fake `effect_receipts` table but no reconcile
//! helper. This file adds `reconcile_postgres_unknown_write` + the read-only resolver, fake-only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::postgres_write::{
    reconcile_postgres_unknown_write, FakePostgresWriteAdapter, FakeWriteBehavior,
    PostgresReconcileResult, PostgresWriteExecutor, PostgresWritePolicy,
};
use igniter_machine::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.PostgresWrite";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".to_string(),
        capability_id: CAP.to_string(),
        scopes: vec!["write".to_string()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig:pgw".to_string(),
    }
}

fn registry(adapter: Arc<FakePostgresWriteAdapter>) -> CapabilityExecutorRegistry {
    let policy = PostgresWritePolicy::new()
        .allow_target("leads")
        .allow_ops(&["insert", "upsert"]);
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(PostgresWriteExecutor::new(CAP, adapter, policy)));
    reg
}

fn write_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "insert".to_string(),
        idempotency_key: key.to_string(),
        payload: json!({
            "operation": "insert", "target": "leads", "key": "lead-1",
            "values": {"name": "Ada", "status": "new"}, "correlation_id": "c1",
        }),
    }
}

/// Manually plant a machine write receipt in a given state (models a dangling `prepared`, or an
/// `unknown` receipt whose effect did not land).
async fn plant_receipt(store: &Arc<dyn TBackend>, key: &str, state: &str) {
    let rkey = format!("{CAP}:{key}");
    let value = json!({
        "capability_id": CAP, "operation": "insert", "idempotency_key": key,
        "authority_digest": "AUTH", "payload_digest": "PD",
        "correlation_id": "c1", "state": state, "result": serde_json::Value::Null, "detail": serde_json::Value::Null,
    });
    let fact = Fact {
        id: format!("write-receipt:{rkey}:{state}"),
        store: RECEIPTS_STORE.to_string(),
        key: rkey,
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: 100.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    };
    store.write_fact(fact).await.unwrap();
}

async fn receipt_state(store: &Arc<dyn TBackend>, key: &str) -> WriteState {
    let f = store
        .read_as_of(RECEIPTS_STORE, &format!("{CAP}:{key}"), f64::MAX)
        .await
        .unwrap()
        .unwrap();
    WriteState::from_str(f.value.get("state").and_then(|s| s.as_str()).unwrap_or(""))
}

// ── found PG effect receipt → committed (landed-but-unknown), no re-execution ──

#[test]
fn unknown_with_pg_receipt_found_resolves_committed() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::CommitButLost,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        // The write commits (row + PG effect receipt) but the ack is lost → unknown machine receipt.
        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k1"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
        assert!(adapter.has_effect_receipt("k1"));
        assert_eq!(adapter.attempts(), 1);
        assert_eq!(adapter.business_row_count(), 1);

        // Reconcile: read-only lookup finds the PG effect receipt → committed.
        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "k1")
            .await
            .unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedCommitted);
        assert_eq!(receipt_state(&store, "k1").await, WriteState::Committed);

        // read-only: no re-execution, no new mutation.
        assert_eq!(adapter.attempts(), 1, "reconcile must not call transact");
        assert_eq!(adapter.business_row_count(), 1);

        // evidence preserved in the terminal receipt.
        let f = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:k1"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(f.value["reconciled_by"], json!("pg_effect_receipt"));
        assert_eq!(f.value["idempotency_key"], json!("k1"));
        assert_eq!(f.value["correlation_id"], json!("c1"));
        assert_eq!(f.value["pg_effect_receipt"]["target"], json!("leads"));
        assert_eq!(f.value["pg_effect_receipt"]["key"], json!("lead-1"));
    });
}

// ── no PG effect receipt → permanent_failure (did not land) ───────────────────

#[test]
fn unknown_with_no_pg_receipt_resolves_permanent_failure() {
    rt().block_on(async {
        // Unknown behavior records NOTHING (rolled back, response lost ambiguously).
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Unknown));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k2"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
        assert!(!adapter.has_effect_receipt("k2"));

        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "k2")
            .await
            .unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedPermanentFailure);
        assert_eq!(
            receipt_state(&store, "k2").await,
            WriteState::PermanentFailure
        );
        assert_eq!(adapter.business_row_count(), 0);
    });
}

// ── resolver unavailable → still unknown ──────────────────────────────────────

#[test]
fn resolver_unavailable_keeps_unknown() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::CommitButLost,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k3"),
            RunMode::Live,
        )
        .await
        .unwrap();
        adapter.set_resolver_down(true);

        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "k3")
            .await
            .unwrap();
        assert_eq!(r, PostgresReconcileResult::StillUnknown);
        assert_eq!(
            receipt_state(&store, "k3").await,
            WriteState::UnknownExternalState,
            "stays unknown"
        );
    });
}

// ── dangling `prepared` reconciled through the same path ──────────────────────

#[test]
fn dangling_prepared_reconciled() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::CommitButLost));
        let store = receipts();

        // Seed the PG effect receipt directly (the effect landed) — a direct adapter call.
        let intent = igniter_machine::postgres_write::PostgresWriteIntent::from_args(&json!({
            "operation": "insert", "target": "leads", "key": "lead-1", "values": {}, "correlation_id": "c1",
        }))
        .unwrap();
        use igniter_machine::postgres_write::PostgresWriteAdapter;
        let _ = adapter.transact(&intent, "kprep").await; // records effect receipt for kprep
        assert!(adapter.has_effect_receipt("kprep"));

        // Machine receipt is stuck at `prepared` (crash before terminal receipt, P19 shape).
        plant_receipt(&store, "kprep", "prepared").await;
        assert_eq!(receipt_state(&store, "kprep").await, WriteState::Prepared);

        let attempts_before = adapter.attempts();
        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "kprep").await.unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedCommitted);
        assert_eq!(receipt_state(&store, "kprep").await, WriteState::Committed);
        assert_eq!(adapter.attempts(), attempts_before, "reconcile does not transact");
    });
}

// ── recovered committed receipt replays without re-executing ──────────────────

#[test]
fn recovered_committed_replays_without_re_executing() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::CommitButLost,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k4"),
            RunMode::Live,
        )
        .await
        .unwrap();
        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "k4")
            .await
            .unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedCommitted);

        // A subsequent same-key + same-payload write replays the reconciled committed receipt
        // (authority/payload digests were preserved) — the executor is NOT re-entered.
        let replay = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k4"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(replay.state, WriteState::Committed);
        assert_eq!(
            adapter.attempts(),
            1,
            "reconciled-committed receipt replays, no re-execution"
        );
        assert_eq!(adapter.business_row_count(), 1);
    });
}

// ── same-value false positive impossible: lookup is by key identity, not values ──

#[test]
fn same_value_different_key_no_false_positive() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::CommitButLost,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        // "landed" actually committed (PG effect receipt present).
        run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("landed"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert!(adapter.has_effect_receipt("landed"));

        // "notlanded" has the SAME values/correlation but NO effect receipt (planted unknown).
        plant_receipt(&store, "notlanded", "unknown_external_state").await;
        assert!(!adapter.has_effect_receipt("notlanded"));

        // Despite identical values, reconcile keys by idempotency identity → not-found → permanent.
        let r =
            reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "notlanded")
                .await
                .unwrap();
        assert_eq!(r, PostgresReconcileResult::ResolvedPermanentFailure);
        assert_eq!(
            receipt_state(&store, "notlanded").await,
            WriteState::PermanentFailure
        );

        // while the genuinely-landed key resolves committed.
        let r2 =
            reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "landed")
                .await
                .unwrap();
        assert_eq!(r2, PostgresReconcileResult::ResolvedCommitted);
    });
}

// ── not-applicable / no-receipt guards ────────────────────────────────────────

#[test]
fn committed_receipt_is_not_applicable_and_missing_is_no_receipt() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());
        let store = receipts();

        run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("done"),
            RunMode::Live,
        )
        .await
        .unwrap();
        let r = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "done")
            .await
            .unwrap();
        assert_eq!(
            r,
            PostgresReconcileResult::NotApplicable(WriteState::Committed)
        );

        let r2 = reconcile_postgres_unknown_write(&store, adapter.as_ref(), &clock(), CAP, "ghost")
            .await
            .unwrap();
        assert_eq!(r2, PostgresReconcileResult::NoReceipt);
    });
}
