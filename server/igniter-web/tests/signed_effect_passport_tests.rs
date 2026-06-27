//! LAB-IGNITER-WEB-SIGNED-EFFECT-PASSPORT-P27 — IgWeb effect-host boundary
//! routes final InvokeEffect through signed machine passports.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, PassportVerifier, sign_passport,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, COORDINATION_CAPABILITY, CoordinationHub,
    DuplicatePolicy, PoolRight, PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};
use igniter_server::effect_host::MachineEffectHost;
use igniter_server::protocol::{ResponseBody, ServerRequest};
use serde_json::{Value, json};
use std::sync::Arc;

const ISSUER: [u8; 32] = [27u8; 32];
const CAP: &str = "IO.WebEffectWrite";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(10.0))
}

fn signed_passport(subject: &str, capability_id: &str, scopes: &[&str]) -> CapabilityPassport {
    let mut p = CapabilityPassport {
        subject: subject.to_string(),
        capability_id: capability_id.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: String::new(),
    };
    p.evidence_digest = sign_passport(&ISSUER, &p);
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
        evidence_digest: "forged-static-digest".to_string(),
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

async fn hub_and_router() -> (CoordinationHub, IngressRouter, CapabilityPassport) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let verifier = PassportVerifier::new().trust(ISSUER);
    let mut hub = CoordinationHub::new_signed(audit, clock(), verifier);
    let svc = "host:svc";
    let dev = "host:dev";
    let actor = "host:write-actor";

    hub.register_agent(agent(actor, AgentKind::Agent))
        .await
        .unwrap();
    hub.register_agent(agent(dev, AgentKind::Developer))
        .await
        .unwrap();
    hub.register_agent(agent(svc, AgentKind::RuntimeActor))
        .await
        .unwrap();

    let coord = signed_passport(
        svc,
        COORDINATION_CAPABILITY,
        &[
            "create_pool",
            "import_capsule",
            "activate_capsule",
            "grant_access",
            "accept_recipe",
            "invoke",
        ],
    );
    let devp = signed_passport(
        dev,
        COORDINATION_CAPABILITY,
        &["accept_recipe", "grant_access"],
    );

    hub.create_pool(&coord, "svc", "effect host pool", PoolVisibility::Private)
        .await
        .unwrap();

    let capsule_src = "contract WriteRecord { input attempt: Integer  compute code = attempt  output code: Integer }";
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(capsule_src, "WriteRecord").unwrap();
    let bytes = m.checkpoint_bytes().await.unwrap();
    let digest = hub
        .add_capsule(&coord, "svc", bytes, vec![])
        .await
        .unwrap()
        .capsule_id;

    hub.accept_recipe(
        &devp,
        "svc",
        ServiceRecipe {
            recipe_id: "signed-web-effect-r1".into(),
            capsule_digest: digest,
            entry_contract: "WriteRecord".into(),
            input_schema_digest: None,
            capability_bindings: vec![],
            required_scopes: vec!["invoke".into()],
            receipt_policy: "audit".into(),
            retry_policy_ref: None,
            pool_sizing: 1,
            created_by: actor.into(),
            accepted_by: None,
            accepted_at: None,
            duplicate_policy: Some(DuplicatePolicy {
                mode: "dedup_strict".into(),
                key_header: "idempotency-key".into(),
                max_fresh: 0,
                after_limit: "dedup_last".into(),
                seed_field: "attempt".into(),
                variant_payload: false,
                require_key: true,
            }),
        },
    )
    .await
    .unwrap();

    hub.grant(&devp, "svc", svc, PoolRight::ActivateCapsule)
        .await
        .unwrap();

    let mut router = IngressRouter::new();
    router.route("/w", "svc");
    router.token("vendor-token", coord.clone());
    (hub, router, coord)
}

fn request() -> ServerRequest {
    let mut req = ServerRequest::new("POST", "/todos", json!({"title": "signed"}));
    req.headers.insert(
        "authorization".to_string(),
        "Bearer vendor-token".to_string(),
    );
    req
}

async fn run_effect_with_passport(effect_passport: CapabilityPassport) -> (u16, Value, u64) {
    let (hub, router, _) = hub_and_router().await;
    let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec.clone());
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let clk = clock();
    let sf = SingleFlight::new();
    let verifier = PassportVerifier::new().trust(ISSUER);
    let cfg = EffectBridgeConfig {
        registry: &registry,
        receipts: &receipts,
        effect_clock: &clk,
        effect_passport: &effect_passport,
        effect_passport_verifier: Some(&verifier),
        single_flight: &sf,
        capability_id: CAP.to_string(),
        operation: "write_record".to_string(),
        scope: "write".to_string(),
    };
    let mut host = MachineEffectHost::new(&router, &hub, &cfg);
    host.bind_target("todo-create", "/w");
    let response = host
        .run_invoke_effect(
            &request(),
            "todo-create",
            &json!({"values": {"title": "signed"}}),
            Some("corr-p27".to_string()),
            Some("idem-p27".to_string()),
        )
        .await;
    let body = match response.body {
        ResponseBody::Json(v) => v,
        _ => Value::Null,
    };
    (response.status, body, exec.attempts())
}

#[test]
fn forged_effect_passport_is_refused_at_web_effect_host_boundary() {
    rt().block_on(async {
        let forged = forged_passport("host", CAP, &["write"]);
        let (status, body, attempts) = run_effect_with_passport(forged).await;

        assert_eq!(status, 403, "body={body}");
        assert_eq!(body["status"], "denied");
        assert!(
            body["detail"].to_string().contains("Untrusted"),
            "body={body}"
        );
        assert_eq!(attempts, 0, "forged passport must not reach executor");
    });
}

#[test]
fn valid_signed_effect_passport_still_commits() {
    rt().block_on(async {
        let signed = signed_passport("host", CAP, &["write"]);
        let (status, body, attempts) = run_effect_with_passport(signed).await;

        assert_eq!(status, 200, "body={body}");
        assert_eq!(body["status"], "committed");
        assert_eq!(attempts, 1);
    });
}
