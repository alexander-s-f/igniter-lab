//! LAB-MACHINE-AGENT-TRANSFER-P4 — audited two-phase capsule transfer envelopes.
//!
//! `proposed → accepted/rejected/revoked` (pattern reuse of the P6 write lifecycle; not the
//! write module). Idempotent accept, immutable source, content-addressed ref import, declared
//! rights only, developer override, every transition audited. Same machine; no federation /
//! signatures / consensus / production serving.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRefusal, PoolRight, PoolVisibility,
    TransferState, COORD_AUDIT_STORE,
};
use serde_json::Value;
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
    "export_capsule", "grant_access", "admin_pool", "send_message", "read_message",
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

async fn audit_events(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit.all_facts().await.unwrap().into_iter().filter(|f| f.store == COORD_AUDIT_STORE).map(|f| f.value).collect()
}

/// Register alice (owner of pool `src` with one capsule) + bob; return the capsule_id.
async fn base(h: &mut CoordinationHub) -> String {
    register(h, "alice", AgentKind::Agent).await;
    register(h, "bob", AgentKind::Agent).await;
    h.create_pool(&passport("alice"), "src", "source", PoolVisibility::Private).await.unwrap();
    let cref = h.add_capsule(&passport("alice"), "src", b"capsule-bytes".to_vec(), vec![]).await.unwrap();
    cref.capsule_id
}

// 1 + 3 + 4: propose (export) → accept (import) → ref appears; source immutable
#[test]
fn propose_accept_imports_ref_source_immutable() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();

        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![PoolRight::ActivateCapsule], "handoff", None).await.unwrap();
        assert!(xid.starts_with("xfer:"));

        let state = h.accept_transfer(&passport("bob"), &xid).await.unwrap();
        assert_eq!(state, TransferState::Accepted);
        // ref appears in target pool
        assert_eq!(h.pool("dst").unwrap().capsule_refs.len(), 1);
        assert_eq!(h.pool("dst").unwrap().capsule_refs[0].capsule_id, cap);
        // source pool/ref untouched; no byte copy (content-addressed dedup)
        assert_eq!(h.pool("src").unwrap().capsule_refs.len(), 1);
        assert_eq!(h.content_count(), 1);
    });
}

// 2: recipient without import_capsule cannot accept
#[test]
fn recipient_without_import_cannot_accept() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        // target pool owned by ALICE, not bob, and bob has no grant on it
        h.create_pool(&passport("alice"), "alice_dst", "alice's other", PoolVisibility::Shared).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "alice_dst", &cap, vec![], "x", None).await.unwrap();

        assert_eq!(h.accept_transfer(&passport("bob"), &xid).await.unwrap_err(), PoolRefusal::NotGranted);
        assert_eq!(h.pool("alice_dst").unwrap().capsule_refs.len(), 0);
    });
}

// 5: rejected transfer does not import
#[test]
fn rejected_does_not_import() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "x", None).await.unwrap();

        assert_eq!(h.reject_transfer(&passport("bob"), &xid).await.unwrap(), TransferState::Rejected);
        assert_eq!(h.pool("dst").unwrap().capsule_refs.len(), 0);
        // accepting a rejected transfer is refused
        assert!(matches!(h.accept_transfer(&passport("bob"), &xid).await.unwrap_err(), PoolRefusal::Invalid(_)));
    });
}

// 6: revoked transfer prevents future accept
#[test]
fn revoked_prevents_accept() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "x", None).await.unwrap();

        assert_eq!(h.revoke_transfer(&passport("alice"), &xid).await.unwrap(), TransferState::Revoked);
        assert!(matches!(h.accept_transfer(&passport("bob"), &xid).await.unwrap_err(), PoolRefusal::Invalid(_)));
        assert_eq!(h.pool("dst").unwrap().capsule_refs.len(), 0);
    });
}

// 7: duplicate accept is idempotent
#[test]
fn duplicate_accept_idempotent() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "x", None).await.unwrap();

        assert_eq!(h.accept_transfer(&passport("bob"), &xid).await.unwrap(), TransferState::Accepted);
        assert_eq!(h.accept_transfer(&passport("bob"), &xid).await.unwrap(), TransferState::Accepted);
        assert_eq!(h.pool("dst").unwrap().capsule_refs.len(), 1, "no second import on duplicate accept");
    });
}

// 8: transfer grants only the declared rights
#[test]
fn transfer_grants_only_declared_rights() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        // shared pool owned by alice; bob granted import so he can accept into it
        h.create_pool(&passport("alice"), "shared", "shared", PoolVisibility::Shared).await.unwrap();
        h.grant(&passport("alice"), "shared", "bob", PoolRight::ImportCapsule).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "shared", &cap, vec![PoolRight::ActivateCapsule], "x", None).await.unwrap();
        h.accept_transfer(&passport("bob"), &xid).await.unwrap();

        // bob got ActivateCapsule (declared) but NOT ForkCapsule
        assert!(h.check_right(&passport("bob"), "shared", PoolRight::ActivateCapsule).await.is_ok());
        assert_eq!(h.check_right(&passport("bob"), "shared", PoolRight::ForkCapsule).await.unwrap_err(), PoolRefusal::NotGranted);
    });
}

// 9: developer can approve/override a transfer, audited
#[test]
fn developer_can_override_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        let cap = base(&mut h).await;
        register(&mut h, "dev", AgentKind::Developer).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "x", None).await.unwrap();

        // developer accepts on override (not the recipient) — privileged, audited
        assert_eq!(h.accept_transfer(&passport("dev"), &xid).await.unwrap(), TransferState::Accepted);
        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "accept_transfer" && e["actor"] == "dev" && e["outcome"] == "allowed"));
    });
}

// 10: all state transitions are bitemporal audit facts
#[test]
fn all_transitions_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "x", None).await.unwrap();
        h.accept_transfer(&passport("bob"), &xid).await.unwrap();

        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "propose_transfer" && e["outcome"] == "allowed"));
        assert!(evs.iter().any(|e| e["operation"] == "accept_transfer" && e["outcome"] == "allowed"));
        // and the transfer envelope itself is a fact whose latest state is accepted
        let env = h.read_transfer(&xid).await.unwrap();
        assert_eq!(env.state, TransferState::Accepted);
    });
}

// 11: transfer can carry a ServiceRecipe digest (optional, not served)
#[test]
fn transfer_carries_recipe_digest() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        let cap = base(&mut h).await;
        h.create_pool(&passport("bob"), "dst", "bob's", PoolVisibility::Private).await.unwrap();
        let xid = h.propose_transfer(&passport("alice"), "bob", "src", "dst", &cap, vec![], "candidate", Some("recipe-digest-abc".to_string())).await.unwrap();

        let env = h.read_transfer(&xid).await.unwrap();
        assert_eq!(env.recipe_digest.as_deref(), Some("recipe-digest-abc"));
        // P4 does not serve — the digest is carried, nothing is deployed.
    });
}
