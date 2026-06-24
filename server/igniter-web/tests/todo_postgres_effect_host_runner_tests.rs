//! igniter-web/tests/todo_postgres_effect_host_runner_tests.rs — LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9
//!
//! Closes the P8 gap: the app's typed `WriteIntent` flows through the FULL `MachineEffectHost` contour
//! (NOT a direct `run_write_effect`), and the FINAL capability payload IS that typed intent — accepted by
//! `PostgresWriteIntent::from_args`, committed with a receipt, replay-safe.
//!
//!   POST /accounts/:id/todos  (examples/todo_postgres_app, ZERO app Rust)
//!     -> InvokeEffect { target: "todo-create", input: <WriteIntent>, idempotency_key }
//!     -> MachineEffectHost target binding (todo-create -> "/w")
//!     -> machine ingress + a SHAPING capsule `ShapeTodoWrite` that re-emits the intent as its output
//!     -> bridge wraps it: payload = { intent: <WriteIntent>, correlation_id }
//!     -> typed `PostgresWriteExecutor` (over a FAKE adapter) unwraps `intent` -> from_args -> commit
//!     -> committed machine receipt; replay same key -> NO second business mutation
//!
//! The P8 diagnosis CORRECTED here: the bridge does NOT mask the intent behind `{code}` — that was only the
//! generic placeholder capsule. With a shaping capsule, the capsule OUTPUT carries the typed intent, and the
//! bridge envelopes it under `intent` (`ingress.rs:640-645`); a thin executor decorator unwraps that one key.
//!
//! Fake adapter (no DB) — this card is about the HOST CONTOUR, not local DDL. Gated `--features machine`.
#![cfg(feature = "machine")]

use async_trait::async_trait;
use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    CapabilityExecutor, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome,
    EffectRequest,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_write::{
    FakePostgresWriteAdapter, FakeWriteBehavior, PostgresWriteExecutor, PostgresWritePolicy,
};
use igniter_machine::single_flight::SingleFlight;

use igniter_server::effect_host::MachineEffectHost;
use igniter_server::protocol::{ResponseBody, ServerApp, ServerDecision, ServerRequest};
use igniter_web::runner::build_app_from_dir;

use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const WRITE_CAP: &str = "IO.TodoWrite"; // host write capability — NEVER named by the app.

// ── the JOIN: a thin executor decorator that unwraps the bridge envelope ──────────────────────────
// The effect bridge builds the write payload as `{ intent: <capsule output>, correlation_id }`
// (`ingress.rs:640-645`). The typed `PostgresWriteExecutor` reads `from_args(&req.args)` at the TOP level,
// so this decorator lifts `req.args["intent"]` (the shaping capsule's re-emitted WriteIntent) into the
// executor's args. That is the entire join P9 proves — host authority + executor stay in Rust; the app
// names only a logical target + structured input.
struct IntentBridgeExecutor {
    cap: String,
    inner: PostgresWriteExecutor<FakePostgresWriteAdapter>,
}
#[async_trait]
impl CapabilityExecutor for IntentBridgeExecutor {
    fn capability_id(&self) -> &str {
        &self.cap
    }
    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        let intent = req
            .args
            .get("intent")
            .cloned()
            .unwrap_or_else(|| req.args.clone());
        let inner_req = EffectRequest {
            capability_id: req.capability_id.clone(),
            idempotency_key: req.idempotency_key.clone(),
            authority_ref: req.authority_ref.clone(),
            args: intent,
        };
        self.inner.execute(&inner_req).await
    }
}

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn clock() -> Arc<dyn ClockProvider> {
    Arc::new(FixedClock::new(100.0))
}
fn cpass(subject: &str, cap: &str, scopes: &[&str]) -> CapabilityPassport {
    CapabilityPassport {
        subject: subject.to_string(),
        capability_id: cap.to_string(),
        scopes: scopes.iter().map(|s| s.to_string()).collect(),
        issued_at: 0.0,
        expires_at: Some(1_000_000.0),
        revoked: false,
        evidence_digest: "sig".to_string(),
    }
}
fn vendor() -> CapabilityPassport {
    cpass(
        "vendor:acme",
        "coordination",
        &[
            "create_pool",
            "import_capsule",
            "activate_capsule",
            "grant_access",
            "accept_recipe",
            "invoke",
        ],
    )
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

/// The SHAPING capsule: re-emit the structured `WriteIntent` carried in the body as the capsule OUTPUT, so
/// the bridge's effect payload IS the typed intent (not a generic `{code}`). `values` is `Unknown` — the P7
/// open-payload sentinel — so the nested record passes through untouched.
async fn shaping_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract ShapeTodoWrite {\n  input operation : String\n  input target : String\n  input key : String\n  input values : Unknown\n  input correlation_id : String\n  compute intent = { operation: operation, target: target, key: key, values: values, correlation_id: correlation_id }\n  output intent : Unknown\n}",
        "ShapeTodoWrite",
    )
    .unwrap();
    m.checkpoint_bytes().await.unwrap()
}
fn policy() -> DuplicatePolicy {
    DuplicatePolicy {
        mode: "dedup_strict".into(),
        key_header: "idempotency-key".into(),
        max_fresh: 0,
        after_limit: "dedup_last".into(),
        seed_field: "attempt".into(),
        variant_payload: false,
        require_key: true,
    }
}
fn recipe(digest: &str, n: u32) -> ServiceRecipe {
    ServiceRecipe {
        recipe_id: "r1".into(),
        capsule_digest: digest.into(),
        entry_contract: "ShapeTodoWrite".into(),
        input_schema_digest: None,
        capability_bindings: vec![],
        required_scopes: vec!["invoke".into()],
        receipt_policy: "audit".into(),
        retry_policy_ref: None,
        pool_sizing: n,
        created_by: "alice".into(),
        accepted_by: None,
        accepted_at: None,
        duplicate_policy: Some(policy()),
    }
}
async fn prod(n: usize) -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = shaping_capsule_bytes().await;
    let mut digest = String::new();
    for _ in 0..n {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &cpass("dev", "coordination", &["accept_recipe"]),
        "svc",
        recipe(&digest, n as u32),
    )
    .await
    .unwrap();
    h.grant(
        &cpass("dev", "coordination", &["grant_access"]),
        "svc",
        "vendor:acme",
        PoolRight::ActivateCapsule,
    )
    .await
    .unwrap();
    let mut r = IngressRouter::new();
    r.route("/w", "svc");
    r.token("vtok", vendor());
    (h, r)
}

struct EffectState {
    adapter: Arc<FakePostgresWriteAdapter>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}
fn write_policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new()
        .allow_target("todos")
        .allow_ops(&["insert", "upsert"])
}
fn effect_state() -> EffectState {
    let adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let inner = PostgresWriteExecutor::new(WRITE_CAP, adapter.clone(), write_policy());
    let exec = Arc::new(IntentBridgeExecutor {
        cap: WRITE_CAP.into(),
        inner,
    });
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    EffectState {
        adapter,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", WRITE_CAP, &["write"]),
        sf: SingleFlight::new(),
    }
}
fn cfg(s: &EffectState) -> EffectBridgeConfig<'_> {
    EffectBridgeConfig {
        registry: &s.registry,
        receipts: &s.receipts,
        effect_clock: &s.eclock,
        effect_passport: &s.ep,
        single_flight: &s.sf,
        capability_id: WRITE_CAP.into(),
        operation: "write_record".into(),
        scope: "write".into(),
    }
}
fn effect_host<'a>(
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(router, hub, cfg);
    eh.bind_target("todo-create", "/w"); // INFRA binding (host authority), not app routing.
    eh.bind_target("todo-done", "/w");
    eh
}
fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}
fn build_app() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&app_dir())
        .expect("build examples/todo_postgres_app (zero authored Rust)")
        .0
}
fn app_request(method: &str, path: &str, idem_key: Option<&str>) -> ServerRequest {
    // P45: create uses the object body (legacy string removed); done/GET ignore the body.
    let mut req = ServerRequest::new(method, path, json!({"title": "Buy milk"}));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = idem_key.map(|k| k.to_string());
    req
}
async fn execute(
    eh: &MachineEffectHost<'_>,
    req: &ServerRequest,
    decision: ServerDecision,
) -> (u16, Value, bool) {
    match decision {
        ServerDecision::InvokeEffect {
            target,
            input,
            correlation_id,
            idempotency_key,
        } => {
            let resp = eh
                .run_invoke_effect(req, &target, &input, correlation_id, idempotency_key)
                .await;
            let body = match resp.body {
                ResponseBody::Json(v) => v,
                _ => Value::Null,
            };
            (resp.status, body, true)
        }
        ServerDecision::Respond { response } => {
            let body = match response.body {
                ResponseBody::Json(v) => v,
                _ => Value::Null,
            };
            (response.status, body, false)
        }
        other => panic!("unexpected decision: {other:?}"),
    }
}

// ── 1: the app's typed WriteIntent flows THROUGH MachineEffectHost into from_args + a committed receipt ─

#[test]
fn typed_write_flows_through_machine_host() {
    let app = build_app();
    let req = app_request("POST", "/accounts/acct-7/todos", Some("evt-r1"));
    let decision = app.call(req.clone()); // sync VM dispatch OUTSIDE the runtime (P4 nesting).
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, body, executed) = execute(&eh, &req, decision).await;

        assert!(
            executed,
            "keyed create → final InvokeEffect, executed through the host"
        );
        assert_eq!(status, 200, "committed effect → 200, body={body}");
        assert_eq!(body["status"], json!("committed"));
        // the FINAL capability payload was the TYPED WriteIntent — from_args parsed target/key from it
        // (the committed result echoes the intent's target/key).
        assert_eq!(
            body["result"]["target"],
            json!("todos"),
            "from_args read the app intent's target"
        );
        assert!(
            body["result"]["key"].as_str().is_some(),
            "from_args read the app intent's key"
        );
        // exactly one real (fake) transaction + one business row + one PG-side receipt.
        assert_eq!(st.adapter.attempts(), 1);
        assert_eq!(
            st.adapter.business_row_count(),
            1,
            "one business row via the host contour"
        );
        assert_eq!(
            st.adapter.effect_receipt_count(),
            1,
            "one PG-side effect receipt"
        );
        // executed response carries no capability identity.
        assert!(body.get("capability_id").is_none());
        assert!(body.get("scope").is_none());
    });
}

// ── 2: replay with the SAME idempotency key → no second business mutation ──────────────────────────

#[test]
fn replay_same_key_no_second_mutation() {
    let app = build_app();
    let req = app_request("POST", "/accounts/acct-7/todos", Some("evt-r2"));
    let d1 = app.call(req.clone());
    let d2 = app.call(req.clone()); // replay: same key, deterministic same decision.
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, _b1, _e1) = execute(&eh, &req, d1).await;
        assert_eq!(s1, 200);
        let (s2, _b2, _e2) = execute(&eh, &req, d2).await;
        assert_eq!(s2, 200, "replay still reports 200");
        assert_eq!(
            st.adapter.attempts(),
            1,
            "same key → machine dedup keeps it at one mutation"
        );
        assert_eq!(
            st.adapter.business_row_count(),
            1,
            "still exactly one business row"
        );
    });
}

// ── 3: keyless mutation stays app-owned 400, BEFORE any host execution ────────────────────────────

#[test]
fn keyless_mutation_is_app_owned_400_before_host() {
    let app = build_app();
    let req = app_request("POST", "/accounts/acct-7/todos", None); // no idempotency key.
    let decision = app.call(req.clone());
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, _body, executed) = execute(&eh, &req, decision).await;
        assert!(
            !executed,
            "keyless → app Respond, not an executed InvokeEffect"
        );
        assert_eq!(status, 400, "keyless mutation is an app-owned 400");
        assert_eq!(
            st.adapter.attempts(),
            0,
            "no host execution before the app's guard"
        );
    });
}

// ── 4: the authored app names no DB / effect identity (host authority stays in Rust) ──────────────

#[test]
fn app_names_no_authority_surface() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();
    let routes = std::fs::read_to_string(app_dir().join("routes.igweb")).unwrap();
    let strip = |s: &str| {
        s.lines()
            .map(|l| l.split("--").next().unwrap_or(""))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let code = format!("{}\n{}", strip(&handlers), strip(&routes)).to_lowercase();
    for forbidden in [
        "capability_id",
        "io.todowrite",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "secret",
        "[effects]",
        "select ",
        "insert into",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
    assert!(handlers.contains("\"todo-create\"")); // only logical targets.
}
