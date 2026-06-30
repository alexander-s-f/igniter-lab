//! LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17 — a declared ViewArtifact action invokes a REAL capsule
//! through `CoordinationHub` serving. Double gate (declared + registered) + recipe-match refuse
//! before invoke; passport/grant/production gate refuses inside invoke. Serving INVOKE only — no
//! capability-IO receipt. Mirrors `coordination_recipe_tests.rs` for the fixture.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::CapabilityPassport;
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRight, PoolVisibility,
    ServiceRecipe, COORD_AUDIT_STORE,
};
use igniter_machine::frame_binding::{FrameBindingBridge, FrameBindingRefusal, FrameBindingResult};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::registry::ContractRegistry;
use serde_json::{json, Value};
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
    "export_capsule",
    "grant_access",
    "admin_pool",
    "accept_recipe",
    "invoke",
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

/// alice builds a candidate pool `svc` with a real Add capsule; returns the capsule digest.
async fn setup(h: &mut CoordinationHub) -> String {
    register(h, "alice", AgentKind::Agent).await;
    register(h, "dev", AgentKind::Developer).await;
    register(h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(
        &passport("alice"),
        "svc",
        "candidate",
        PoolVisibility::Private,
    )
    .await
    .unwrap();
    let bytes = add_capsule_bytes().await;
    let cref = h
        .add_capsule(&passport("alice"), "svc", bytes, vec![])
        .await
        .unwrap();
    cref.capsule_id
}

/// Promote `svc` to production with a signed recipe and grant the vendor activation. Ready to serve.
async fn production_pool(h: &mut CoordinationHub) {
    let digest = setup(h).await;
    h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice"))
        .await
        .unwrap();
    h.grant(
        &passport("dev"),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
}

fn registry_with(names: &[&str]) -> ContractRegistry {
    let mut r = ContractRegistry::new();
    for n in names {
        r.register(n.to_string(), json!({ "entry_contract": n }));
    }
    r
}

async fn count(audit: &Arc<dyn TBackend>, store: &str) -> usize {
    audit
        .all_facts()
        .await
        .unwrap()
        .into_iter()
        .filter(|f| f.store == store)
        .count()
}

const ARTIFACT: &str = r#"{ "artifact":"view","version":0,"layout":"workbench",
  "actions": { "add": { "contract": "Add", "input": { "a":"$form.a","b":"$form.b" } } } }"#;

// ── the proof ───────────────────────────────────────────────────────────────────────────────────

#[test]
fn declared_registered_action_invokes_real_capsule_and_audits_without_a_receipt() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        production_pool(&mut h).await;
        let registry = registry_with(&["Add"]);

        let audit_before = count(&audit, COORD_AUDIT_STORE).await;
        let out = FrameBindingBridge::handle_action(
            ARTIFACT,
            "add",
            json!({ "a": 2, "b": 3 }),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;

        assert_eq!(
            out.ok(),
            Some(&json!(5)),
            "real capsule activation returned a+b=5"
        );
        assert!(
            count(&audit, COORD_AUDIT_STORE).await > audit_before,
            "the invoke wrote a coordination audit fact"
        );
        assert_eq!(
            count(&audit, "__receipts__").await,
            0,
            "serving invoke produced NO capability-IO receipt"
        );
    });
}

#[test]
fn missing_declaration_refuses_before_invoke() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        production_pool(&mut h).await;
        let registry = registry_with(&["Add"]);
        let audit_before = count(&audit, COORD_AUDIT_STORE).await;

        let out = FrameBindingBridge::handle_action(
            ARTIFACT,
            "not_declared",
            json!({}),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;
        assert!(matches!(
            out.refusal(),
            Some(FrameBindingRefusal::MissingDeclaration(_))
        ));
        assert_eq!(
            count(&audit, COORD_AUDIT_STORE).await,
            audit_before,
            "no invoke audit — refused before invoke"
        );
    });
}

#[test]
fn missing_registry_entry_refuses_before_invoke() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        production_pool(&mut h).await;
        let registry = ContractRegistry::new(); // "Add" NOT registered
        let audit_before = count(&audit, COORD_AUDIT_STORE).await;

        let out = FrameBindingBridge::handle_action(
            ARTIFACT,
            "add",
            json!({ "a": 2, "b": 3 }),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;
        match out.refusal() {
            Some(FrameBindingRefusal::NotRegistered(c)) => assert_eq!(c, "Add"),
            other => panic!("expected NotRegistered, got {other:?}"),
        }
        assert_eq!(
            count(&audit, COORD_AUDIT_STORE).await,
            audit_before,
            "refused before invoke"
        );
    });
}

#[test]
fn recipe_entry_contract_mismatch_refuses_before_invoke() {
    rt().block_on(async {
        let (mut h, audit) = hub();
        production_pool(&mut h).await; // recipe.entry_contract == "Add"
                                       // action declares (and registry registers) a DIFFERENT contract
        let mismatch = r#"{ "artifact":"view","layout":"workbench",
          "actions": { "add": { "contract": "Mul" } } }"#;
        let registry = registry_with(&["Mul"]);
        let audit_before = count(&audit, COORD_AUDIT_STORE).await;

        let out = FrameBindingBridge::handle_action(
            mismatch,
            "add",
            json!({ "a": 2, "b": 3 }),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;
        match out.refusal() {
            Some(FrameBindingRefusal::RecipeMismatch { action, recipe }) => {
                assert_eq!(action, "Mul");
                assert_eq!(recipe, "Add");
            }
            other => panic!("expected RecipeMismatch, got {other:?}"),
        }
        assert_eq!(
            count(&audit, COORD_AUDIT_STORE).await,
            audit_before,
            "refused before invoke"
        );
    });
}

#[test]
fn missing_grant_is_refused_by_the_coordination_gate() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        // production pool + recipe but NO ActivateCapsule grant to the vendor
        let digest = setup(&mut h).await;
        h.accept_recipe(&passport("dev"), "svc", recipe(&digest, "alice"))
            .await
            .unwrap();
        let registry = registry_with(&["Add"]);

        let out = FrameBindingBridge::handle_action(
            ARTIFACT,
            "add",
            json!({ "a": 2, "b": 3 }),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;
        // the real coordination gate refuses (the bridge passed its declared/registered/recipe gates)
        assert!(
            matches!(out.refusal(), Some(FrameBindingRefusal::Pool(_))),
            "coordination gate refused: {:?}",
            out.refusal()
        );
        assert!(out.ok().is_none());
    });
}

#[test]
fn bad_artifact_json_is_refused() {
    rt().block_on(async {
        let (mut h, _audit) = hub();
        production_pool(&mut h).await;
        let registry = registry_with(&["Add"]);
        let out = FrameBindingBridge::handle_action(
            "{ not json",
            "add",
            json!({}),
            &passport("vendor:acme"),
            "svc",
            &h,
            &registry,
        )
        .await;
        assert!(matches!(
            out.refusal(),
            Some(FrameBindingRefusal::BadArtifact(_))
        ));
    });
}
