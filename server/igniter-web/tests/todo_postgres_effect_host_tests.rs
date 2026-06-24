//! igniter-web/tests/todo_postgres_effect_host_tests.rs — LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4
//!
//! The smallest live execution bridge: the authored `examples/todo_postgres_app` (ZERO app Rust) runs its
//! FINAL mutating `InvokeEffect` decisions through the EXISTING `igniter-server` `MachineEffectHost`
//! contour (→ `IngressRouter::handle_effect` → CoordinationHub → fake write executor → machine receipt) —
//! i.e. keyed writes are EXECUTED, not merely observed. The host binding (`target → machine route`) lives
//! entirely in this harness; the app names only logical targets (`todo-create`/`todo-done`). No live
//! Postgres, no DSN, no read guards, no `[effects]` in the app manifest. Gated behind `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};

use igniter_server::effect_host::MachineEffectHost;
use igniter_server::protocol::{ResponseBody, ServerApp, ServerDecision, ServerRequest};

use igniter_web::runner::build_app_from_dir;

use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const CAP: &str = "IO.TodoWrite"; // neutral host capability — never named by the app.

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
/// Neutral pool capsule. Reads only the dedup-injected `attempt` (the app's `{input}` body is ignored by
/// the service contract — the effect side keys on the app's idempotency key).
async fn capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract WriteRecord { input attempt: Integer  compute code = attempt  output code: Integer }",
        "WriteRecord",
    )
    .unwrap();
    m.checkpoint_bytes().await.unwrap()
}
/// Duplicate policy keyed on the app's `idempotency-key` (what `run_invoke_effect` injects from the
/// decision), so the machine dedup gate keys on exactly what the IgWeb route required.
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
        entry_contract: "WriteRecord".into(),
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
/// Production pool + accepted recipe + granted vendor + ingress route `/w` → pool `svc` + token `vtok`.
async fn prod(n: usize) -> (CoordinationHub, IngressRouter) {
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let mut h = CoordinationHub::new(audit, clock());
    register(&mut h, "alice", AgentKind::Agent).await;
    register(&mut h, "dev", AgentKind::Developer).await;
    register(&mut h, "vendor:acme", AgentKind::RuntimeActor).await;
    h.create_pool(&vendor(), "svc", "candidate", PoolVisibility::Private)
        .await
        .unwrap();
    let bytes = capsule_bytes().await;
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
    exec: Arc<FakeWriteExecutor>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
}
fn effect_state() -> EffectState {
    let exec = Arc::new(FakeWriteExecutor::new(CAP, WriteBehavior::Commit));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec.clone());
    EffectState {
        exec,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", CAP, &["write"]),
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
        capability_id: CAP.into(),
        operation: "write_record".into(),
        scope: "write".into(),
    }
}
/// Host with the INFRA bindings the app's logical targets map to (both → the one fake write route `/w`).
fn effect_host<'a>(
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(router, hub, cfg);
    eh.bind_target("todo-create", "/w");
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

/// Build the request the way the runner would (the app reads `idempotency_key` from the field; the
/// machine ingress passport `Authorization: Bearer vtok` rides in the headers — the app never sets/reads
/// it).
fn app_request(method: &str, path: &str, idem_key: Option<&str>) -> ServerRequest {
    // P45: create uses the object body (legacy string removed); done/GET ignore the body.
    let mut req = ServerRequest::new(method, path, json!({"title": "Buy milk"}));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = idem_key.map(|k| k.to_string());
    req
}

/// Execute one already-computed app decision through `MachineEffectHost`. A final `InvokeEffect` is
/// EXECUTED (the write contour); any other decision (e.g. the 400 guard `Respond`) is NOT — returns
/// `(status, body, executed)`. NOTE: the app's decision is computed by `app.call()` BEFORE entering the
/// tokio runtime — `IgWebServerApp::call` does an internal `block_on`, which cannot nest inside the async
/// effect host (see the proof doc's honest limitation about the full socket serve loop).
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

// ── 1: keyed create EXECUTES through the machine host (not just observed 202) ─────────────────────

#[test]
fn keyed_create_executes_via_machine_host() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos", Some("evt-1"));
    let decision = app.call(req.clone()); // sync VM dispatch — OUTSIDE the runtime.
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, body, executed) = execute(&eh, &req, decision).await;

        assert!(
            executed,
            "a keyed mutating route produces a final InvokeEffect"
        );
        assert_eq!(status, 200, "committed effect → 200, body={body}");
        assert_eq!(body["status"], json!("committed"));
        assert_eq!(st.exec.attempts(), 1, "exactly one write effect performed");
        // the executed response carries NO capability identity.
        assert!(body.get("capability_id").is_none());
        assert!(body.get("scope").is_none());
        assert!(body.get("operation").is_none());
    });
}

// ── 1b: create carries the object-body title into the structured intent ───────────────────────────

#[test]
fn create_carries_object_body_title() {
    let app = build_app();
    // P45: the object body `{ "title": … }` is the only accepted create shape; its title flows to the intent.
    let mut req = ServerRequest::new("POST", "/accounts/7/todos", json!({"title": "Buy milk"}));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = Some("evt-body".to_string());

    match app.call(req) {
        ServerDecision::InvokeEffect { input, .. } => {
            assert_eq!(
                input["values"]["title"],
                json!("Buy milk"),
                "P16: the structured intent title carries the request body"
            );
            assert_eq!(input["values"]["account_id"], json!("7"));
            assert_eq!(input["values"]["done"], json!("false"));
        }
        other => panic!("expected InvokeEffect for create, got {other:?}"),
    }
}

// ── 2: keyed done EXECUTES through the machine host ───────────────────────────────────────────────

#[test]
fn keyed_done_executes_via_machine_host() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos/42/done", Some("evt-2"));
    let decision = app.call(req.clone());

    // P15: the done effect reaches the host with the BUSINESS key = route todo_id ("42"), the effect
    // idempotency key = the request key ("evt-2"), and op "upsert"; account_id is carried for the FK.
    if let ServerDecision::InvokeEffect {
        ref target,
        ref input,
        ref idempotency_key,
        ..
    } = decision
    {
        assert_eq!(target, "todo-done");
        assert_eq!(input["key"], json!("42"), "business key = route todo_id");
        assert_eq!(input["operation"], json!("upsert"));
        assert_eq!(input["values"]["account_id"], json!("7"));
        assert_eq!(input["values"]["done"], json!("true"));
        assert_eq!(
            idempotency_key.as_deref(),
            Some("evt-2"),
            "effect idempotency key = request key, not the business key"
        );
    } else {
        panic!("expected InvokeEffect for done, got {decision:?}");
    }

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, body, executed) = execute(&eh, &req, decision).await;

        assert!(executed);
        assert_eq!(status, 200, "body={body}");
        assert_eq!(body["status"], json!("committed"));
        assert_eq!(st.exec.attempts(), 1);
    });
}

// ── 3: keyless mutating request → 400 BEFORE the effect host; executor untouched ──────────────────

#[test]
fn keyless_create_400_before_host() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos", None);
    let decision = app.call(req.clone());
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, _b, executed) = execute(&eh, &req, decision).await;

        assert!(!executed, "keyless request never reaches the effect host");
        assert_eq!(status, 400, "keyless idempotency guard fires in the app");
        assert_eq!(st.exec.attempts(), 0, "executor untouched");
    });
}

// ── 4: replay with the SAME idempotency key performs exactly one effect ───────────────────────────

#[test]
fn replay_same_key_one_effect() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos", Some("evt-9"));
    // deterministic: compute the same effect intent twice (both off-runtime).
    let d1 = app.call(req.clone());
    let d2 = app.call(req.clone());
    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, _b1, _e1) = execute(&eh, &req, d1).await;
        let (s2, _b2, _e2) = execute(&eh, &req, d2).await;

        assert_eq!(s1, 200);
        assert_eq!(s2, 200);
        assert_eq!(
            st.exec.attempts(),
            1,
            "same idempotency key → exactly one write effect (machine dedup)"
        );
    });
}

// ── 5: the app's decision carries no capability identity (structural) ─────────────────────────────

#[test]
fn app_decision_carries_no_capability_identity() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos", Some("evt-x"));
    match app.call(req) {
        ServerDecision::InvokeEffect {
            target,
            idempotency_key,
            ..
        } => {
            // the InvokeEffect variant structurally has ONLY target/input/correlation_id/idempotency_key;
            // there is no field for capability_id/operation/scope to smuggle.
            assert_eq!(target, "todo-create");
            assert_eq!(idempotency_key.as_deref(), Some("evt-x"));
        }
        other => panic!("expected InvokeEffect, got {other:?}"),
    }
}

// ── 7 (P19): same key + DIFFERENT body → 409 conflict, no second effect ───────────────────────────
//
// The Todo duplicate policy is `dedup_strict` + `variant_payload: false`. A client bug that reuses one
// idempotency key with a different create body is caught at the ingress dedup gate (payload-digest
// mismatch → `DuplicateDecision::Conflict`) and returns **409** BEFORE any replica is activated — never
// a silent success, never a second mutation. The create body is the canonical object `{ "title": … }`
// (P45: the legacy string body was removed), so two different titles produce two different body digests.

fn titled_create(account: &str, idem_key: &str, title: &str) -> ServerRequest {
    let mut req =
        ServerRequest::new("POST", &format!("/accounts/{account}/todos"), json!({ "title": title }));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = Some(idem_key.to_string());
    req
}

#[test]
fn create_same_key_different_body_conflicts_no_second_effect() {
    let app = build_app();
    // SAME idempotency key, DIFFERENT title (different body → different payload digest).
    let r1 = titled_create("7", "evt-create-conflict", "Buy milk");
    let r2 = titled_create("7", "evt-create-conflict", "Buy bread");
    let d1 = app.call(r1.clone());
    let d2 = app.call(r2.clone());

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, _b1, e1) = execute(&eh, &r1, d1).await;
        let (s2, b2, e2) = execute(&eh, &r2, d2).await;

        assert!(e1 && e2, "both keyed creates reach the effect host");
        assert_eq!(s1, 200, "first create commits → 200");
        assert_eq!(
            s2, 409,
            "same key + different body → 409 conflict, body={b2}"
        );
        assert_eq!(b2["error"], json!("conflict"), "distinct conflict body");
        assert_eq!(
            st.exec.attempts(),
            1,
            "conflict is refused before activation → exactly one effect"
        );
        assert_eq!(st.exec.applied_count(), 1, "no second mutation applied");
    });
}

#[test]
fn create_same_key_same_body_dedup_no_second_effect() {
    let app = build_app();
    // SAME idempotency key + SAME title → dedup replay (no conflict, no second effect).
    let r1 = titled_create("7", "evt-create-same", "Buy milk");
    let r2 = titled_create("7", "evt-create-same", "Buy milk");
    let d1 = app.call(r1.clone());
    let d2 = app.call(r2.clone());

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, _b1, _e1) = execute(&eh, &r1, d1).await;
        let (s2, _b2, _e2) = execute(&eh, &r2, d2).await;

        assert_eq!(s1, 200, "first create commits");
        assert_eq!(s2, 200, "same key + same body → dedup replay, still 200");
        assert_eq!(st.exec.attempts(), 1, "same payload → exactly one effect");
    });
}

// ── 8 (P19): done — same key + DIFFERENT todo_id → 409 conflict, no wrong-row mutation ────────────
//
// The done effect's business key is the route `todo_id` (carried in the intent `key`). Reusing one
// idempotency key against a different `todo_id` changes the intent body → payload-digest mismatch →
// 409 before activation: the WRONG row is never marked done (the executor is never reached a 2nd time).

#[test]
fn done_same_key_different_todo_id_conflicts_no_wrong_mutation() {
    let app = build_app();
    // SAME idempotency key, DIFFERENT route todo_id (42 vs 43) → different intent key → different body.
    let r1 = app_request(
        "POST",
        "/accounts/7/todos/42/done",
        Some("evt-done-conflict"),
    );
    let r2 = app_request(
        "POST",
        "/accounts/7/todos/43/done",
        Some("evt-done-conflict"),
    );
    let d1 = app.call(r1.clone());
    let d2 = app.call(r2.clone());

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, _b1, e1) = execute(&eh, &r1, d1).await;
        let (s2, b2, e2) = execute(&eh, &r2, d2).await;

        assert!(e1 && e2, "both keyed dones reach the effect host");
        assert_eq!(s1, 200, "first done commits → 200");
        assert_eq!(
            s2, 409,
            "same key + different todo_id → 409 conflict, body={b2}"
        );
        assert_eq!(
            st.exec.attempts(),
            1,
            "the wrong row's done is refused before activation → exactly one effect"
        );
    });
}

// ── P35: an object body MISSING `title` is rejected (400) BEFORE the machine effect host ───────────
//
// The body-contract guard lives in the app handler (`ResolveCreateTitle` → empty title → 400), so a
// create whose object body has no usable `title` produces a `Respond { 400 }` decision — never an
// `InvokeEffect`. It therefore never reaches `MachineEffectHost`: the write executor is untouched.

#[test]
fn titleless_object_create_body_rejected_before_effect_host() {
    let app = build_app();
    // Keyed create with a JSON OBJECT body that carries no `title` field.
    let mut req = ServerRequest::new("POST", "/accounts/7/todos", json!({"note": "x"}));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = Some("evt-bad-body".to_string());
    let decision = app.call(req.clone());

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, _b, executed) = execute(&eh, &req, decision).await;

        assert!(!executed, "a rejected body never reaches the effect host");
        assert_eq!(status, 400, "object body missing title → product-owned 400");
        assert_eq!(st.exec.attempts(), 0, "write executor untouched");
    });
}

// ── P35: the preferred v1 OBJECT body `{ "title": … }` EXECUTES through the machine host ───────────

#[test]
fn object_create_body_executes_via_machine_host() {
    let app = build_app();
    // Keyed create with the v1 object body — title carried as a JSON object field.
    let mut req = ServerRequest::new("POST", "/accounts/7/todos", json!({"title": "Buy milk"}));
    req.headers
        .insert("authorization".to_string(), "Bearer vtok".to_string());
    req.idempotency_key = Some("evt-obj-1".to_string());
    let decision = app.call(req.clone());

    // The decision carries the title extracted from the object body into the structured intent.
    if let ServerDecision::InvokeEffect { ref input, .. } = decision {
        assert_eq!(
            input["values"]["title"],
            json!("Buy milk"),
            "P35: object-body title flows into the write intent values"
        );
    } else {
        panic!("expected InvokeEffect for object-body create, got {decision:?}");
    }

    rt().block_on(async move {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (status, body, executed) = execute(&eh, &req, decision).await;

        assert!(executed, "object-body create produces a final InvokeEffect");
        assert_eq!(status, 200, "committed effect → 200, body={body}");
        assert_eq!(st.exec.attempts(), 1, "exactly one write effect performed");
    });
}

// ── 6 (P7): the app's decision carries STRUCTURED `input` — a clean JSON object, not a string wrapper ─

#[test]
fn structured_input_crosses_as_clean_object() {
    let app = build_app();
    let req = app_request("POST", "/accounts/7/todos", Some("evt-1"));
    match app.call(req) {
        ServerDecision::InvokeEffect {
            input,
            idempotency_key,
            ..
        } => {
            // P7: `input` is the WHOLE structured WriteIntent — a JSON object, NOT `{"input": "<string>"}`.
            assert!(
                input.is_object(),
                "input crosses as a structured object: {input}"
            );
            assert!(input.get("input").is_none(), "no legacy string wrapper");
            assert_eq!(input["operation"], json!("insert"));
            assert_eq!(input["target"], json!("todos"));
            // nested record preserved + tag-free (plain records carry no variant discriminants).
            assert!(input["values"].is_object(), "nested `values` preserved");
            assert_eq!(input["values"]["done"], json!("false"));
            let s = input.to_string();
            assert!(
                !s.contains("__arm") && !s.contains("__variant"),
                "tag-free: {s}"
            );
            // idempotency stays its OWN field, never folded into `input`.
            assert_eq!(idempotency_key.as_deref(), Some("evt-1"));
        }
        other => panic!("expected InvokeEffect, got {other:?}"),
    }
}
