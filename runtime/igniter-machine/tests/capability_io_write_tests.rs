//! LAB-MACHINE-CAPABILITY-IO-WRITE-P6a — receipt-gated write lifecycle (fake executor).
//!
//! Proves the write protocol without a real substrate: two-phase receipt (prepared →
//! committed/denied/unknown), idempotency bound to payload digest, duplicate-different-payload
//! refusal, timeout→unknown with no blind retry, and prepare-receipt-failure blocking the
//! executor. Authority + clock are the P4/P5 invariants, reused.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::errors::EngineError;
use igniter_machine::fact::Fact;
use igniter_machine::write::{
    run_write_effect, FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState,
};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.WriteCapability";

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

fn write_req(key: &str, payload: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "put".to_string(),
        idempotency_key: key.to_string(),
        payload,
    }
}

fn registry(exec: Arc<FakeWriteExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}

// ── commit lifecycle: prepared → committed (two facts, terminal wins the read) ─

#[test]
fn commit_lifecycle_writes_two_phase_receipt() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("k1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Committed);
        assert_eq!(exec.attempts(), 1);
        assert_eq!(exec.applied_count(), 1);

        // two facts on the timeline (prepared + committed); the latest read = committed
        let facts = store
            .facts_for(RECEIPTS_STORE, "IO.WriteCapability:k1", None, None)
            .await
            .unwrap();
        assert_eq!(
            facts.len(),
            2,
            "two-phase: a prepared and a committed receipt"
        );
        let latest = store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:k1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(latest.value["state"], json!("committed"));
        assert!(facts.iter().any(|f| f.value["state"] == json!("prepared")));
    });
}

// ── duplicate same key + same payload → replay, no second mutation ─────────────

#[test]
fn duplicate_same_payload_replays_no_second_write() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let a = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("dup", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        let b = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("dup", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(a.state, WriteState::Committed);
        assert_eq!(b.state, WriteState::Committed); // replayed
        assert_eq!(exec.attempts(), 1, "the mutation must run exactly once");
        assert_eq!(exec.applied_count(), 1);
    });
}

// ── duplicate same key + DIFFERENT payload → refuse before executor ────────────

#[test]
fn duplicate_different_payload_refused() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("k", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        let conflict = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("k", json!({"v": 999})),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(conflict.state, WriteState::Denied);
        assert!(conflict.detail.unwrap().contains("different payload"));
        assert_eq!(
            exec.attempts(),
            1,
            "the conflicting write must not reach the executor"
        );
        assert_eq!(exec.applied_count(), 1);
        // the original committed receipt is intact
        let latest = store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:k", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(latest.value["state"], json!("committed"));
    });
}

// ── executor denial → denied state, receipt written (denial-as-data) ───────────

#[test]
fn executor_denial_is_denied_state_with_receipt() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Deny));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("d1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Denied);
        assert_eq!(exec.attempts(), 1);
        assert_eq!(
            exec.applied_count(),
            0,
            "a denied write applies no mutation"
        );

        let latest = store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:d1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(latest.value["state"], json!("denied"));
    });
}

// ── timeout → unknown_external_state, and NO blind retry ───────────────────────

#[test]
fn timeout_is_unknown_and_not_blindly_retried() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let first = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("t1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(first.state, WriteState::UnknownExternalState);
        assert_eq!(exec.attempts(), 1);

        let latest = store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:t1", f64::MAX)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(latest.value["state"], json!("unknown_external_state"));

        // a second identical call MUST NOT blindly retry the mutation
        let second = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("t1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(second.state, WriteState::UnknownExternalState);
        assert!(second.detail.unwrap().contains("no blind retry"));
        assert_eq!(
            exec.attempts(),
            1,
            "an unknown write is never blindly retried"
        );
    });
}

// ── prepare-receipt failure blocks the executor (the gate) ─────────────────────

struct WriteFailBackend;

#[async_trait::async_trait]
impl TBackend for WriteFailBackend {
    async fn read_as_of(&self, _: &str, _: &str, _: f64) -> Result<Option<Fact>, EngineError> {
        Ok(None)
    }
    async fn write_fact(&self, _: Fact) -> Result<(), EngineError> {
        Err(EngineError::StorageError("disk full".to_string()))
    }
    async fn facts_for(
        &self,
        _: &str,
        _: &str,
        _: Option<f64>,
        _: Option<f64>,
    ) -> Result<Vec<Fact>, EngineError> {
        Ok(vec![])
    }
    async fn all_facts(&self) -> Result<Vec<Fact>, EngineError> {
        Ok(vec![])
    }
}

#[test]
fn prepare_receipt_failure_blocks_executor() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store: Arc<dyn TBackend> = Arc::new(WriteFailBackend);
        let p = passport("svc", &["write"]);

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("g1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Denied); // refused: the gate could not be written
        assert!(out.detail.unwrap().contains("prepare receipt write failed"));
        assert_eq!(
            exec.attempts(),
            0,
            "the executor must not be called if the gate cannot be written"
        );
    });
}

// ── authority refused writes no receipt; replay-different-authority refused ─────

#[test]
fn authority_refused_writes_no_receipt() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        // passport lacks the "write" scope
        let p = passport("svc", &["read"]);

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("a1", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::Denied);
        assert_eq!(exec.attempts(), 0);
        assert!(store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:a1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}

#[test]
fn replay_with_different_authority_refused() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        let a = passport("svc:A", &["write"]);
        let b = passport("svc:B", &["write"]); // different subject → different digest

        run_write_effect(
            &reg,
            &store,
            &clock(),
            &a,
            "write",
            &write_req("k", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        let mism = run_write_effect(
            &reg,
            &store,
            &clock(),
            &b,
            "write",
            &write_req("k", json!({"v": 1})),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(mism.state, WriteState::Denied);
        assert!(mism.detail.unwrap().contains("authority scope mismatch"));
        assert_eq!(exec.attempts(), 1);
    });
}

// ── replay mode without a receipt → unknown, nothing prepared ──────────────────

#[test]
fn replay_mode_without_receipt_is_unknown() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        let store = receipts();
        let p = passport("svc", &["write"]);

        let out = run_write_effect(
            &reg,
            &store,
            &clock(),
            &p,
            "write",
            &write_req("r1", json!({"v": 1})),
            RunMode::Replay,
        )
        .await
        .unwrap();
        assert_eq!(out.state, WriteState::UnknownExternalState);
        assert_eq!(exec.attempts(), 0);
        assert!(store
            .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:r1", f64::MAX)
            .await
            .unwrap()
            .is_none());
    });
}
