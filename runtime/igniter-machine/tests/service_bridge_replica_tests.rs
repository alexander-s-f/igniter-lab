//! LAB-MACHINE-SERVICE-BRIDGE-REPLICA-P10 — single-replica serving × one bridge effect.
//!
//! ```text
//! webhook → duplicate policy (attempt/key) → ONE replica → capsule intent
//!        → ONE declared effect (run_write_effect) → receipt → HTTP response + audit links
//! ```
//! Duplicate policy controls effect count: `dedup_strict` → one effect ever; `bounded_fresh(n)`
//! → up to n distinct-keyed effects. Fanout never performs an effect. Fake executor only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRequest, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

const CAP: &str = "IO.SparkCRM";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn passport(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    passport(
        "vendor:acme",
        "coordination",
        &[
            "create_pool",
            "import_capsule",
            "activate_capsule",
            "grant_access",
            "accept_recipe",
            "invoke",
        ],
    )
}
fn host_effect() -> CapabilityPassport {
    passport("host", CAP, &["write"])
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity {
        agent_id: id.into(),
        kind,
        label: id.into(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    })
    .await
    .unwrap();
}

async fn offer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source("contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }", "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn policy(mode: &str, max_fresh: u32) -> DuplicatePolicy {
    DuplicatePolicy {
        mode: mode.into(),
        key_header: "x-vendor-event-id".into(),
        max_fresh,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    }
}

fn recipe(digest: &str, n: u32, dp: DuplicatePolicy) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "Offer".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: n,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: Some(dp),
    }
}

/// Build a production pool `svc` (n Offer replicas) + an ingress router for it.
async fn prod(
    n: usize,
    dp: DuplicatePolicy,
) -> (CoordinationHub, Arc<dyn TBackend>, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = offer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &passport("dev", "coordination", &["accept_recipe"]),
        "svc",
        recipe(&digest, n as u32, dp),
    )
    .await
    .unwrap();
    h.grant(
        &passport("dev", "coordination", &["grant_access"]),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, audit, r)
}

fn req(key: &str, corr: &str) -> IngressRequest {
    let mut headers = HashMap::new();
    headers.insert("authorization".to_string(), "Bearer vtok".to_string());
    headers.insert("x-vendor-event-id".to_string(), key.to_string());
    headers.insert("x-correlation-id".to_string(), corr.to_string());
    IngressRequest {
        method: "POST".to_string(),
        path: "/w".to_string(),
        headers,
        body: json!({"base": 1000}),
    }
}

async fn bridge_facts(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit
        .all_facts()
        .await
        .unwrap()
        .into_iter()
        .filter(|f| f.store == COORD_AUDIT_STORE && f.value["operation"] == json!("bridge_effect"))
        .map(|f| f.value)
        .collect()
}

// 1: one request → one replica → one capsule activation → one committed effect → 200
#[test]
fn one_request_one_effect() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        let resp = r.handle_effect(&h, &req("E1", "c1"), &cfg).await;
        assert_eq!(resp.status, 200);
        assert_eq!(exec.attempts(), 1, "exactly one effect");
        assert_eq!(exec.applied_count(), 1);
    });
}

// 5 (dedup): dedup_strict repeat does NOT perform a second effect
#[test]
fn dedup_strict_no_second_effect() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        let a = r.handle_effect(&h, &req("E1", "c1"), &cfg).await;
        let b = r.handle_effect(&h, &req("E1", "c2"), &cfg).await; // same key+payload → replay
        assert_eq!(a.status, 200);
        assert_eq!(b.status, 200);
        assert_eq!(exec.attempts(), 1, "the repeat replays, NO second effect");
    });
}

// 6: bounded_fresh(6) makes distinct effect keys/payloads per attempt
#[test]
fn bounded_fresh_distinct_effects() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, policy("bounded_fresh", 6)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        for i in 0..3 {
            r.handle_effect(&h, &req("E1", &format!("c{}", i)), &cfg)
                .await;
        }
        // three fresh attempts → three distinct effect idempotency keys → three committed effects
        assert_eq!(
            exec.applied_count(),
            3,
            "each fresh attempt is a distinct effect"
        );
        assert!(receipts
            .read_as_of("__receipts__", "IO.SparkCRM:E1:0", f64::MAX)
            .await
            .unwrap()
            .is_some());
        assert!(receipts
            .read_as_of("__receipts__", "IO.SparkCRM:E1:2", f64::MAX)
            .await
            .unwrap()
            .is_some());
    });
}

// 7: audit links correlation_id, attempt_index, replica_index, effect_receipt_id
#[test]
fn audit_links_request_attempt_replica_effect() {
    rt().block_on(async {
        let (h, audit, r) = prod(2, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        r.handle_effect(&h, &req("E1", "corr-xyz"), &cfg).await;
        let bf = &bridge_facts(&audit).await[0];
        assert_eq!(bf["correlation_id"], json!("corr-xyz"));
        assert_eq!(bf["attempt_index"], json!(0));
        assert!(bf["replica_index"].is_number());
        assert_eq!(bf["effect_receipt_id"], json!("IO.SparkCRM:E1:0"));
        assert_eq!(bf["effect_state"], json!("Committed"));
    });
}

// 9: unknown effect → 202 + correlation in the body
#[test]
fn unknown_effect_202() {
    rt().block_on(async {
        let (h, _a, r) = prod(2, policy("dedup_strict", 0)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Timeout));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        let resp = r.handle_effect(&h, &req("E1", "c1"), &cfg).await;
        assert_eq!(resp.status, 202);
        assert_eq!(resp.body["correlation_id"], json!("c1"));
    });
}

// 8: fanout is never on the bridge hot path
#[test]
fn fanout_never_on_bridge_path() {
    rt().block_on(async {
        let (h, audit, r) = prod(3, policy("bounded_fresh", 6)).await;
        let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec.clone());
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let eclock = clock();
        let ep = host_effect();
        let sf = SingleFlight::new();
        let cfg = EffectBridgeConfig {
            registry: &registry,
            receipts: &receipts,
            effect_clock: &eclock,
            effect_passport: &ep,
            single_flight: &sf,
            capability_id: CAP.into(),
            operation: "create_lead".into(),
            scope: "write".into(),
        };

        r.handle_effect(&h, &req("E1", "c1"), &cfg).await;
        let all = audit.all_facts().await.unwrap();
        assert!(all
            .iter()
            .all(|f| f.value["operation"] != json!("invoke_fanout")));
        assert_eq!(
            bridge_facts(&audit).await.len(),
            1,
            "exactly one bridge effect"
        );
    });
}
