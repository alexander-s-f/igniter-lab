//! LAB-FRAME-BINDING-CONSOLE-E2E-P20 — the full lab loop (no live IO): a declared action runs the
//! P18 host bridge (real capsule invoke + fake capability-IO effect → receipt), the host serializes
//! the result into a plain `HostActionRecord` JSON, and the machine-free console renders that
//! action/receipt lineage. The console consumes DATA only; this is a host-side (dev-dep) integration
//! test — console/ui-kit never depend on the machine.

use igniter_console::Console;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutorRegistry, CapabilityPassport, EchoCapabilityExecutor,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, PoolRight, PoolVisibility,
    ServiceRecipe,
};
use igniter_machine::frame_binding_effect::FrameBindingEffectBridge;
use igniter_machine::machine::IgniterMachine;
use igniter_machine::registry::ContractRegistry;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

const EFFECT_CAP: &str = "IO.FrameFixture";
// the bound action artifact (P18 shape) + the console's own (unbound) workbench artifact
const ARTIFACT: &str = r#"{ "artifact":"view","layout":"workbench",
  "actions": { "record": { "contract":"Add", "input":{"a":"$form.a","b":"$form.b"},
    "effect": { "capability_id":"IO.FrameFixture","operation":"record","scope":"write" } } } }"#;
const LEAD_REVIEW: &str =
    include_str!("../../frame-ui/igniter-ui-kit/web/lead_review.view.json");

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
fn coord_passport(s: &str) -> CapabilityPassport {
    CapabilityPassport {
        subject: s.into(),
        capability_id: "coordination".into(),
        scopes: SCOPES.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1e6),
        revoked: false,
        evidence_digest: "sig".into(),
    }
}
fn effect_passport() -> CapabilityPassport {
    CapabilityPassport {
        subject: "host".into(),
        capability_id: EFFECT_CAP.into(),
        scopes: vec!["write".into()],
        issued_at: 0.0,
        expires_at: Some(1e6),
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
    m.load_contract_source("contract Add { input a: Integer  input b: Integer  compute sum = a + b  output sum: Integer }", "Add").unwrap();
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
/// Console viewer click that records a frame (selects Grace in the embedded target).
fn console_with_a_frame() -> Console {
    let mut c = Console::from_artifact(LEAD_REVIEW).unwrap();
    c.click(28.0 + 106.0 / 720.0 * 576.0, 120.0 + 105.0 / 440.0 * 352.0); // select Grace → records a frame
    c
}

#[test]
fn e2e_committed_action_renders_action_and_receipt_in_console() {
    rt().block_on(async {
        // 1. host bridge: real invoke + fake effect → committed receipt
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo);
        let contracts = registry_with_add();
        let ep = effect_passport();
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
            .unwrap();
        assert_eq!(out.receipt_state, WriteState::Committed);

        // 2. serialize the bridge result → a plain HostActionRecord JSON (host-side)
        let rec = out.to_host_action_json(
            "frame-action-1",
            "record",
            "Add",
            "svc",
            "idem-1",
            "frame-corr-1",
        );
        assert_eq!(rec["effect_state"], "committed");
        assert_eq!(rec["effect_receipt_id"], "IO.FrameFixture:idem-1");
        assert!(rec["invoke_digest"]
            .as_str()
            .unwrap()
            .starts_with("blake3:"));

        // 3. feed the JSON to the machine-free console
        let mut con = console_with_a_frame();
        assert!(con.attach_action_json(&rec.to_string()));

        // 4. lineage_json carries the full action/receipt fields
        let lin: Value = serde_json::from_str(&con.lineage_json()).unwrap();
        assert_eq!(lin["host_action"]["action_name"], "record");
        assert_eq!(lin["host_action"]["contract"], "Add");
        assert_eq!(lin["host_action"]["effect_state"], "committed");
        assert_eq!(
            lin["host_action"]["effect_receipt_id"],
            "IO.FrameFixture:idem-1"
        );
        assert_eq!(lin["host_action"]["pool_id"], "svc");

        // 5. rendered SVG shows a compact action + receipt line
        let svg = con.render_svg();
        assert!(svg.contains("action: record"));
        assert!(svg.contains("receipt: committed"));
    });
}

#[test]
fn e2e_idempotent_replay_shows_one_receipt_id() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let echo = Arc::new(EchoCapabilityExecutor::new(EFFECT_CAP));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(echo.clone());
        let contracts = registry_with_add();
        let ep = effect_passport();
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
        let a = bridge
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
        let b = bridge
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
            a.receipt_key, b.receipt_key,
            "same idempotency key → same receipt id"
        );
        assert_eq!(echo.call_count(), 1);

        let mut con = console_with_a_frame();
        con.attach_action_json(
            &b.to_host_action_json("a2", "record", "Add", "svc", "idem-2", "corr-2")
                .to_string(),
        );
        let lin: Value = serde_json::from_str(&con.lineage_json()).unwrap();
        assert_eq!(
            lin["host_action"]["effect_receipt_id"],
            "IO.FrameFixture:idem-2"
        );
    });
}

#[test]
fn e2e_unknown_effect_state_renders_without_panic() {
    rt().block_on(async {
        let hub = served_hub().await;
        let receipts = receipts();
        let fake = Arc::new(FakeWriteExecutor::new(EFFECT_CAP, WriteBehavior::Timeout));
        let mut execs = CapabilityExecutorRegistry::new();
        execs.register(fake);
        let contracts = registry_with_add();
        let ep = effect_passport();
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
                "idem-3",
                &coord_passport("vendor:acme"),
                "svc",
                &hub,
            )
            .await
            .unwrap();
        assert_eq!(out.receipt_state, WriteState::UnknownExternalState);

        let rec = out.to_host_action_json("a3", "record", "Add", "svc", "idem-3", "corr-3");
        assert_eq!(rec["effect_state"], "unknown_external_state");

        let mut con = console_with_a_frame();
        con.attach_action_json(&rec.to_string());
        let svg = con.render_svg(); // must not panic
        assert!(svg.contains("receipt: unknown_external_state"));
    });
}
