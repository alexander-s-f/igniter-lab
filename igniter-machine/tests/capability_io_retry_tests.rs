//! LAB-MACHINE-CAPABILITY-IO-RETRY-P8 — bounded, reconciliation-gated write retry.
//!
//! Safety invariant under test: never retry an `unknown` blindly. A retry proceeds only when
//! the prior attempt is KNOWN not to have landed (executor `retryable`, or P7 reconcile says
//! not-landed). Each attempt uses a fresh idempotency key, so at most one attempt commits.

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, RemoteTcpBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome, EffectRequest,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::fact::Fact;
use igniter_machine::retry::{run_write_with_retry, RetryOutcome, RetryPolicy};
use igniter_machine::write::{FactWrite, WriteRequest};
use serde_json::json;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
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
fn base_req(rec: &str, value: serde_json::Value) -> WriteRequest {
    WriteRequest {
        capability_id: CAP.to_string(),
        operation: "put_fact".to_string(),
        idempotency_key: "base".to_string(),
        payload: FactWrite { store: "orders".to_string(), key: rec.to_string(), value, valid_time: None }.to_payload(),
    }
}

// ── a programmable write executor: returns a scripted sequence of outcomes ──────

#[derive(Clone, Copy)]
enum Step {
    Commit,
    Deny,
    Retryable,
    Timeout,
    WriteThenUnknown,
    Permanent,
}

struct ScriptedWriteExecutor {
    backend: Arc<dyn TBackend>,
    clock: Arc<dyn ClockProvider>,
    steps: Vec<Step>,
    cursor: AtomicUsize,
    attempts: AtomicU64,
}

impl ScriptedWriteExecutor {
    fn new(backend: Arc<dyn TBackend>, clock: Arc<dyn ClockProvider>, steps: Vec<Step>) -> Self {
        Self { backend, clock, steps, cursor: AtomicUsize::new(0), attempts: AtomicU64::new(0) }
    }
    fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }
    async fn apply_write(&self, req: &EffectRequest) {
        let store = req.args.get("store").and_then(|v| v.as_str()).unwrap_or("");
        let key = req.args.get("key").and_then(|v| v.as_str()).unwrap_or("");
        let value = req.args.get("value").cloned().unwrap_or(serde_json::Value::Null);
        let fact = Fact {
            id: format!("w:{}:{}:{}", store, key, uuid::Uuid::new_v4()),
            store: store.to_string(),
            key: key.to_string(),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("scripted")),
            derivation: None,
        };
        let _ = self.backend.write_fact(fact).await;
    }
}

#[async_trait]
impl CapabilityExecutor for ScriptedWriteExecutor {
    fn capability_id(&self) -> &str {
        CAP
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        let idx = self.cursor.fetch_add(1, Ordering::SeqCst);
        let step = self.steps.get(idx).copied().unwrap_or(Step::Commit);
        match step {
            Step::Commit => {
                self.apply_write(req).await;
                EffectOutcome::succeeded(json!({ "written": true }))
            }
            Step::Deny => EffectOutcome::denied("write denied"),
            Step::Retryable => EffectOutcome::retryable("transient failure, did not mutate"),
            Step::Timeout => EffectOutcome::unknown("timeout — mutation unknown"),
            Step::WriteThenUnknown => {
                self.apply_write(req).await; // the mutation DID land
                EffectOutcome::unknown("ack lost after the write")
            }
            Step::Permanent => EffectOutcome::permanent("constraint violation"),
        }
    }
}

fn registry(exec: Arc<ScriptedWriteExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}

// ── transient retries then commits ─────────────────────────────────────────────

#[test]
fn retries_transient_then_commits() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::Retryable, Step::Retryable, Step::Commit]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-1", json!({"total": 1})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Committed { attempts: 3 });
        assert_eq!(exec.attempts(), 3);
    });
}

// ── exhausts the bound when failures persist ───────────────────────────────────

#[test]
fn exhausts_on_persistent_transient() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::Retryable, Step::Retryable]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-2", json!({"total": 1})), RetryPolicy::new(2))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Exhausted { attempts: 2 });
        assert_eq!(exec.attempts(), 2);
    });
}

// ── unknown → reconcile says not-landed → retry → commit ───────────────────────

#[test]
fn unknown_reconciled_not_landed_then_commits() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // attempt 1 times out WITHOUT writing; attempt 2 commits
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::Timeout, Step::Commit]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-3", json!({"total": 5})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Committed { attempts: 2 });
        // the value really landed exactly once
        let versions = substrate.facts_for("orders", "ord-3", None, None).await.unwrap();
        assert_eq!(versions.len(), 1);
    });
}

// ── unknown but the write actually landed → reconcile resolves committed ───────

#[test]
fn unknown_but_landed_resolves_committed_without_retry() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // the write lands but the ack is lost → unknown; reconcile must find it
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::WriteThenUnknown, Step::Commit]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-4", json!({"total": 9})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Committed { attempts: 1 });
        assert_eq!(exec.attempts(), 1, "no retry — reconcile found the write already landed");
        // exactly one version (no double write)
        let versions = substrate.facts_for("orders", "ord-4", None, None).await.unwrap();
        assert_eq!(versions.len(), 1);
    });
}

// ── unknown + unreconcilable substrate → bail (no double-write risk) ───────────

#[test]
fn unknown_unreconcilable_bails_unresolved() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let healthy: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(ScriptedWriteExecutor::new(healthy.clone(), clock(), vec![Step::Timeout]));
        let reg = registry(exec.clone());
        // reconcile against an UNAVAILABLE substrate → cannot determine → bail
        let dead: Arc<dyn TBackend> = Arc::new(RemoteTcpBackend::new("127.0.0.1:1".to_string()));

        let out = run_write_with_retry(&reg, &receipts, &dead, &clock(), &passport(), "write", &base_req("ord-5", json!({"total": 1})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Unresolved { attempts: 1 });
        assert_eq!(exec.attempts(), 1, "must NOT retry an unreconcilable unknown");
    });
}

// ── boundary refusal and hard permanent are not retried ────────────────────────

#[test]
fn denial_is_not_retried() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::Deny]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-6", json!({"total": 1})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::Denied);
        assert_eq!(exec.attempts(), 1);
    });
}

#[test]
fn hard_permanent_is_not_retried() {
    rt().block_on(async {
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let substrate: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let exec = Arc::new(ScriptedWriteExecutor::new(substrate.clone(), clock(), vec![Step::Permanent]));
        let reg = registry(exec.clone());

        let out = run_write_with_retry(&reg, &receipts, &substrate, &clock(), &passport(), "write", &base_req("ord-7", json!({"total": 1})), RetryPolicy::new(5))
            .await
            .unwrap();
        assert_eq!(out, RetryOutcome::PermanentFailure { attempts: 1 });
        assert_eq!(exec.attempts(), 1);
    });
}
