//! LAB-MACHINE-POSTGRES-WRITE-GATE-P3 — fake-adapter Postgres receipt-gated write.
//!
//! Proves the Postgres-shaped WRITE boundary WITHOUT a real database: a `PostgresWriteExecutor`
//! is a `CapabilityExecutor`, driven by the EXISTING `write::run_write_effect` two-phase receipt
//! protocol. Two idempotency layers — the machine `__receipts__` spine AND a fake PG-side
//! `effect_receipts(idempotency_key)` table. No `tokio-postgres`/`sqlx`/`diesel`, no SQL, no
//! network, no new dependency.
//!
//! Verify-first (this card): P2 (`postgres_read`) is read-only; before P3 there was NO Postgres
//! WRITE executor in the crate. This file adds the first one, fake-only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::postgres_write::{
    FakePostgresWriteAdapter, FakeWriteBehavior, PostgresWriteExecutor, PostgresWritePolicy,
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

fn policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new()
        .allow_target("leads")
        .allow_ops(&["insert", "upsert"])
}

fn registry(adapter: Arc<FakePostgresWriteAdapter>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(Arc::new(PostgresWriteExecutor::new(CAP, adapter, policy())));
    reg
}

fn write_req(key: &str, payload: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "insert".to_string(),
        idempotency_key: key.to_string(),
        payload,
    }
}

fn intent(corr: &str) -> serde_json::Value {
    json!({
        "operation": "insert",
        "target": "leads",
        "key": "lead-1",
        "values": {"name": "Ada", "status": "new"},
        "correlation_id": corr,
    })
}

// ── #5: success lifecycle — machine receipt prepared→committed + business row + PG receipt ──

#[test]
fn commit_lifecycle_business_row_and_pg_receipt() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k1", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(out.result["committed"], json!(true));
        assert_eq!(out.result["duplicate"], json!(false));
        // fake business mutation + PG-side effect receipt both landed (one transaction).
        assert_eq!(adapter.business_row_count(), 1);
        assert!(adapter.has_effect_receipt("k1"));
        assert_eq!(adapter.attempts(), 1);

        // machine receipt is two-phase: a `prepared` fact precedes the `committed` terminal.
        let hist = store
            .facts_for(RECEIPTS_STORE, &format!("{CAP}:k1"), None, None)
            .await
            .unwrap();
        let states: Vec<String> = hist
            .iter()
            .filter_map(|f| {
                f.value
                    .get("state")
                    .and_then(|s| s.as_str())
                    .map(|s| s.to_string())
            })
            .collect();
        assert!(
            states.contains(&"prepared".to_string()),
            "prepared gate fact must exist: {states:?}"
        );
        assert!(
            states.contains(&"committed".to_string()),
            "committed terminal fact must exist: {states:?}"
        );

        // terminal receipt records correlation + idempotency key, NOT raw SQL / business values.
        let terminal = store
            .read_as_of(RECEIPTS_STORE, &format!("{CAP}:k1"), f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(terminal.value["state"], json!("committed"));
        assert_eq!(terminal.value["correlation_id"], json!("c1"));
        assert_eq!(terminal.value["idempotency_key"], json!("k1"));
        let receipt_text = terminal.value.to_string().to_lowercase();
        assert!(
            !receipt_text.contains("select ") && !receipt_text.contains("insert into"),
            "no raw SQL in receipt"
        );
    });
}

// ── #4: raw SQL payload refused structurally before the adapter ───────────────

#[test]
fn raw_sql_payload_refused_structurally() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-sql", json!({"sql": "INSERT INTO leads VALUES ('x')"})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::PermanentFailure);
        assert!(out.detail.unwrap().contains("raw SQL refused"));
        assert_eq!(
            adapter.attempts(),
            0,
            "adapter must never see a raw-SQL payload"
        );
        assert_eq!(adapter.business_row_count(), 0);
    });
}

// ── #6: replay same key + same payload bypasses the adapter via machine receipt ──

#[test]
fn replay_same_key_same_payload_bypasses_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());
        let store = receipts();

        let a = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("dup", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        let b = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("dup", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(a.state, WriteState::Committed);
        assert_eq!(b.state, WriteState::Committed); // replayed from machine receipt
        assert_eq!(
            adapter.attempts(),
            1,
            "machine receipt replay never reaches the adapter"
        );
        assert_eq!(adapter.business_row_count(), 1);
    });
}

// ── #7: same key + different payload refused before the adapter (machine layer) ──

#[test]
fn same_key_different_payload_refused_before_adapter() {
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
            &write_req("kx", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        // same idempotency key, different payload (correlation differs → digest differs).
        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("kx", intent("DIFFERENT")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::Denied);
        assert!(out.detail.unwrap().contains("different payload"));
        assert_eq!(
            adapter.attempts(),
            1,
            "second (conflicting) request must not reach the adapter"
        );
        assert_eq!(adapter.business_row_count(), 1);
    });
}

// ── #8: PG-side duplicate key blocks a 2nd mutation when the machine receipt is LOST ──

#[test]
fn pg_side_dedup_blocks_second_mutation_when_machine_receipt_lost() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());

        // First attempt against receipts store A → commits, PG effect receipt recorded.
        let store_a = receipts();
        let a = run_write_effect(
            &reg,
            &store_a,
            &clock(),
            &passport(),
            "write",
            &write_req("k-lost", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(a.state, WriteState::Committed);

        // Simulate the machine receipt being LOST: a FRESH receipts store B with no prior receipt.
        // The machine layer finds nothing → prepares → reaches the executor again. But the PG-side
        // effect_receipts(idempotency_key) still has the key → DuplicateKey, no 2nd mutation.
        let store_b = receipts();
        let b = run_write_effect(
            &reg,
            &store_b,
            &clock(),
            &passport(),
            "write",
            &write_req("k-lost", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(b.state, WriteState::Committed);
        assert_eq!(
            b.result["duplicate"],
            json!(true),
            "second hit is a PG-side dedup"
        );
        assert_eq!(
            adapter.attempts(),
            2,
            "executor reached twice (machine receipt was lost)"
        );
        assert_eq!(
            adapter.business_row_count(),
            1,
            "but the business mutation happened exactly once"
        );
    });
}

// ── #9: transient rolled-back → retryable; lost/unknown → unknown + no blind retry ──

#[test]
fn serialization_failure_is_retryable() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::SerializationFailure,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-ser", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Retryable);
        assert_eq!(adapter.business_row_count(), 0, "rolled back — no mutation");
    });
}

#[test]
fn unknown_is_unknown_with_no_blind_retry() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Unknown));
        let reg = registry(adapter.clone());
        let store = receipts();

        let first = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-unk", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.state, WriteState::UnknownExternalState);
        assert_eq!(adapter.attempts(), 1);

        // a re-run on the same key sees the unknown receipt → NO blind retry (executor not reached).
        let second = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-unk", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(second.state, WriteState::UnknownExternalState);
        assert!(second.detail.unwrap().contains("no blind retry"));
        assert_eq!(
            adapter.attempts(),
            1,
            "unknown receipt must not trigger a blind re-execution"
        );
    });
}

// ── #10: constraint/type → permanent; policy/authorization denial → denied ────

#[test]
fn constraint_violation_is_permanent() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(
            FakeWriteBehavior::ConstraintViolation,
        ));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-con", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::PermanentFailure);
        assert!(out.detail.unwrap().contains("constraint violation"));
        assert_eq!(adapter.business_row_count(), 0);
    });
}

#[test]
fn adapter_denied_maps_to_denied() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Denied));
        let reg = registry(adapter.clone());
        let store = receipts();

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-den", intent("c1")),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Denied);
        assert_eq!(adapter.business_row_count(), 0);
    });
}

// ── #10 (policy gates): disallowed target / op refused BEFORE the adapter ─────

#[test]
fn policy_gates_refuse_before_adapter() {
    rt().block_on(async {
        let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
        let reg = registry(adapter.clone());
        let store = receipts();

        // target not allowlisted.
        let bad_target =
            json!({"operation": "insert", "target": "secrets", "key": "x", "values": {}});
        let out1 = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-t", bad_target),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out1.state, WriteState::Denied);

        // op not allowlisted (delete is not in [insert, upsert]).
        let bad_op = json!({"operation": "delete", "target": "leads", "key": "x", "values": {}});
        let out2 = run_write_effect(
            &reg,
            &store,
            &clock(),
            &passport(),
            "write",
            &write_req("k-o", bad_op),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out2.state, WriteState::Denied);

        assert_eq!(
            adapter.attempts(),
            0,
            "gate refusals never reach the adapter"
        );
        assert_eq!(adapter.business_row_count(), 0);
    });
}
