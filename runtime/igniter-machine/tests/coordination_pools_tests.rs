//! LAB-MACHINE-AGENT-POOLS-P2 — agent/pool registry + ACL + audit foundation.
//!
//! Proves the coordination foundation on one machine: passport authenticates WHO (P5), pool
//! ACL authorizes WHAT, every op writes an audit fact. No messenger, no transfer envelope, no
//! production serving — but the schema does not preclude them (visibility Production, free
//! actor subject incl. vendor:* / RuntimeActor, transferable ownership).

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRefusal, PoolRight, PoolVisibility,
    COORD_AUDIT_STORE,
};
use serde_json::Value;
use std::sync::Arc;

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

fn hub() -> (CoordinationHub, Arc<dyn TBackend>) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    (CoordinationHub::new(audit.clone(), clock()), audit)
}

/// A coordination passport: capability "coordination", carrying the op-classes the subject is
/// cleared for as scopes (the "who/what-class" half; per-pool authz is the ACL).
fn passport(subject: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: "coordination".to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}

const ALL_SCOPES: &[&str] = &[
    "create_pool",
    "import_capsule",
    "list_capsules",
    "activate_capsule",
    "fork_capsule",
    "grant_access",
    "admin_pool",
];

fn agent(id: &str, kind: AgentKind) -> AgentIdentity {
    AgentIdentity {
        agent_id: id.to_string(),
        kind,
        label: id.to_string(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    }
}

async fn audit_events(audit: &Arc<dyn TBackend>) -> Vec<Value> {
    audit
        .all_facts()
        .await
        .unwrap()
        .into_iter()
        .filter(|f| f.store == COORD_AUDIT_STORE)
        .map(|f| f.value)
        .collect()
}

// ── owner can create a pool and add a capsule ──────────────────────────────────

#[test]
fn owner_creates_pool_and_adds_capsule() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        let p = passport("alice", ALL_SCOPES);

        h.create_pool(&p, "pool1", "Alice's pool", PoolVisibility::Private)
            .await
            .unwrap();
        let cref = h
            .add_capsule(&p, "pool1", b"capsule-bytes-A".to_vec(), vec!["v1".into()])
            .await
            .unwrap();

        assert_eq!(h.pool("pool1").unwrap().capsule_refs.len(), 1);
        assert_eq!(cref.content_digest.len(), 64); // blake3 hex
                                                   // audited
        let evs = audit_events(&audit).await;
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "create_pool" && e["outcome"] == "allowed"));
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "import_capsule" && e["outcome"] == "allowed"));
    });
}

// ── another agent cannot list/activate/fork without a grant ────────────────────

#[test]
fn other_agent_denied_without_grant() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        h.register_agent(agent("bob", AgentKind::Agent))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(&alice, "pool1", "p", PoolVisibility::Private)
            .await
            .unwrap();
        h.add_capsule(&alice, "pool1", b"x".to_vec(), vec![])
            .await
            .unwrap();

        let bob = passport("bob", ALL_SCOPES);
        assert_eq!(
            h.list_capsules(&bob, "pool1").await.unwrap_err(),
            PoolRefusal::NotGranted
        );
        assert_eq!(
            h.check_right(&bob, "pool1", PoolRight::ActivateCapsule)
                .await
                .unwrap_err(),
            PoolRefusal::NotGranted
        );
        assert_eq!(
            h.check_right(&bob, "pool1", PoolRight::ForkCapsule)
                .await
                .unwrap_err(),
            PoolRefusal::NotGranted
        );
    });
}

// ── an explicit grant enables ONLY the granted operation ───────────────────────

#[test]
fn explicit_grant_enables_only_granted_op() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        h.register_agent(agent("bob", AgentKind::Agent))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(&alice, "pool1", "p", PoolVisibility::Shared)
            .await
            .unwrap();

        h.grant(&alice, "pool1", "bob", PoolRight::ListCapsules)
            .await
            .unwrap();

        let bob = passport("bob", ALL_SCOPES);
        assert!(h.list_capsules(&bob, "pool1").await.is_ok()); // granted
        assert_eq!(
            h.check_right(&bob, "pool1", PoolRight::ForkCapsule)
                .await
                .unwrap_err(),
            PoolRefusal::NotGranted
        ); // not granted
    });
}

// ── content-addressed dedup: identical bytes → one stored image ────────────────

#[test]
fn content_addressed_dedup() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(&alice, "p1", "p1", PoolVisibility::Private)
            .await
            .unwrap();
        h.create_pool(&alice, "p2", "p2", PoolVisibility::Private)
            .await
            .unwrap();

        let r1 = h
            .add_capsule(&alice, "p1", b"same-bytes".to_vec(), vec![])
            .await
            .unwrap();
        let r2 = h
            .add_capsule(&alice, "p2", b"same-bytes".to_vec(), vec![])
            .await
            .unwrap();
        let r3 = h
            .add_capsule(&alice, "p1", b"different".to_vec(), vec![])
            .await
            .unwrap();

        assert_eq!(r1.content_digest, r2.content_digest); // same content → same digest
        assert_ne!(r1.content_digest, r3.content_digest);
        assert_eq!(
            h.content_count(),
            2,
            "identical bytes are stored once (dedup)"
        );
    });
}

// ── developer-conductor grants + takes ownership; audited; visibility→production ─

#[test]
fn developer_grants_and_takes_ownership_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        h.register_agent(agent("dev", AgentKind::Developer))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(
            &alice,
            "candidate",
            "candidate service",
            PoolVisibility::Private,
        )
        .await
        .unwrap();

        // the developer (NOT the owner) can grant on the pool — conductor privilege, audited.
        let dev = passport("dev", ALL_SCOPES);
        h.grant(&dev, "candidate", "carol", PoolRight::ListCapsules)
            .await
            .unwrap();

        // dev→prod handoff: developer takes ownership and promotes to production.
        h.transfer_ownership(&dev, "candidate", "dev", Some(PoolVisibility::Production))
            .await
            .unwrap();
        let pool = h.pool("candidate").unwrap();
        assert_eq!(pool.owner_agent_id, "dev");
        assert_eq!(pool.visibility, PoolVisibility::Production);

        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "admin_pool"
            && e["actor"] == "dev"
            && e["outcome"] == "allowed"));
        assert!(evs.iter().any(|e| e["operation"] == "grant_access"
            && e["actor"] == "dev"
            && e["outcome"] == "allowed"));
    });
}

// ── revoked agent cannot access ────────────────────────────────────────────────

#[test]
fn revoked_agent_cannot_access() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        h.register_agent(agent("bob", AgentKind::Agent))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(&alice, "pool1", "p", PoolVisibility::Shared)
            .await
            .unwrap();
        h.grant(&alice, "pool1", "bob", PoolRight::ListCapsules)
            .await
            .unwrap();

        // bob works while active, then is revoked
        let bob = passport("bob", ALL_SCOPES);
        assert!(h.list_capsules(&bob, "pool1").await.is_ok());
        h.set_agent_status("bob", AgentStatus::Revoked);
        assert_eq!(
            h.list_capsules(&bob, "pool1").await.unwrap_err(),
            PoolRefusal::AgentNotActive
        );
    });
}

// ── passport failure is refused before the ACL, audited, no state change ───────

#[test]
fn passport_failure_refused_before_acl() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        // passport for alice WITHOUT the import_capsule scope
        let alice_full = passport("alice", ALL_SCOPES);
        h.create_pool(&alice_full, "pool1", "p", PoolVisibility::Private)
            .await
            .unwrap();

        let alice_no_import = passport("alice", &["create_pool", "list_capsules"]);
        let err = h
            .add_capsule(&alice_no_import, "pool1", b"x".to_vec(), vec![])
            .await
            .unwrap_err();
        assert!(matches!(err, PoolRefusal::Unauthenticated(_)));
        assert_eq!(h.content_count(), 0, "no state change on a refused op");

        let evs = audit_events(&audit).await;
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "import_capsule" && e["outcome"] == "denied"));
    });
}

// ── every operation produces a bitemporal audit fact (allowed + denied) ────────

#[test]
fn every_operation_is_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        h.register_agent(agent("bob", AgentKind::Agent))
            .await
            .unwrap();
        let alice = passport("alice", ALL_SCOPES);
        let bob = passport("bob", ALL_SCOPES);
        h.create_pool(&alice, "pool1", "p", PoolVisibility::Private)
            .await
            .unwrap();
        h.add_capsule(&alice, "pool1", b"x".to_vec(), vec![])
            .await
            .unwrap();
        let _ = h.list_capsules(&bob, "pool1").await; // denied

        let evs = audit_events(&audit).await;
        // register x2 + create + import + denied-list = 5
        assert!(evs.len() >= 5, "got {} audit events", evs.len());
        assert!(evs.iter().any(|e| e["outcome"] == "allowed"));
        assert!(evs.iter().any(|e| e["outcome"] == "denied"));
        // facts carry the actor + authority digest
        assert!(evs
            .iter()
            .all(|e| e.get("actor").is_some() && e.get("authority_digest").is_some()));
    });
}

// ── schema does not exclude a runtime/vendor actor (future production mode) ─────

#[test]
fn runtime_vendor_actor_schema_supported() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        h.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        // a non-agent subject — a vendor runtime actor — is a first-class identity
        h.register_agent(AgentIdentity {
            agent_id: "vendor:acme".to_string(),
            kind: AgentKind::RuntimeActor,
            label: "Acme webhooks".to_string(),
            status: AgentStatus::Active,
            registered_at: 0.0,
        })
        .await
        .unwrap();

        let alice = passport("alice", ALL_SCOPES);
        h.create_pool(&alice, "prodpool", "service", PoolVisibility::Production)
            .await
            .unwrap();
        h.grant(
            &alice,
            "prodpool",
            "vendor:acme",
            PoolRight::ActivateCapsule,
        )
        .await
        .unwrap();

        // the vendor subject authenticates + is authorized by the ACL like any subject
        let vendor = passport("vendor:acme", &["activate_capsule"]);
        assert!(h
            .check_right(&vendor, "prodpool", PoolRight::ActivateCapsule)
            .await
            .is_ok());
    });
}
