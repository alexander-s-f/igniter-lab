//! LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9 — durable, auditable retry over time.
//!
//! Retry intents are TBackend facts with a `due_at`; an explicit `drain_due_retries(now)` runs
//! the next attempt under the same reconcile-gated rules as P8. No background worker, no HTTP.

use igniter_machine::backend::{InMemoryBackend, RemoteTcpBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::retry_queue::{
    drain_due_retries, enqueue_retry, DrainAction, RETRY_QUEUE_STORE,
};
use igniter_machine::write::{FactWrite, FakeWriteExecutor, WriteBehavior, WriteRequest};
use serde_json::json;
use std::sync::Arc;

const CAP: &str = "IO.WriteCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock(t: f64) -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(t))
}
fn passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "svc".to_string(),
        capability_id: CAP.to_string(),
        scopes: vec!["write".to_string()],
        issued_at: 0.0,
        expires_at: Some(1_000_000_000.0),
        revoked: false,
        evidence_digest: "sig:w".to_string(),
    }
}
fn base_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "put_fact".to_string(),
        idempotency_key: key.to_string(),
        payload: FactWrite { store: "orders".to_string(), key: format!("rec-{key}"), value: json!({"v": 1}), valid_time: None }.to_payload(),
    }
}
fn registry(exec: Arc<FakeWriteExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}
async fn intent_state(receipts: &Arc<dyn TBackend>, key: &str) -> String {
    receipts
        .read_as_of(RETRY_QUEUE_STORE, key, f64::MAX)
        .await
        .unwrap()
        .unwrap()
        .value["state"]
        .as_str()
        .unwrap()
        .to_string()
}

// ── #1: a retryable outcome produces a retry-intent fact with due_at ───────────

#[test]
fn enqueue_creates_intent_fact_with_due_at() {
    rt().block_on(async {
        let store = receipts();
        let auth = passport().authority_digest();
        enqueue_retry(&store, &clock(150.0), &base_req("w1"), "write", &auth, 3, 10.0).await.unwrap();

        let f = store.read_as_of(RETRY_QUEUE_STORE, "w1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(f.value["state"], json!("pending"));
        assert_eq!(f.value["due_at"], json!(160.0)); // 150 + 10 * 2^0
        assert_eq!(f.value["attempt"], json!(0));
    });
}

// ── #2: draining before due does nothing ───────────────────────────────────────

#[test]
fn drain_before_due_does_nothing() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(150.0), &base_req("w2"), "write", &passport().authority_digest(), 3, 10.0).await.unwrap();

        let reports = drain_due_retries(&reg, &store, &substrate, &clock(155.0), &passport(), 10.0).await.unwrap();
        assert!(reports.is_empty(), "due_at=160, now=155 → not due");
        assert_eq!(exec.attempts(), 0);
        assert_eq!(intent_state(&store, "w2").await, "pending");
    });
}

// ── #3: draining at/after due runs the next attempt; commit → done ─────────────

#[test]
fn drain_at_due_runs_and_commits() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(150.0), &base_req("w3"), "write", &passport().authority_digest(), 3, 10.0).await.unwrap();

        let reports = drain_due_retries(&reg, &store, &substrate, &clock(165.0), &passport(), 10.0).await.unwrap();
        assert_eq!(reports.len(), 1);
        assert_eq!(reports[0].action, DrainAction::Committed);
        assert_eq!(exec.attempts(), 1);
        assert_eq!(intent_state(&store, "w3").await, "done");
    });
}

// ── #4: an unknown outcome is reconciled before scheduling a retry ─────────────

#[test]
fn unknown_is_reconciled_then_rescheduled() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts(); // empty → reconcile says "did not land"
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(100.0), &base_req("w4"), "write", &passport().authority_digest(), 3, 0.0).await.unwrap();

        let reports = drain_due_retries(&reg, &store, &substrate, &clock(200.0), &passport(), 0.0).await.unwrap();
        assert_eq!(reports.len(), 1);
        assert!(matches!(reports[0].action, DrainAction::Rescheduled(_)));
        assert_eq!(exec.attempts(), 1);
        // the intent advanced to attempt 1 and is pending again (reconcile said not-landed)
        let f = store.read_as_of(RETRY_QUEUE_STORE, "w4", f64::MAX).await.unwrap().unwrap();
        assert_eq!(f.value["state"], json!("pending"));
        assert_eq!(f.value["attempt"], json!(1));
    });
}

#[test]
fn unknown_unreconcilable_is_blocked() {
    rt().block_on(async {
        let store = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let reg = registry(exec.clone());
        let dead: Arc<dyn TBackend> = Arc::new(RemoteTcpBackend::new("127.0.0.1:1".to_string()));
        enqueue_retry(&store, &clock(100.0), &base_req("w4b"), "write", &passport().authority_digest(), 3, 0.0).await.unwrap();

        let reports = drain_due_retries(&reg, &store, &dead, &clock(200.0), &passport(), 0.0).await.unwrap();
        assert_eq!(reports[0].action, DrainAction::Blocked);
        assert_eq!(intent_state(&store, "w4b").await, "blocked");
    });
}

// ── #5: a committed terminal is final; a second drain is a no-op ───────────────

#[test]
fn committed_terminal_is_not_redrained() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(100.0), &base_req("w5"), "write", &passport().authority_digest(), 3, 0.0).await.unwrap();

        drain_due_retries(&reg, &store, &substrate, &clock(100.0), &passport(), 0.0).await.unwrap();
        assert_eq!(intent_state(&store, "w5").await, "done");
        let again = drain_due_retries(&reg, &store, &substrate, &clock(100.0), &passport(), 0.0).await.unwrap();
        assert!(again.is_empty(), "a done intent is not re-drained");
        assert_eq!(exec.attempts(), 1);
    });
}

// ── #6: max attempts → exhausted terminal ──────────────────────────────────────

#[test]
fn max_attempts_exhausts() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Retryable));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(1000.0), &base_req("w6"), "write", &passport().authority_digest(), 2, 0.0).await.unwrap();

        let r1 = drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();
        assert!(matches!(r1[0].action, DrainAction::Rescheduled(_)));
        let r2 = drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();
        assert!(matches!(r2[0].action, DrainAction::Rescheduled(_)));
        let r3 = drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();
        assert_eq!(r3[0].action, DrainAction::Exhausted);

        assert_eq!(exec.attempts(), 2, "exactly max_attempts write attempts");
        assert_eq!(intent_state(&store, "w6").await, "exhausted");
    });
}

// ── #7: every scheduler operation is an auditable fact ─────────────────────────

#[test]
fn all_operations_are_auditable_facts() {
    rt().block_on(async {
        let store = receipts();
        let substrate = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Retryable));
        let reg = registry(exec.clone());
        enqueue_retry(&store, &clock(1000.0), &base_req("w7"), "write", &passport().authority_digest(), 2, 0.0).await.unwrap();
        drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();
        drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();
        drain_due_retries(&reg, &store, &substrate, &clock(1000.0), &passport(), 0.0).await.unwrap();

        // full history at the intent's key: enqueue + 2 reschedules + exhausted
        let history = store.facts_for(RETRY_QUEUE_STORE, "w7", None, None).await.unwrap();
        assert_eq!(history.len(), 4, "every transition is a recorded fact");
        let states: Vec<&str> = history.iter().map(|f| f.value["state"].as_str().unwrap()).collect();
        assert!(states.contains(&"pending"));
        assert!(states.contains(&"exhausted"));
    });
}
