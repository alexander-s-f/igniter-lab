//! LAB-MACHINE-SIGNED-PASSPORT-DATAPLANE-P26 — signed passport verifier on
//! write + coordination data-plane entrypoints.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    AuthRefusal, CapabilityExecutorRegistry, CapabilityPassport, PassportVerifier, RECEIPTS_STORE,
    RunMode, sign_passport,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, COORD_AUDIT_STORE, CoordinationHub, PoolRefusal,
    PoolVisibility,
};
use igniter_machine::write::{
    FakeWriteExecutor, WriteBehavior, WriteRequest, WriteState, run_write_effect_signed,
};
use serde_json::{Value, json};
use std::sync::Arc;

const ISSUER: [u8; 32] = [26u8; 32];
const OTHER_ISSUER: [u8; 32] = [27u8; 32];
const WRITE_CAP: &str = "IO.WriteCapability";
const COORD_CAP: &str = "coordination";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn clock_at(t: f64) -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(t))
}

fn store() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}

fn verifier() -> PassportVerifier {
    PassportVerifier::new().trust(ISSUER)
}

fn signed_passport(
    key: &[u8; 32],
    subject: &str,
    capability_id: &str,
    scopes: &[&str],
    expires_at: Option<f64>,
) -> CapabilityPassport {
    let mut p = CapabilityPassport {
        subject: subject.to_string(),
        capability_id: capability_id.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at,
        revoked: false,
        evidence_digest: String::new(),
    };
    p.evidence_digest = sign_passport(key, &p);
    p
}

fn forged_passport(subject: &str, capability_id: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: capability_id.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "forged-digest-only-authority".to_string(),
    }
}

fn write_registry(exec: Arc<FakeWriteExecutor>) -> CapabilityExecutorRegistry {
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    reg
}

fn write_req(key: &str) -> WriteRequest {
    WriteRequest {
        capability_id: WRITE_CAP.to_string(),
        operation: "put".to_string(),
        idempotency_key: key.to_string(),
        payload: json!({"v": 1}),
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

#[test]
fn write_path_refuses_forged_or_unsigned_passport() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(WRITE_CAP, WriteBehavior::Commit));
        let reg = write_registry(exec.clone());
        let receipts = store();
        let forged = forged_passport("svc", WRITE_CAP, &["write"]);

        let out = run_write_effect_signed(
            &reg,
            &receipts,
            &clock_at(10.0),
            &verifier(),
            &forged,
            "write",
            &write_req("forged-write"),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::Denied);
        assert!(out.detail.unwrap().contains("Untrusted"));
        assert_eq!(exec.attempts(), 0);
        assert!(
            receipts
                .read_as_of(RECEIPTS_STORE, "IO.WriteCapability:forged-write", f64::MAX)
                .await
                .unwrap()
                .is_none()
        );
    });
}

#[test]
fn write_path_accepts_valid_signed_passport_and_preserves_scope_time_checks() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(WRITE_CAP, WriteBehavior::Commit));
        let reg = write_registry(exec.clone());
        let receipts = store();
        let signed = signed_passport(&ISSUER, "svc", WRITE_CAP, &["write"], Some(1_000_000.0));

        let ok = run_write_effect_signed(
            &reg,
            &receipts,
            &clock_at(10.0),
            &verifier(),
            &signed,
            "write",
            &write_req("valid-write"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(ok.state, WriteState::Committed);
        assert_eq!(exec.attempts(), 1);

        let wrong_scope = signed_passport(&ISSUER, "svc", WRITE_CAP, &["read"], Some(1_000_000.0));
        let denied = run_write_effect_signed(
            &reg,
            &receipts,
            &clock_at(10.0),
            &verifier(),
            &wrong_scope,
            "write",
            &write_req("wrong-scope"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(denied.state, WriteState::Denied);
        assert!(denied.detail.unwrap().contains("MissingScope"));

        let expired = signed_passport(&ISSUER, "svc", WRITE_CAP, &["write"], Some(5.0));
        let denied = run_write_effect_signed(
            &reg,
            &receipts,
            &clock_at(10.0),
            &verifier(),
            &expired,
            "write",
            &write_req("expired"),
            RunMode::Live,
        )
        .await
        .unwrap();
        assert_eq!(denied.state, WriteState::Denied);
        assert!(denied.detail.unwrap().contains("Expired"));
        assert_eq!(exec.attempts(), 1, "refusals do not reach executor");
    });
}

#[test]
fn coordination_path_refuses_forged_or_unsigned_passport() {
    rt().block_on(async {
        let audit = store();
        let mut hub = CoordinationHub::new_signed(audit.clone(), clock_at(10.0), verifier());
        hub.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();

        let forged = forged_passport("alice", COORD_CAP, &["create_pool"]);
        let err = hub
            .create_pool(&forged, "pool1", "Alice pool", PoolVisibility::Private)
            .await
            .unwrap_err();

        assert_eq!(err, PoolRefusal::Unauthenticated(AuthRefusal::Untrusted));
        assert!(hub.pool("pool1").is_none());
        let events = audit_events(&audit).await;
        assert!(events.iter().any(|e| {
            e["operation"] == "create_pool"
                && e["outcome"] == "denied"
                && e["reason"].as_str().unwrap_or("").contains("Untrusted")
        }));
    });
}

#[test]
fn coordination_path_accepts_valid_signed_passport() {
    rt().block_on(async {
        let audit = store();
        let mut hub = CoordinationHub::new_signed(audit.clone(), clock_at(10.0), verifier());
        hub.register_agent(agent("alice", AgentKind::Agent))
            .await
            .unwrap();
        let signed = signed_passport(
            &ISSUER,
            "alice",
            COORD_CAP,
            &["create_pool"],
            Some(1_000_000.0),
        );

        hub.create_pool(&signed, "pool1", "Alice pool", PoolVisibility::Private)
            .await
            .unwrap();

        assert!(hub.pool("pool1").is_some());
        let events = audit_events(&audit).await;
        assert!(
            events
                .iter()
                .any(|e| { e["operation"] == "create_pool" && e["outcome"] == "allowed" })
        );
    });
}

#[test]
fn untrusted_issuer_is_refused_on_signed_paths() {
    rt().block_on(async {
        let exec = Arc::new(FakeWriteExecutor::new(WRITE_CAP, WriteBehavior::Commit));
        let reg = write_registry(exec.clone());
        let receipts = store();
        let foreign = signed_passport(&OTHER_ISSUER, "svc", WRITE_CAP, &["write"], Some(1000.0));

        let out = run_write_effect_signed(
            &reg,
            &receipts,
            &clock_at(10.0),
            &verifier(),
            &foreign,
            "write",
            &write_req("foreign"),
            RunMode::Live,
        )
        .await
        .unwrap();

        assert_eq!(out.state, WriteState::Denied);
        assert!(out.detail.unwrap().contains("Untrusted"));
        assert_eq!(exec.attempts(), 0);
    });
}
