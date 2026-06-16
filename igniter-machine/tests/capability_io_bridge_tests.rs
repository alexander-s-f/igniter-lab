//! LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16 — coordination serving line ↔ capability-IO effect.
//!
//! End-to-end integration of the two completed lines: a vendor webhook activates a served
//! capsule (coordination: passport → production pool → resume+dispatch), and the capsule's output
//! is performed as a declared effect through the capability-IO substrate (receipt + idempotency +
//! correlation + outcome taxonomy). No live external network — fake effect executor.

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::bridge_effect::ServiceEffectBridge;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EchoCapabilityExecutor,
    EffectOutcome, EffectRequest, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRight, PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::IngressRequest;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteState};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

const EFFECT_CAP: &str = "IO.RecordCapability";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

// ── coordination side (copied setup pattern from the recipe/BRIDGE tests) ──────

const SCOPES: &[&str] = &["create_pool", "import_capsule", "grant_access", "accept_recipe", "invoke"];

fn coord_passport(subject: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.into(),
        capability_id: "coordination".into(),
        scopes: SCOPES.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}
async fn add_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }";
    m.load_contract_source(src, "Add").unwrap();
    m.checkpoint_bytes().await.unwrap()
}
fn recipe(digest: &str) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "Add".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: 1,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: None,
    }
}
/// Register alice/dev/vendor, build & sign a production `svc` pool serving the Add capsule, grant
/// the vendor activation. Also registers `mallory` (NOT granted).
async fn served_hub() -> CoordinationHub {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    register(&mut h, "mallory", AgentKind::RuntimeActor).await;
    h.create_pool(&coord_passport("alice"), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = add_capsule_bytes().await;
    let cref = h.add_capsule(&coord_passport("alice"), "svc", bytes, vec![]).await.unwrap();
    h.accept_recipe(&coord_passport("dev"), "svc", recipe(&cref.capsule_id)).await.unwrap();
    h.grant(&coord_passport("dev"), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
    h
}

// ── effect side ────────────────────────────────────────────────────────────────

fn effect_passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "host".into(),
        capability_id: EFFECT_CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "host-sig".into(),
    }
}
fn webhook(corr: &str, idem: Option<&str>, body: Value) -> IngressRequest {
    let mut headers = HashMap::new();
    headers.insert("x-correlation-id".into(), corr.into());
    if let Some(k) = idem {
        headers.insert("idempotency-key".into(), k.into());
    }
    IngressRequest { method: "POST".into(), path: "/svc".into(), headers, body }
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

// ── #1: webhook → capsule activation → effect (data flows end-to-end) ──────────

#[test]
fn webhook_activates_capsule_and_performs_effect() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP)); // echoes the payload back
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge {
            registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf,
            capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into(),
        };

        let out = bridge.serve(&hub, &coord_passport("vendor:acme"), "svc", &webhook("corr-1", Some("idem-1"), json!({"a": 20, "b": 22}))).await;
        assert_eq!(out.status, 200);
        assert_eq!(out.write_state, Some(WriteState::Committed));
        assert_eq!(echo.call_count(), 1);

        // the CAPSULE output (Add 20+22 = 42, a scalar) reached the EFFECT payload, with correlation
        assert_eq!(out.body["result"]["intent"], json!(42));
        assert_eq!(out.body["result"]["correlation_id"], json!("corr-1"));

        // and a receipt exists carrying the correlation
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.RecordCapability:idem-1", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["state"], json!("committed"));
        assert_eq!(r.value["correlation_id"], json!("corr-1"));
    });
}

// ── #2: replay (same webhook idempotency key) performs the effect once ─────────

#[test]
fn replay_webhook_performs_effect_once() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge { registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf, capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into() };

        let wh = webhook("corr-2", Some("idem-2"), json!({"a": 1, "b": 2}));
        let a = bridge.serve(&hub, &coord_passport("vendor:acme"), "svc", &wh).await;
        let b = bridge.serve(&hub, &coord_passport("vendor:acme"), "svc", &wh).await;
        assert_eq!(a.status, 200);
        assert_eq!(b.status, 200);
        assert_eq!(echo.call_count(), 1, "the effect runs once despite the capsule re-activating");
    });
}

// ── #3: a webhook without an idempotency key fails closed (no effect) ──────────

#[test]
fn missing_idempotency_key_fails_closed() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge { registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf, capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into() };

        let out = bridge.serve(&hub, &coord_passport("vendor:acme"), "svc", &webhook("corr-3", None, json!({"a": 1, "b": 1}))).await;
        assert_eq!(out.status, 400);
        assert_eq!(out.write_state, None);
        assert_eq!(echo.call_count(), 0, "no effect without an idempotency key");
    });
}

// ── #4: an unknown effect maps to 202 accepted-unknown (resolve later) ─────────

#[test]
fn unknown_effect_is_accepted_unknown() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let exec = Arc::new(FakeWriteExecutor::new(EFFECT_CAP, WriteBehavior::Timeout));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec);
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge { registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf, capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into() };

        let out = bridge.serve(&hub, &coord_passport("vendor:acme"), "svc", &webhook("corr-4", Some("idem-4"), json!({"a": 5, "b": 5}))).await;
        assert_eq!(out.status, 202);
        assert_eq!(out.write_state, Some(WriteState::UnknownExternalState));
        let r = receipts.read_as_of(RECEIPTS_STORE, "IO.RecordCapability:idem-4", f64::MAX).await.unwrap().unwrap();
        assert_eq!(r.value["state"], json!("unknown_external_state"));
    });
}

// ── #5: serving refusal (un-granted vendor) → no effect ────────────────────────

#[test]
fn serving_refusal_performs_no_effect() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(echo.clone());
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge { registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf, capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into() };

        // mallory is registered but NOT granted ActivateCapsule on the pool
        let out = bridge.serve(&hub, &coord_passport("mallory"), "svc", &webhook("corr-5", Some("idem-5"), json!({"a": 1, "b": 1}))).await;
        assert_eq!(out.status, 403, "serving refusal → 403, before any effect");
        assert_eq!(out.write_state, None);
        assert_eq!(echo.call_count(), 0);
    });
}

// ── P18: concurrent webhooks with the same idempotency key → effect ONCE ───────

use std::sync::atomic::{AtomicU64, Ordering};

/// An effect executor that yields mid-flight (so concurrent calls genuinely overlap) and counts
/// invocations — to prove the bridge's per-key atomic gate serializes same-key webhooks.
struct SlowEcho {
    cap: String,
    calls: AtomicU64,
}
#[async_trait]
impl CapabilityExecutor for SlowEcho {
    fn capability_id(&self) -> &str {
        &self.cap
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        self.calls.fetch_add(1, Ordering::SeqCst);
        for _ in 0..8 {
            tokio::task::yield_now().await;
        }
        EffectOutcome::succeeded(req.args.clone())
    }
}

#[test]
fn concurrent_same_webhook_performs_effect_once() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let exec = Arc::new(SlowEcho { cap: EFFECT_CAP.into(), calls: AtomicU64::new(0) });
        let mut reg = CapabilityExecutorRegistry::new();
        reg.register(exec.clone());
        let ep = effect_passport();
        let sf = SingleFlight::new();
        let bridge = ServiceEffectBridge { registry: &reg, receipts: &receipts, clock: &clock(), effect_passport: &ep, single_flight: &sf, capability_id: EFFECT_CAP.into(), operation: "record".into(), scope: "write".into() };

        // two concurrent webhooks carrying the SAME idempotency key
        let wh = webhook("corr-cc", Some("idem-cc"), json!({"a": 3, "b": 4}));
        let vendor = coord_passport("vendor:acme");
        let f1 = bridge.serve(&hub, &vendor, "svc", &wh);
        let f2 = bridge.serve(&hub, &vendor, "svc", &wh);
        let (a, b) = tokio::join!(f1, f2);

        assert_eq!(a.status, 200);
        assert_eq!(b.status, 200);
        assert_eq!(exec.calls.load(Ordering::SeqCst), 1, "the effect runs once for two concurrent same-key webhooks");
    });
}
