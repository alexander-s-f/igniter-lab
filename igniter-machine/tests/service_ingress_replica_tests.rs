//! LAB-MACHINE-SERVICE-INGRESS-REPLICA-P9 — wire replica selection into the ingress hot path.
//!
//! ```text
//! webhook → duplicate policy decides attempt/key → replica strategy selects ONE replica
//!        → capsule activation → response + audit(selected_replica)
//! ```
//! Single-replica hot path (NOT fanout: that stays a separate diagnostic API, so scaling compute
//! never multiplies downstream effects). Deterministic selection (hash-by-key / round-robin),
//! audited (replica_index, replica_count, strategy, seed_digest). Loopback / in-process only.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::ingress::{IngressRequest, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

const SCOPES: &[&str] = &["create_pool", "import_capsule", "activate_capsule", "grant_access", "accept_recipe", "invoke"];

fn passport(subject: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(), capability_id: "coordination".to_string(),
        scopes: SCOPES.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0, expires_at: Some(1_000_000.0), revoked: false, evidence_digest: "sig".to_string(),
    }
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}

async fn offer_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source("contract Offer { input base: Integer  input attempt: Integer  compute code = base + attempt  output code: Integer }", "Offer").unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn policy_fresh() -> DuplicatePolicy {
    DuplicatePolicy {
        mode: "treat_as_fresh".into(), key_header: "x-vendor-event-id".into(), max_fresh: 0,
        after_limit: "dedup_last".into(), seed_field: "attempt".into(), variant_payload: false, require_key: true,
    }
}

fn recipe(digest: &str, n: u32, dp: Option<DuplicatePolicy>) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(), capsule_digest: digest.into(), entry_contract: "Offer".into(),
        input_schema_digest: None, capability_bindings: vec![], required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(), retry_policy_ref: None, pool_sizing: n,
        created_by: "alice".into(), accepted_by: None, accepted_at: None, duplicate_policy: dp,
    }
}

/// A production pool `svc` with `n` Offer replicas + a router with the given strategy.
async fn prod(n: usize, dp: Option<DuplicatePolicy>, strategy: &str) -> (CoordinationHub, Arc<dyn TBackend>, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit.clone(), clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&passport("alice"), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = offer_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h.add_capsule(&passport("alice"), "svc", bytes.clone(), vec![]).await.unwrap().capsule_id;
    }
    h.accept_recipe(&passport("dev"), "svc", recipe(&digest, n as u32, dp)).await.unwrap();
    h.grant(&passport("dev"), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
    let mut r = IngressRouter::new();
    r.route_with_strategy("/w", "svc", strategy);
    r.token("vendortoken", passport("vendor:acme"));
    (h, audit, r)
}

fn req(key: &str, base: i64, corr: &str) -> IngressRequest {
    let mut headers = HashMap::new();
    headers.insert("authorization".to_string(), "Bearer vendortoken".to_string());
    headers.insert("x-vendor-event-id".to_string(), key.to_string());
    headers.insert("x-correlation-id".to_string(), corr.to_string());
    IngressRequest { method: "POST".to_string(), path: "/w".to_string(), headers, body: json!({"base": base}) }
}

async fn serve_facts(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit.all_facts().await.unwrap().into_iter()
        .filter(|f| f.store == COORD_AUDIT_STORE && f.value["operation"] == json!("serve"))
        .map(|f| f.value).collect()
}

// 1: hash-by-key → same vendor key stably hits the same replica
#[test]
fn hash_key_stable_replica() {
    rt().block_on(async {
        let (h, audit, r) = prod(3, Some(policy_fresh()), "hash_key").await;
        r.handle(&h, &req("E1", 1000, "c1")).await;
        r.handle(&h, &req("E1", 1000, "c2")).await; // same key, fresh re-activation
        let s = serve_facts(&audit).await;
        assert_eq!(s.len(), 2);
        assert_eq!(s[0]["replica_index"], s[1]["replica_index"], "same key → same replica");
        assert_eq!(s[0]["strategy"], json!("hash_key"));
    });
}

// 3: round-robin → deterministic cycling, auditable
#[test]
fn round_robin_cycles() {
    rt().block_on(async {
        let (h, audit, r) = prod(3, Some(policy_fresh()), "round_robin").await;
        for i in 0..3 {
            r.handle(&h, &req("E1", 1000, &format!("c{}", i))).await;
        }
        let mut idx: Vec<u64> = serve_facts(&audit).await.iter().map(|s| s["replica_index"].as_u64().unwrap()).collect();
        idx.sort();
        assert_eq!(idx, vec![0, 1, 2], "round-robin cycles through all replicas");
    });
}

// 2: attempt index participates in the seed when the route uses hash_key_attempt
#[test]
fn attempt_participates_in_seed() {
    rt().block_on(async {
        let (h, audit, r) = prod(3, Some(policy_fresh()), "hash_key_attempt").await;
        for i in 0..3 {
            r.handle(&h, &req("E1", 1000, &format!("c{}", i))).await; // same key, attempts 0,1,2
        }
        let digests: std::collections::HashSet<String> = serve_facts(&audit).await.iter()
            .map(|s| s["seed_digest"].as_str().unwrap().to_string()).collect();
        assert_eq!(digests.len(), 3, "each attempt yields a distinct seed (attempt participates)");
    });
}

// 5: audit records replica_index, replica_count, strategy, seed_digest
#[test]
fn audit_serve_has_all_fields() {
    rt().block_on(async {
        let (h, audit, r) = prod(2, Some(policy_fresh()), "hash_key").await;
        r.handle(&h, &req("E1", 1000, "c1")).await;
        let s = &serve_facts(&audit).await[0];
        assert!(s["replica_index"].is_number());
        assert_eq!(s["replica_count"], json!(2));
        assert_eq!(s["strategy"], json!("hash_key"));
        assert!(s["seed_digest"].as_str().map(|x| x.len() == 64).unwrap_or(false));
    });
}

// 6: output is unchanged relative to a direct invoke (replica selection is output-invariant)
#[test]
fn output_unchanged() {
    rt().block_on(async {
        let (h, _a, r) = prod(3, Some(policy_fresh()), "round_robin").await;
        // attempt 0 → code = base + 0 = 1000, regardless of which replica is chosen
        let resp = r.handle(&h, &req("E1", 1000, "c1")).await;
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, json!(1000));
    });
}

// 7: the hot path activates exactly ONE replica (single serve fact), never fanout
#[test]
fn single_replica_not_fanout() {
    rt().block_on(async {
        let (h, audit, r) = prod(3, Some(policy_fresh()), "hash_key").await;
        r.handle(&h, &req("E1", 1000, "c1")).await;
        let all = audit.all_facts().await.unwrap();
        assert_eq!(serve_facts(&audit).await.len(), 1, "exactly one replica served");
        assert!(all.iter().all(|f| f.value["operation"] != json!("invoke_fanout")), "fanout is never on the hot path");
    });
}

// 4: a non-production pool cannot be served
#[test]
fn non_production_refused() {
    rt().block_on(async {
        let (mut h, _a, mut r) = prod(2, Some(policy_fresh()), "hash_key").await;
        register(&mut h, "carol", AgentKind::Agent).await;
        h.create_pool(&passport("carol"), "draft", "draft", PoolVisibility::Private).await.unwrap();
        r.route_with_strategy("/draft", "draft", "hash_key");
        let resp = r.handle(&h, &req_path("/draft", "E9", "c9")).await;
        assert_ne!(resp.status, 200);
    });
}

fn req_path(path: &str, key: &str, corr: &str) -> IngressRequest {
    let mut headers = HashMap::new();
    headers.insert("authorization".to_string(), "Bearer vendortoken".to_string());
    headers.insert("x-vendor-event-id".to_string(), key.to_string());
    headers.insert("x-correlation-id".to_string(), corr.to_string());
    IngressRequest { method: "POST".to_string(), path: path.to_string(), headers, body: json!({"base": 1}) }
}
