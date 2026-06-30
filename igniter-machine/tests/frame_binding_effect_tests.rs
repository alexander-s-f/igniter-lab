//! LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18 — a declared ViewArtifact action invokes a real capsule
//! (serving authority) and then performs its output as a declared capability-IO effect (HOST
//! authority) → receipt. Double authority; idempotent; fake executor only. Mirrors
//! `capability_io_bridge_tests.rs` + `frame_binding_tests.rs` for the fixture.

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, EchoCapabilityExecutor, RECEIPTS_STORE,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRight, PoolVisibility,
    ServiceRecipe,
};
use igniter_machine::frame_binding::FrameBindingRefusal;
use igniter_machine::frame_binding_effect::{FrameBindingEffectBridge, FrameBindingEffectRefusal};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::registry::ContractRegistry;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

const EFFECT_CAP: &str = "IO.FrameFixture";

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}

const SCOPES: &[&str] = &[
    "create_pool",
    "import_capsule",
    "grant_access",
    "accept_recipe",
    "invoke",
];
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
/// The HOST effect passport — a DISTINCT authority from the serving (vendor) passport.
fn effect_passport(scope: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: "host".into(),
        capability_id: EFFECT_CAP.into(),
        scopes: vec![scope.into()],
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "host-sig".into(),
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
async fn served_hub() -> CoordinationHub {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(
        &coord_passport("alice"),
        "svc",
        "candidate",
        PoolVisibility::Private,
    )
    .await
    .unwrap();
    let bytes = add_capsule_bytes().await;
    let cref = h
        .add_capsule(&coord_passport("alice"), "svc", bytes, vec![])
        .await
        .unwrap();
    h.accept_recipe(&coord_passport("dev"), "svc", recipe(&cref.capsule_id))
        .await
        .unwrap();
    h.grant(
        &coord_passport("dev"),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    h
}

fn registry_with_add() -> ContractRegistry {
    let mut r = ContractRegistry::new();
    r.register("Add".to_string(), json!({ "entry_contract": "Add" }));
    r
}
fn receipts() -> Arc<dyn TBackend> {
    Arc::new(InMemoryBackend::new())
}
async fn receipt(receipts: &Arc<dyn TBackend>, key: &str) -> Option<Value> {
    receipts
        .read_as_of(RECEIPTS_STORE, key, f64::MAX)
        .await
        .unwrap()
        .map(|f| f.value)
}

const ARTIFACT: &str = r#"{ "artifact":"view","layout":"workbench",
  "actions": { "record": { "contract":"Add", "input":{"a":"$form.a","b":"$form.b"},
    "effect": { "capability_id":"IO.FrameFixture","operation":"record","scope":"write" } } } }"#;
const NO_EFFECT: &str = r#"{ "artifact":"view","layout":"workbench",
  "actions": { "record": { "contract":"Add" } } }"#;

// ── proof ─────────────────────────────────────────────────────────────────────────────────────

#[test]
fn declared_action_invokes_capsule_then_performs_effect_with_receipt() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport("write");
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        let out = bridge
            .handle_effect_action(
                ARTIFACT,
                "record",
                json!({ "a": 20, "b": 22 }),
                "idem-1",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await
            .expect("happy path");

        // acceptance 1+3: real capsule result (20+22=42) + receipt state + receipt key
        assert_eq!(
            out.invoke_result,
            json!(42),
            "the real capsule activation produced the value"
        );
        assert_eq!(out.receipt_state, WriteState::Committed);
        assert_eq!(out.receipt_key, "IO.FrameFixture:idem-1");
        // acceptance 2: a receipt fact exists in __receipts__
        assert_eq!(
            receipt(&receipts, "IO.FrameFixture:idem-1").await.unwrap()["state"],
            json!("committed")
        );
        assert_eq!(echo.call_count(), 1, "the host executor ran exactly once");
    });
}

#[test]
fn replay_same_idempotency_key_runs_effect_once() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport("write");
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        let p = || coord_passport("vendor:acme");
        bridge
            .handle_effect_action(
                ARTIFACT,
                "record",
                json!({ "a": 1, "b": 2 }),
                "idem-2",
                &p(),
                "svc",
                &hub,
            )
            .await
            .unwrap();
        bridge
            .handle_effect_action(
                ARTIFACT,
                "record",
                json!({ "a": 1, "b": 2 }),
                "idem-2",
                &p(),
                "svc",
                &hub,
            )
            .await
            .unwrap();
        assert_eq!(
            echo.call_count(),
            1,
            "the effect runs once despite the capsule re-activating"
        );
    });
}

#[test]
fn malformed_effect_refuses_before_executor_no_receipt() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport("write");
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        // the action is declared+registered (invoke runs) but it has NO effect block
        let out = bridge
            .handle_effect_action(
                NO_EFFECT,
                "record",
                json!({ "a": 1, "b": 1 }),
                "idem-3",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await;
        assert!(matches!(
            out,
            Err(FrameBindingEffectRefusal::MalformedEffect(_))
        ));
        assert_eq!(echo.call_count(), 0, "no effect executed");
        assert!(
            receipt(&receipts, "IO.FrameFixture:idem-3").await.is_none(),
            "no receipt"
        );
    });
}

#[test]
fn the_effect_needs_its_own_host_authority() {
    rt().block_on(async {
        // double authority: the vendor passport authorized invoke, but the HOST effect passport
        // lacking the write scope must be refused by the capability-IO gate (no effect, no receipt).
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport("read"); // WRONG scope for a write effect
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        let out = bridge
            .handle_effect_action(
                ARTIFACT,
                "record",
                json!({ "a": 2, "b": 2 }),
                "idem-4",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await
            .unwrap();
        assert_eq!(
            out.receipt_state,
            WriteState::Denied,
            "the effect authority gate refused"
        );
        assert_eq!(echo.call_count(), 0, "no effect ran without host authority");
        assert!(
            receipt(&receipts, "IO.FrameFixture:idem-4").await.is_none(),
            "an authority refusal writes no receipt"
        );
    });
}

#[test]
fn unknown_external_state_maps_to_receipt_state_without_panic() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        // a fake executor whose external fate is unknown (timeout) — maps to UnknownExternalState
        let fake = Arc::new(FakeWriteExecutor::new(EFFECT_CAP, WriteBehavior::Timeout));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(fake);
        let contracts = registry_with_add();
        let ep = effect_passport("write");
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        let out = bridge
            .handle_effect_action(
                ARTIFACT,
                "record",
                json!({ "a": 9, "b": 1 }),
                "idem-5",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await
            .unwrap();
        assert_eq!(
            out.receipt_state,
            WriteState::UnknownExternalState,
            "unknown fate surfaces as a state, not a panic"
        );
    });
}

#[test]
fn p17_declaration_gate_still_refuses_before_invoke() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport("write");
        let sf = SingleFlight::new();
        let bridge = FrameBindingEffectBridge {
            contracts: &contracts,
            executors: &execs,
            receipts: &receipts,
            clock: &clock(),
            effect_passport: &ep,
            single_flight: &sf,
        };

        let out = bridge
            .handle_effect_action(
                ARTIFACT,
                "not_declared",
                json!({}),
                "idem-6",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await;
        assert!(matches!(
            out,
            Err(FrameBindingEffectRefusal::Binding(
                FrameBindingRefusal::MissingDeclaration(_)
            ))
        ));
        assert_eq!(echo.call_count(), 0);
    });
}
