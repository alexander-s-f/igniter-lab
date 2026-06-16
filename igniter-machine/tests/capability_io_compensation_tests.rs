//! LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12 — reverse a committed effect (`aborted`).
//!
//! Compensation reverses a SUCCEEDED effect (distinct from retry/reconcile). A committed receipt
//! → compensation → `aborted` (terminal update; the committed fact is preserved). Irreversible
//! effects refuse; an unknown compensation does not abort; replay never compensates twice.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::compensation::{
    run_compensation, CompensationBehavior, CompensationResult, FakeCompensatableExecutor,
};
use igniter_machine::write::{run_write_effect, FactWrite, FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.WriteCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn passport(subject: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn write_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.into(),
        operation: "put".into(),
        idempotency_key: key.into(),
        payload: FactWrite { store: "orders".into(), key: format!("rec-{key}"), value: json!({"v": 1}), valid_time: None }.to_payload(),
    }
}

/// Commit a write so there is a `committed` receipt to compensate.
async fn commit(receipts: &Arc<dyn TBackend>, key: &str) {
    let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    let out = run_write_effect(&reg, receipts, &clock(), &passport("svc"), "write", &write_req(key), RunMode::Live).await.unwrap();
    assert_eq!(out.state, WriteState::Committed);
}
async fn state_of(receipts: &Arc<dyn TBackend>, key: &str) -> String {
    receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:{key}"), f64::MAX).await.unwrap().unwrap().value["state"].as_str().unwrap().to_string()
}

// ── committed effect → compensation → aborted ──────────────────────────────────

#[test]
fn committed_effect_compensated_to_aborted() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k1").await;
        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Reverse);

        let r = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k1", "comp-1").await.unwrap();
        assert_eq!(r, CompensationResult::Aborted);
        assert_eq!(comp.calls(), 1);
        assert_eq!(state_of(&receipts, "k1").await, "aborted");

        // original committed fact is preserved (auditable history)
        let history = receipts.facts_for(RECEIPTS_STORE, &format!("{CAP}:k1"), None, None).await.unwrap();
        let states: Vec<&str> = history.iter().map(|f| f.value["state"].as_str().unwrap()).collect();
        assert!(states.contains(&"committed"));
        assert!(states.contains(&"aborted"));
        let aborted = receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:k1"), f64::MAX).await.unwrap().unwrap();
        assert_eq!(aborted.value["compensation_correlation_id"], json!("comp-1"));
    });
}

// ── compensation unknown → original stays committed ────────────────────────────

#[test]
fn compensation_unknown_keeps_committed() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k2").await;
        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Timeout);

        let r = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k2", "comp-2").await.unwrap();
        assert_eq!(r, CompensationResult::Unknown);
        assert_eq!(state_of(&receipts, "k2").await, "committed", "unknown reversal must not abort");
    });
}

// ── compensation refused/failed → original stays committed ─────────────────────

#[test]
fn compensation_failure_keeps_committed() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k3").await;
        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Deny);

        let r = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k3", "comp-3").await.unwrap();
        assert_eq!(r, CompensationResult::Failed);
        assert_eq!(state_of(&receipts, "k3").await, "committed");
    });
}

// ── irreversible effect refuses compensation (compensator never run) ───────────

#[test]
fn irreversible_effect_refuses_compensation() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k4").await;
        let comp = FakeCompensatableExecutor::irreversible(CAP);

        let r = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k4", "comp-4").await.unwrap();
        assert_eq!(r, CompensationResult::NotCompensatable);
        assert_eq!(comp.calls(), 0, "an irreversible effect's compensator must not run");
        assert_eq!(state_of(&receipts, "k4").await, "committed");
    });
}

// ── replay compensation does not run twice ─────────────────────────────────────

#[test]
fn replay_compensation_does_not_run_twice() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k5").await;
        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Reverse);

        let first = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k5", "comp-5").await.unwrap();
        let second = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k5", "comp-5").await.unwrap();
        assert_eq!(first, CompensationResult::Aborted);
        assert_eq!(second, CompensationResult::AlreadyAborted);
        assert_eq!(comp.calls(), 1, "compensation runs exactly once");
    });
}

// ── you can only compensate a committed effect ─────────────────────────────────

#[test]
fn non_committed_is_not_compensated() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // an unknown write (Timeout) — not committed
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        run_write_effect(&reg, &receipts, &clock(), &passport("svc"), "write", &write_req("k6"), RunMode::Live).await.unwrap();

        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Reverse);
        let r = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "k6", "comp-6").await.unwrap();
        assert_eq!(r, CompensationResult::NotCommitted(WriteState::UnknownExternalState));
        assert_eq!(comp.calls(), 0);

        // no receipt at all → NoReceipt
        let none = run_compensation(&receipts, &clock(), &passport("svc"), &comp, CAP, "absent", "c").await.unwrap();
        assert_eq!(none, CompensationResult::NoReceipt);
    });
}

// ── only the original authority may compensate ─────────────────────────────────

#[test]
fn authority_mismatch_refused() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        commit(&receipts, "k7").await; // committed under passport("svc")
        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Reverse);

        // a DIFFERENT authority tries to compensate
        let r = run_compensation(&receipts, &clock(), &passport("other"), &comp, CAP, "k7", "comp-7").await.unwrap();
        assert_eq!(r, CompensationResult::AuthorityMismatch);
        assert_eq!(comp.calls(), 0);
        assert_eq!(state_of(&receipts, "k7").await, "committed");
    });
}
