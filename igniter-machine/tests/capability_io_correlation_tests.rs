//! LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13 — reconcile an unknown by correlation id.
//!
//! Precise per-request reconciliation: look up the fate of an unknown effect by its
//! `correlation_id` (first-class since P11), avoiding P7's same-value caveat. Read-only — never
//! re-issues the original effect. Fake resolver only; no external network.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode, RECEIPTS_STORE};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::compensation::{run_compensation, CompensationBehavior, CompensationResult, FakeCompensatableExecutor};
use igniter_machine::correlation::{
    reconcile_unknown_by_correlation, CorrelationReconcileResult, MapCorrelationResolver,
};
use igniter_machine::write::{run_write_effect, FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState};
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
        subject: "svc".into(),
        capability_id: CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn req(key: &str, value: serde_json::Value, correlation: Option<&str>) -> WriteRequest {
    let mut payload = json!({ "store": "orders", "key": format!("rec-{key}"), "value": value });
    if let Some(c) = correlation {
        payload["correlation_id"] = json!(c);
    }
    WriteRequest { capability_id: CAP.into(), operation: "put".into(), idempotency_key: key.into(), payload }
}

/// Create an `unknown` write receipt (Timeout executor) carrying a correlation id.
async fn make_unknown(receipts: &Arc<dyn TBackend>, exec: &Arc<FakeWriteExecutor>, key: &str, value: serde_json::Value, corr: Option<&str>) {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec.clone());
    let out = run_write_effect(&reg, receipts, &clock(), &passport(), "write", &req(key, value, corr), RunMode::Live).await.unwrap();
    assert_eq!(out.state, WriteState::UnknownExternalState);
}
async fn state_of(receipts: &Arc<dyn TBackend>, key: &str) -> String {
    receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:{key}"), f64::MAX).await.unwrap().unwrap().value["state"].as_str().unwrap().to_string()
}

// ── #1/#4: landed-by-correlation → committed; not-found → permanent_failure ─────

#[test]
fn unknown_reconciled_committed_by_correlation() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        make_unknown(&receipts, &exec, "k1", json!({"v": 1}), Some("corr-A")).await;
        let resolver = MapCorrelationResolver::new(&["corr-A"]);

        let r = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "k1").await.unwrap();
        assert_eq!(r, CorrelationReconcileResult::ResolvedCommitted);
        assert_eq!(state_of(&receipts, "k1").await, "committed");
        let rec = receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:k1"), f64::MAX).await.unwrap().unwrap();
        assert_eq!(rec.value["reconciled_by"], json!("correlation_id"));
    });
}

#[test]
fn not_found_by_correlation_is_permanent_failure() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        make_unknown(&receipts, &exec, "k4", json!({"v": 1}), Some("corr-missing")).await;
        let resolver = MapCorrelationResolver::new(&["corr-other"]);

        let r = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "k4").await.unwrap();
        assert_eq!(r, CorrelationReconcileResult::ResolvedPermanentFailure);
        assert_eq!(state_of(&receipts, "k4").await, "permanent_failure");
    });
}

// ── #2: same value, different correlation → no false match ─────────────────────

#[test]
fn same_value_different_correlation_no_false_match() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        // IDENTICAL value, different correlation ids and different idempotency keys
        make_unknown(&receipts, &exec, "ka", json!({"v": 7}), Some("corr-A")).await;
        make_unknown(&receipts, &exec, "kb", json!({"v": 7}), Some("corr-B")).await;
        // the resolver only knows corr-A landed
        let resolver = MapCorrelationResolver::new(&["corr-A"]);

        let ra = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "ka").await.unwrap();
        let rb = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "kb").await.unwrap();
        assert_eq!(ra, CorrelationReconcileResult::ResolvedCommitted);
        // identical value must NOT make kb falsely match A
        assert_eq!(rb, CorrelationReconcileResult::ResolvedPermanentFailure);
    });
}

// ── #3: missing correlation → explicit fallback signal ─────────────────────────

#[test]
fn missing_correlation_returns_missing() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        make_unknown(&receipts, &exec, "k3", json!({"v": 1}), None).await; // no correlation id
        let resolver = MapCorrelationResolver::new(&["corr-A"]);

        let r = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "k3").await.unwrap();
        assert_eq!(r, CorrelationReconcileResult::MissingCorrelation);
        assert_eq!(state_of(&receipts, "k3").await, "unknown_external_state", "no premature resolution");
    });
}

// ── #6: lookup unavailable stays unknown ───────────────────────────────────────

#[test]
fn lookup_unavailable_stays_unknown() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        make_unknown(&receipts, &exec, "k6", json!({"v": 1}), Some("corr-A")).await;
        let resolver = MapCorrelationResolver::unavailable();

        let r = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "k6").await.unwrap();
        assert_eq!(r, CorrelationReconcileResult::StillUnknown);
        assert_eq!(state_of(&receipts, "k6").await, "unknown_external_state");
    });
}

// ── #7: reconciliation never re-sends the original effect ──────────────────────

#[test]
fn reconciliation_never_resends() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        make_unknown(&receipts, &exec, "k7", json!({"v": 1}), Some("corr-A")).await;
        assert_eq!(exec.attempts(), 1);
        let resolver = MapCorrelationResolver::new(&["corr-A"]);

        reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "k7").await.unwrap();
        // the resolver is read-only — the original write executor was never invoked again
        assert_eq!(exec.attempts(), 1, "reconcile must never re-send the effect");
    });
}

// ── not-applicable / no-receipt guards ─────────────────────────────────────────

#[test]
fn committed_is_not_applicable_and_absent_is_no_receipt() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &req("kc", json!({"v": 1}), Some("corr-A")), RunMode::Live).await.unwrap();
        let resolver = MapCorrelationResolver::new(&["corr-A"]);

        let applic = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "kc").await.unwrap();
        assert_eq!(applic, CorrelationReconcileResult::NotApplicable(WriteState::Committed));
        let none = reconcile_unknown_by_correlation(&receipts, &resolver, &clock(), CAP, "absent").await.unwrap();
        assert_eq!(none, CorrelationReconcileResult::NoReceipt);
    });
}

// ── #8: compensation references the original correlation id ────────────────────

#[test]
fn compensation_references_original_correlation() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        run_write_effect(&reg, &receipts, &clock(), &passport(), "write", &req("k8", json!({"v": 1}), Some("corr-orig")), RunMode::Live).await.unwrap();

        let comp = FakeCompensatableExecutor::new(CAP, CompensationBehavior::Reverse);
        let r = run_compensation(&receipts, &clock(), &passport(), &comp, CAP, "k8", "comp-corr").await.unwrap();
        assert_eq!(r, CompensationResult::Aborted);

        let rec = receipts.read_as_of(RECEIPTS_STORE, &format!("{CAP}:k8"), f64::MAX).await.unwrap().unwrap();
        assert_eq!(rec.value["correlation_id"], json!("corr-orig"), "original correlation preserved");
        assert_eq!(rec.value["compensation_correlation_id"], json!("comp-corr"));
    });
}
