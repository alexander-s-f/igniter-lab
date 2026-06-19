//! LAB-MACHINE-SERVICE-RECIPE-P5 — dev→prod handoff + agentless serving.
//!
//! The bridge: agent-built candidate capsule → developer-signed `ServiceRecipe` → production
//! pool → vendor/runtime passport invokes the entry contract → audit. Invocation is a REAL
//! capsule activation (resume bytes + dispatch), not a message. Same machine; no external HTTP
//! server, no messenger hot path, no federation.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRefusal, PoolRight, PoolVisibility,
    ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::machine::IgniterMachine;
use serde_json::{json, Value};
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn hub() -> (CoordinationHub, Arc<dyn TBackend>) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    (CoordinationHub::new(audit.clone(), clock()), audit)
}

const SCOPES: &[&str] = &[
    "create_pool", "import_capsule", "list_capsules", "activate_capsule", "fork_capsule",
    "export_capsule", "grant_access", "admin_pool", "accept_recipe", "invoke",
    "propose_transfer", "accept_transfer", "reject_transfer", "revoke_transfer",
];

fn passport(subject: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: "coordination".to_string(),
        scopes: SCOPES.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(AgentIdentity { agent_id: id.into(), kind, label: id.into(), status: AgentStatus::Active, registered_at: 0.0 }).await.unwrap();
}

/// A REAL capsule: a machine with the `Add` contract, checkpointed to `.igm` bytes.
async fn add_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    let src = "contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }";
    m.load_contract_source(src, "Add").unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn recipe(digest: &str, created_by: &str) -> ServiceRecipe {
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
        created_by: created_by.into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: None,
    }
}

async fn audit_events(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit.all_facts().await.unwrap().into_iter().filter(|f| f.store == COORD_AUDIT_STORE).map(|f| f.value).collect()
}

/// Register alice/dev/vendor, alice builds pool `svc` with a real Add capsule, returns digest.
async fn setup(h: &mut CoordinationHub) -> String {
    register(h, "alice", AgentKind::Agent).await;
    register(h, "dev", AgentKind::Developer).await;
    register(h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&passport("alice"), "svc", "candidate", PoolVisibility::Private).await.unwrap();
    let bytes = add_capsule_bytes().await;
    let cref = h.add_capsule(&passport("alice"), "svc", bytes, vec![]).await.unwrap();
    cref.capsule_id
}

// 2 + 3: developer signs the recipe and the pool becomes production, owned by the developer
#[test]
fn dev_signs_recipe_promotes_to_production() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let digest = setup(&mut h).await;
        h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice")).await.unwrap();

        let pool = h.pool("svc").unwrap();
        assert_eq!(pool.visibility, PoolVisibility::Production);
        assert_eq!(pool.owner_agent_id, "dev");
        let r = h.read_recipe("svc").await.unwrap();
        assert_eq!(r.accepted_by.as_deref(), Some("dev"));
    });
}

// 4 + 6 + 7: a vendor/runtime passport invokes the entry contract via real activation, audited
#[test]
fn vendor_can_invoke_production_service() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        let digest = setup(&mut h).await;
        h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice")).await.unwrap();
        h.grant(&passport("dev"), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();

        // real capsule activation: resume + dispatch("Add", {2,3}) → 5
        let out = h.invoke(&passport("vendor:acme"), "svc", json!({ "a": 2, "b": 3 })).await.unwrap();
        assert_eq!(out, json!(5));

        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "invoke" && e["actor"] == "vendor:acme" && e["outcome"] == "allowed"));
    });
}

// 5: an agent without an invoke (ActivateCapsule) grant cannot invoke
#[test]
fn agent_without_invoke_grant_refused() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let digest = setup(&mut h).await;
        h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice")).await.unwrap();
        register(&mut h, "mallory", AgentKind::Agent).await;

        assert_eq!(h.invoke(&passport("mallory"), "svc", json!({ "a": 1, "b": 1 })).await.unwrap_err(), PoolRefusal::NotGranted);
    });
}

// 8: a production pool of N refs sharing one content_digest = homogeneous service image
#[test]
fn homogeneous_replicas_same_digest() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "dev", AgentKind::Developer).await;
        h.create_pool(&passport("alice"), "svc", "candidate", PoolVisibility::Private).await.unwrap();
        let bytes = add_capsule_bytes().await;
        // three replicas of the SAME image
        for _ in 0..3 {
            h.add_capsule(&passport("alice"), "svc", bytes.clone(), vec![]).await.unwrap();
        }
        let pool = h.pool("svc").unwrap();
        assert_eq!(pool.capsule_refs.len(), 3);
        let d0 = &pool.capsule_refs[0].content_digest;
        assert!(pool.capsule_refs.iter().all(|r| &r.content_digest == d0), "all replicas share one digest");
        assert_eq!(h.content_count(), 1, "identical replicas store ONE image (content-addressed)");
    });
}

// 9: a recipe whose capsule digest is not in the pool is refused
#[test]
fn capsule_digest_mismatch_refused() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let _digest = setup(&mut h).await;
        let bad = recipe("deadbeef-not-in-pool", "alice");
        assert!(matches!(h.accept_recipe(&passport("dev"), "svc", bad).await.unwrap_err(), PoolRefusal::Invalid(_)));
    });
}

// 10 (in spirit) + 6: invocation is activation, not messenger; no IO receipts; pure VM dispatch
#[test]
fn invocation_is_activation_not_messenger() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        let digest = setup(&mut h).await;
        h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice")).await.unwrap();
        h.grant(&passport("dev"), "svc", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
        h.invoke(&passport("vendor:acme"), "svc", json!({ "a": 10, "b": 7 })).await.unwrap();

        let all = audit.all_facts().await.unwrap();
        // no messenger facts and no capability-IO receipts were produced by serving
        assert!(all.iter().all(|f| f.store != "__messenger__"));
        assert!(all.iter().all(|f| f.store != "__receipts__"));
    });
}

// 1 + end-to-end: agent transfers candidate (carrying recipe_digest) → dev accepts → dev signs
//                  recipe → vendor invokes. The whole bridge.
#[test]
fn full_handoff_via_transfer_then_invoke() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "dev", AgentKind::Developer).await;
        register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
        // alice builds the candidate in her pool
        h.create_pool(&passport("alice"), "candidate", "c", PoolVisibility::Private).await.unwrap();
        let bytes = add_capsule_bytes().await;
        let cref = h.add_capsule(&passport("alice"), "candidate", bytes, vec![]).await.unwrap();
        // developer's production pool
        h.create_pool(&passport("dev"), "prod", "prod", PoolVisibility::Private).await.unwrap();

        // P4 transfer carries the recipe digest; dev accepts the transfer (capsule lands in prod)
        let xid = h.propose_transfer(&passport("alice"), "dev", "candidate", "prod", &cref.capsule_id, vec![], "handoff", Some("recipe-digest".into())).await.unwrap();
        h.accept_transfer(&passport("dev"), &xid).await.unwrap();

        // dev signs the recipe → prod becomes production; vendor invokes
        h.accept_recipe(&passport("dev"), "prod", recipe(&cref.capsule_id, "alice")).await.unwrap();
        h.grant(&passport("dev"), "prod", "vendor:acme", PoolRight::ActivateCapsule).await.unwrap();
        let out = h.invoke(&passport("vendor:acme"), "prod", json!({ "a": 20, "b": 22 })).await.unwrap();
        assert_eq!(out, json!(42));
    });
}
