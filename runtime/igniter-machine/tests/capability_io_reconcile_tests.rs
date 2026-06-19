//! LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7 — read-back resolution of unknown writes.
//!
//! After a write resolves to `unknown_external_state`, reconciliation READS the target back
//! (never re-writes) and resolves the receipt to committed / permanent_failure / still-unknown.
//! No blind retry. Prerequisite for a future retry scheduler.

use igniter_machine::backend::{InMemoryBackend, RemoteTcpBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::executors::TBackendWriteExecutor;
use igniter_machine::fact::Fact;
use igniter_machine::reconcile::{reconcile_unknown_write, ReconcileResult};
use igniter_machine::write::{run_write_effect, FactWrite, WriteRequest, WriteState};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.WriteCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
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
        evidence_digest: "sig:w".to_string(),
    }
}

fn write_req(key: &str, store: &str, rec: &str, value: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "put_fact".to_string(),
        idempotency_key: key.to_string(),
        payload: FactWrite { store: store.to_string(), key: rec.to_string(), value, valid_time: None }.to_payload(),
    }
}

fn fact(store: &str, key: &str, value: serde_json::Value) -> Fact {
    Fact {
        id: format!("{}:{}", store, key),
        store: store.to_string(),
        key: key.to_string(),
        value,
        value_hash: String::new(),
        causation: None,
        transaction_time: 1.0,
        valid_time: None,
        schema_version: 1,
        producer: None,
        derivation: None,
    }
}

/// Produce an `unknown_external_state` write receipt (executor failed to confirm the write)
/// against `substrate`, using the failing write executor (which does NOT touch the substrate).
async fn make_unknown_receipt(
    receipts: &Arc<dyn TBackend>,
    substrate: &Arc<dyn TBackend>,
    key: &str,
    rec: &str,
    value: serde_json::Value,
) {
    let exec = Arc::new(TBackendWriteExecutor::failing(CAP, substrate.clone(), clock()));
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    let out = run_write_effect(&reg, receipts, &clock(), &passport(), "write", &write_req(key, "orders", rec, value), RunMode::Live)
        .await
        .unwrap();
    assert_eq!(out.state, WriteState::UnknownExternalState);
}

// ── unknown → committed when the value actually landed ─────────────────────────

#[test]
fn reconcile_resolves_committed_when_value_landed() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        make_unknown_receipt(&receipts, &substrate, "k1", "ord-1", json!({"total": 5})).await;
        // simulate: the mutation actually DID land (ack was lost → we recorded unknown)
        substrate.write_fact(fact("orders", "ord-1", json!({"total": 5}))).await.unwrap();

        let before = substrate.facts_for("orders", "ord-1", None, None).await.unwrap().len();
        let r = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "k1").await.unwrap();
        assert_eq!(r, ReconcileResult::ResolvedCommitted);
        // reconcile reads only — substrate unchanged (no blind retry)
        let after = substrate.facts_for("orders", "ord-1", None, None).await.unwrap().len();
        assert_eq!(before, after);

        // the receipt is now committed
        let receipt = receipts.read_as_of(RECEIPTS_STORE, "IO.WriteCapability:k1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(receipt.value["state"], json!("committed"));
        assert_eq!(receipt.value["reconciled"], json!(true));
    });
}

// ── unknown → permanent_failure when the value never landed ────────────────────

#[test]
fn reconcile_resolves_permanent_failure_when_absent() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        make_unknown_receipt(&receipts, &substrate, "k2", "ord-2", json!({"total": 9})).await;
        // substrate has NO matching fact → the mutation did not land

        let r = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "k2").await.unwrap();
        assert_eq!(r, ReconcileResult::ResolvedPermanentFailure);
        // no blind retry: substrate still empty for this key
        assert!(substrate.read_as_of("orders", "ord-2", f64::MAX).await.unwrap().is_none());

        let receipt = receipts.read_as_of(RECEIPTS_STORE, "IO.WriteCapability:k2", f64::MAX).await.unwrap().unwrap();
        assert_eq!(receipt.value["state"], json!("permanent_failure"));
    });
}

// ── unknown stays unknown when the substrate cannot be read ────────────────────

#[test]
fn reconcile_still_unknown_when_substrate_unavailable() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let healthy: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // build the unknown receipt against a healthy substrate (so target fields are recorded)
        make_unknown_receipt(&receipts, &healthy, "k3", "ord-3", json!({"total": 1})).await;

        // reconcile against an UNAVAILABLE substrate (dead TCP port) → cannot determine
        let dead: Arc<dyn TBackend> = Arc::new(RemoteTcpBackend::new("127.0.0.1:1".to_string()));
        let r = reconcile_unknown_write(&receipts, &dead, &clock(), CAP, "k3").await.unwrap();
        assert_eq!(r, ReconcileResult::StillUnknown);

        // the receipt is untouched — still unknown, no premature resolution
        let receipt = receipts.read_as_of(RECEIPTS_STORE, "IO.WriteCapability:k3", f64::MAX).await.unwrap().unwrap();
        assert_eq!(receipt.value["state"], json!("unknown_external_state"));
    });
}

// ── terminal receipt is not reconciled (idempotent no-op) ──────────────────────

#[test]
fn reconcile_is_noop_on_terminal_receipt() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        // a committed write
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, substrate.clone(), clock()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &write_req("c1", "orders", "ord-c", json!({"total": 3})), RunMode::Live).await.unwrap();

        let r = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "c1").await.unwrap();
        assert_eq!(r, ReconcileResult::NotApplicable(WriteState::Committed));
    });
}

// ── after reconcile→committed, a re-issued same write replays (no re-exec) ──────

#[test]
fn reconciled_committed_then_replays() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        make_unknown_receipt(&receipts, &substrate, "k4", "ord-4", json!({"total": 7})).await;
        substrate.write_fact(fact("orders", "ord-4", json!({"total": 7}))).await.unwrap();
        let r = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "k4").await.unwrap();
        assert_eq!(r, ReconcileResult::ResolvedCommitted);

        // re-issue the SAME write with a fresh executor → must replay committed, NOT re-execute
        let fresh = Arc::new(TBackendWriteExecutor::new(CAP, substrate.clone(), clock()));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(fresh.clone());
        let out = run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &write_req("k4", "orders", "ord-4", json!({"total": 7})), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(fresh.write_count(), 0, "a reconciled-committed write is replayed, never re-executed");
    });
}

// ── reconcile is idempotent: a second pass is a no-op on the now-terminal receipt ─

#[test]
fn reconcile_twice_is_idempotent() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());

        make_unknown_receipt(&receipts, &substrate, "k5", "ord-5", json!({"total": 2})).await;
        let first = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "k5").await.unwrap();
        assert_eq!(first, ReconcileResult::ResolvedPermanentFailure);
        let second = reconcile_unknown_write(&receipts, &substrate, &clock(), CAP, "k5").await.unwrap();
        assert_eq!(second, ReconcileResult::NotApplicable(WriteState::PermanentFailure));
    });
}
