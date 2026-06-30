//! LAB-MACHINE-AGENT-MESSENGER-P3 — append-only audited messenger bus.
//!
//! Messages are FACTS + audit + ACL, NOT a mutable inbox. Direct notes, request/ack, developer
//! escalation, capsule refs (which do NOT grant access), participant visibility, every op
//! audited. No delivery worker, no federation, no voting, no production serving.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, MessageKind, PoolRefusal, PoolRight,
    PoolVisibility, COORD_AUDIT_STORE,
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

const SCOPES: &[&str] = &[
    "create_pool",
    "import_capsule",
    "list_capsules",
    "activate_capsule",
    "fork_capsule",
    "grant_access",
    "admin_pool",
    "send_message",
    "read_message",
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

fn agent(id: &str, kind: AgentKind) -> AgentIdentity {
    AgentIdentity {
        agent_id: id.to_string(),
        kind,
        label: id.to_string(),
        status: AgentStatus::Active,
        registered_at: 0.0,
    }
}

async fn register(h: &mut CoordinationHub, id: &str, kind: AgentKind) {
    h.register_agent(agent(id, kind)).await.unwrap();
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

// 1. agent can send a note to a registered agent
#[test]
fn agent_can_send_note() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        let id = h
            .send_message(
                &passport("alice"),
                "bob",
                "t1",
                MessageKind::Note,
                b"hi bob",
                vec![],
                false,
            )
            .await
            .unwrap();
        assert!(id.starts_with("msg:"));
    });
}

// 2. recipient can list/read messages addressed to them
#[test]
fn recipient_can_list_and_read() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        h.send_message(
            &passport("alice"),
            "bob",
            "t1",
            MessageKind::Note,
            b"hi",
            vec![],
            false,
        )
        .await
        .unwrap();

        let inbox = h.list_inbox(&passport("bob"), "bob").await.unwrap();
        assert_eq!(inbox.len(), 1);
        assert_eq!(inbox[0].from_agent, "alice");
        let thread = h.read_thread(&passport("bob"), "t1").await.unwrap();
        assert_eq!(thread.len(), 1);
    });
}

// 3. third party cannot read a thread or someone else's inbox
#[test]
fn third_party_cannot_read() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        register(&mut h, "carol", AgentKind::Agent).await;
        h.send_message(
            &passport("alice"),
            "bob",
            "t1",
            MessageKind::Note,
            b"hi",
            vec![],
            false,
        )
        .await
        .unwrap();

        assert_eq!(
            h.read_thread(&passport("carol"), "t1").await.unwrap_err(),
            PoolRefusal::NotGranted
        );
        assert_eq!(
            h.list_inbox(&passport("carol"), "bob").await.unwrap_err(),
            PoolRefusal::NotGranted
        );
    });
}

// 4. a request requiring ack stays pending until acked
#[test]
fn request_pending_until_ack() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        let req = h
            .send_message(
                &passport("alice"),
                "bob",
                "t1",
                MessageKind::Request,
                b"please review",
                vec![],
                true,
            )
            .await
            .unwrap();

        assert_eq!(h.pending_requests("bob").await.len(), 1);
        h.ack(&passport("bob"), &req).await.unwrap();
        assert_eq!(h.pending_requests("bob").await.len(), 0);
    });
}

// 5. the ack is linked to the request and routed back to the requester
#[test]
fn ack_linked_to_request() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        let req = h
            .send_message(
                &passport("alice"),
                "bob",
                "t1",
                MessageKind::Request,
                b"q",
                vec![],
                true,
            )
            .await
            .unwrap();
        h.ack(&passport("bob"), &req).await.unwrap();

        // alice (the requester) receives the ack, linked by in_reply_to
        let alice_inbox = h.list_inbox(&passport("alice"), "alice").await.unwrap();
        let ack = alice_inbox
            .iter()
            .find(|m| m.kind == MessageKind::Ack)
            .expect("ack delivered to requester");
        assert_eq!(ack.in_reply_to.as_deref(), Some(req.as_str()));
        assert_eq!(ack.from_agent, "bob");
    });
}

// 6. developer escalation goes to the developer mailbox and is audited
#[test]
fn developer_escalation_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "dev", AgentKind::Developer).await;
        h.escalate(&passport("alice"), "t1", b"need a decision", vec![])
            .await
            .unwrap();

        // the developer can read the developer mailbox
        let dev_inbox = h.list_inbox(&passport("dev"), "developer").await.unwrap();
        assert_eq!(dev_inbox.len(), 1);
        assert_eq!(dev_inbox[0].kind, MessageKind::Escalation);

        let evs = audit_events(&audit).await;
        assert!(evs.iter().any(|e| e["operation"] == "send_message"
            && e["reason"] == "escalation"
            && e["outcome"] == "allowed"));
    });
}

// 7. a message can carry a CapsuleRef, but access still requires pool rights
#[test]
fn capsule_ref_in_message_does_not_grant_access() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        h.create_pool(&passport("alice"), "pool1", "p", PoolVisibility::Private)
            .await
            .unwrap();
        let cref = h
            .add_capsule(&passport("alice"), "pool1", b"capsule".to_vec(), vec![])
            .await
            .unwrap();

        h.send_message(
            &passport("alice"),
            "bob",
            "t1",
            MessageKind::Note,
            b"here",
            vec![cref.capsule_id.clone()],
            false,
        )
        .await
        .unwrap();
        let inbox = h.list_inbox(&passport("bob"), "bob").await.unwrap();
        assert_eq!(inbox[0].capsule_refs, vec![cref.capsule_id]); // bob SEES the ref

        // ...but bob still cannot access the capsule's pool without a grant
        assert_eq!(
            h.check_right(&passport("bob"), "pool1", PoolRight::ActivateCapsule)
                .await
                .unwrap_err(),
            PoolRefusal::NotGranted
        );
    });
}

// 8. a revoked agent cannot send or read
#[test]
fn revoked_agent_cannot_send_or_read() {
    rt().block_on(async {
        let (mut h, _a) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        h.send_message(
            &passport("alice"),
            "bob",
            "t1",
            MessageKind::Note,
            b"hi",
            vec![],
            false,
        )
        .await
        .unwrap();
        h.set_agent_status("bob", AgentStatus::Revoked);

        assert_eq!(
            h.send_message(
                &passport("bob"),
                "alice",
                "t1",
                MessageKind::Note,
                b"x",
                vec![],
                false
            )
            .await
            .unwrap_err(),
            PoolRefusal::AgentNotActive
        );
        assert_eq!(
            h.list_inbox(&passport("bob"), "bob").await.unwrap_err(),
            PoolRefusal::AgentNotActive
        );
    });
}

// 9. all message operations create bitemporal audit facts (allowed + denied)
#[test]
fn all_message_ops_audited() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        register(&mut h, "alice", AgentKind::Agent).await;
        register(&mut h, "bob", AgentKind::Agent).await;
        register(&mut h, "carol", AgentKind::Agent).await;
        let req = h
            .send_message(
                &passport("alice"),
                "bob",
                "t1",
                MessageKind::Request,
                b"q",
                vec![],
                true,
            )
            .await
            .unwrap();
        h.ack(&passport("bob"), &req).await.unwrap();
        h.list_inbox(&passport("bob"), "bob").await.unwrap();
        let _ = h.read_thread(&passport("carol"), "t1").await; // denied

        let evs = audit_events(&audit).await;
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "send_message" && e["outcome"] == "allowed"));
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "ack" && e["outcome"] == "allowed"));
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "read_message" && e["outcome"] == "allowed"));
        assert!(evs
            .iter()
            .any(|e| e["operation"] == "read_message" && e["outcome"] == "denied"));
    });
}
