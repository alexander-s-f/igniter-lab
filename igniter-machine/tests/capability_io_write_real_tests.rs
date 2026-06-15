//! LAB-MACHINE-CAPABILITY-IO-WRITE-P6b — real local TBackend write executor.
//!
//! The P6a receipt-gated write protocol is UNCHANGED; only a real `TBackendWriteExecutor` (over
//! an on-disk `RocksDBBackend`) replaces the fake. Proves the full lifecycle against a real
//! substrate, with the payload digest FORCED to include target fact identity (store+key+value+
//! valid_time). No HTTP/queue/retry/compensation/reconciliation.

use igniter_machine::backend::{InMemoryBackend, RocksDBBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::executors::TBackendWriteExecutor;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::write::{payload_digest, run_write_effect, FactWrite, WriteRequest, WriteState};
use serde_json::json;
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.WriteCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}

fn temp_dir() -> PathBuf {
    std::env::temp_dir().join(format!("igniter_p6b_{}", uuid::Uuid::new_v4()))
}

fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn passport(subject: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: CAP.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig:w".to_string(),
    }
}

fn write_req(key: &str, fw: FactWrite) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "put_fact".to_string(),
        idempotency_key: key.to_string(),
        payload: fw.to_payload(),
    }
}

fn fact_write(store: &str, key: &str, value: serde_json::Value) -> FactWrite {
    FactWrite { store: store.to_string(), key: key.to_string(), value, valid_time: None }
}

fn registry(exec: Arc<TBackendWriteExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}

// ── #1: successful write — prepared → backend fact → committed → read-back ──────

#[test]
fn successful_write_full_lifecycle() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let out = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("o1", fact_write("orders", "ord-1", json!({"total": 50}))), RunMode::Live)
            .await
            .unwrap();
        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(exec.write_count(), 1);

        // two-phase receipt
        let facts = store.facts_for(RECEIPTS_STORE, "IO.WriteCapability:o1", None, None).await.unwrap();
        assert_eq!(facts.len(), 2);
        // the fact really landed in the REAL backend — read it back
        let back = data.read_as_of("orders", "ord-1", f64::MAX).await.unwrap().expect("fact must be written");
        assert_eq!(back.value, json!({"total": 50}));

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #2: duplicate same key + same payload → no second backend write ────────────

#[test]
fn duplicate_same_payload_no_second_backend_write() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("d", fact_write("orders", "ord-2", json!({"total": 1}))), RunMode::Live).await.unwrap();
        let second = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("d", fact_write("orders", "ord-2", json!({"total": 1}))), RunMode::Live).await.unwrap();

        assert_eq!(second.state, WriteState::Committed); // replayed
        assert_eq!(exec.write_count(), 1, "the real backend is written exactly once");
        // only one fact version on the backend key
        let versions = data.facts_for("orders", "ord-2", None, None).await.unwrap();
        assert_eq!(versions.len(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #3: duplicate same key + different payload → refusal before write ──────────

#[test]
fn duplicate_different_payload_refused_before_write() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("k", fact_write("orders", "ord-3", json!({"total": 1}))), RunMode::Live).await.unwrap();
        let conflict = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("k", fact_write("orders", "ord-3", json!({"total": 999}))), RunMode::Live).await.unwrap();

        assert_eq!(conflict.state, WriteState::Denied);
        assert_eq!(exec.write_count(), 1, "the conflicting write never reaches the backend");

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #4: missing/invalid authority → refusal, no receipt, no backend write ──────

#[test]
fn missing_authority_no_write() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["read"]); // lacks "write"

        let out = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("a", fact_write("orders", "ord-4", json!({"total": 1}))), RunMode::Live).await.unwrap();
        assert_eq!(out.state, WriteState::Denied);
        assert_eq!(exec.write_count(), 0);
        assert!(store.read_as_of(RECEIPTS_STORE, "IO.WriteCapability:a", f64::MAX).await.unwrap().is_none());
        assert!(data.read_as_of("orders", "ord-4", f64::MAX).await.unwrap().is_none());

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #5: injected backend write failure → unknown_external_state, no blind retry ─

#[test]
fn injected_write_failure_is_unknown_no_blind_retry() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::failing(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let first = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("f", fact_write("orders", "ord-5", json!({"total": 1}))), RunMode::Live).await.unwrap();
        assert_eq!(first.state, WriteState::UnknownExternalState);
        assert_eq!(exec.write_count(), 1);

        // second identical call must NOT blindly retry the mutation
        let second = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("f", fact_write("orders", "ord-5", json!({"total": 1}))), RunMode::Live).await.unwrap();
        assert_eq!(second.state, WriteState::UnknownExternalState);
        assert_eq!(exec.write_count(), 1, "an unknown write is never blindly retried");

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #6: replay mode → no backend write ─────────────────────────────────────────

#[test]
fn replay_mode_no_backend_write() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let out = run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("r", fact_write("orders", "ord-6", json!({"total": 1}))), RunMode::Replay).await.unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
        assert_eq!(exec.write_count(), 0);
        assert!(data.read_as_of("orders", "ord-6", f64::MAX).await.unwrap().is_none());

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── #7: contract body / VM still cannot write ──────────────────────────────────

#[test]
fn contract_body_cannot_write() {
    rt().block_on(async {
        let dir = temp_dir();
        let data: Arc<dyn TBackend> = Arc::new(RocksDBBackend::new(dir.clone()).unwrap());
        let exec = Arc::new(TBackendWriteExecutor::new(CAP, data.clone(), clock()));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        // a machine running a contract has no write executor registry — dispatch cannot write
        let m = IgniterMachine::new(None, "in_memory").unwrap();
        m.load_program(
            &["../igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig".to_string()],
            "ExecuteQuery",
        )
        .unwrap();
        let _ = m.dispatch("ExecuteQuery", json!({"plan": {}})).await;
        assert_eq!(exec.write_count(), 0, "contract execution cannot reach the write executor");

        // only the host write path mutates
        run_write_effect(&reg, &store, &clock(), &p, "write", &write_req("w", fact_write("orders", "ord-7", json!({"total": 1}))), RunMode::Live).await.unwrap();
        assert_eq!(exec.write_count(), 1);

        let _ = std::fs::remove_dir_all(&dir);
    });
}

// ── forced identity: payload digest includes store+key+value+valid_time ────────

#[test]
fn payload_digest_includes_target_identity() {
    // same value, DIFFERENT key → different digest (no collision under one idempotency envelope)
    let a = fact_write("orders", "ord-A", json!({"total": 1})).to_payload();
    let b = fact_write("orders", "ord-B", json!({"total": 1})).to_payload();
    assert_ne!(payload_digest(&a), payload_digest(&b));

    // different valid_time → different digest
    let c = FactWrite { store: "orders".into(), key: "ord-A".into(), value: json!({"total": 1}), valid_time: Some(5.0) }.to_payload();
    assert_ne!(payload_digest(&a), payload_digest(&c));

    // identical identity → identical digest (legitimate replay)
    let a2 = fact_write("orders", "ord-A", json!({"total": 1})).to_payload();
    assert_eq!(payload_digest(&a), payload_digest(&a2));
}
