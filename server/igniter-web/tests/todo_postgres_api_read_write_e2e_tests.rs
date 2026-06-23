//! igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs — LAB-TODOAPP-API-READ-WRITE-E2E-P5
//!
//! Stitches the two ADJACENT product seams proven separately (P3 read + P4 write) into ONE
//! product-shaped fake-host e2e for `examples/todo_postgres_app` (ZERO app Rust):
//!
//!   READ  : product `ListTodosByAccount` -> QueryPlan -> host fake `PostgresReadExecutor`
//!           -> rows -> product `AccountTodoIndexFromRows` -> Respond 200 (found) / 404 (empty)
//!   WRITE : authored POST route -> final `InvokeEffect` -> `MachineEffectHost` (fake write executor)
//!           -> committed receipt; replay with the same idempotency key -> exactly ONE executor mutation
//!
//! Hybrid harness: the READ half uses direct `IgniterMachine::dispatch` on the app's own contracts; the
//! WRITE half uses `build_app_from_dir` + `app.call` + the machine effect host (the app's sync `call`
//! computes the decision OUTSIDE the tokio runtime, then the effect executes inside it — see P4). NO live
//! Postgres, NO DSN/SQL/migrations, NO new `.igweb` syntax. Gated behind `--features machine`.
#![cfg(feature = "machine")]

use igniter_machine::backend::{InMemoryBackend, TBackend};
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, CapabilityPassport, EffectOutcome, EffectRequest,
    OutcomeKind, RunMode,
};
use igniter_machine::clock::{ClockProvider, FixedClock};
use igniter_machine::coordination::{
    AgentIdentity, AgentKind, AgentStatus, CoordinationHub, DuplicatePolicy, PoolRight,
    PoolVisibility, ServiceRecipe,
};
use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
use igniter_machine::machine::IgniterMachine;
use igniter_machine::postgres_read::{
    FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
};
use igniter_machine::single_flight::SingleFlight;
use igniter_machine::write::{FakeWriteExecutor, WriteBehavior};

use igniter_server::effect_host::MachineEffectHost;
use igniter_server::protocol::{ResponseBody, ServerApp, ServerDecision, ServerRequest};
use igniter_web::runner::build_app_from_dir;

use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;

const READ_CAP: &str = "IO.PostgresRead"; // host read capability — never named by the app.
const WRITE_CAP: &str = "IO.TodoWrite"; // host write capability — never named by the app.

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}
fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

// ── READ harness (from P3) ───────────────────────────────────────────────────────────────────────

/// Load the prelude + the PRODUCT app's authored `todo_handlers.ig` so its query + continuation
/// contracts can be dispatched directly.
fn load_app_contracts() -> IgniterMachine {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("igweb_e2e_p5_{}_{}", std::process::id(), stamp));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    std::fs::write(&pl, igniter_compiler::igweb::PRELUDE_SOURCE).unwrap();
    let handlers = app_dir().join("todo_handlers.ig");
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_program(
        &[
            pl.to_string_lossy().to_string(),
            handlers.to_string_lossy().to_string(),
        ],
        "ListTodosByAccount",
    )
    .expect("load todo_postgres_app contracts");
    m
}

fn todos_policy(cap: i64) -> PostgresReadPolicy {
    PostgresReadPolicy::new(cap)
        .allow_ops(&["select"])
        .allow_source("todos", &["id", "account_id", "title", "done"])
}
fn todo_rows() -> Vec<Value> {
    vec![
        json!({"id": "todo-1", "account_id": "acct-7", "title": "Buy milk", "done": false}),
        json!({"id": "todo-2", "account_id": "acct-7", "title": "Write spec", "done": true}),
    ]
}
fn min_req() -> Value {
    json!({"method": "GET", "path": "/accounts/acct-7/todos", "body": "",
           "correlation_id": "", "idempotency_key": ""})
}
async fn host_read(
    plan: &Value,
    policy: PostgresReadPolicy,
    adapter: Arc<FakePostgresAdapter>,
) -> EffectOutcome {
    let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy));
    let mut reg = CapabilityExecutorRegistry::new();
    reg.register(exec);
    let store: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let req = EffectRequest {
        capability_id: READ_CAP.to_string(),
        idempotency_key: "rq".to_string(),
        authority_ref: Some("passport:test".to_string()),
        args: plan.clone(),
    };
    run_effect(&reg, &store, &req, RunMode::Live).await.unwrap()
}

// ── WRITE harness (from P4) ──────────────────────────────────────────────────────────────────────

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
async fn capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract WriteRecord { input attempt: Integer  compute code = attempt  output code: Integer }",
        "WriteRecord",
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
    let exec = Arc::new(FakeWriteExecutor::new(WRITE_CAP, WriteBehavior::Commit));
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec.clone());
    EffectState {
        exec,
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
    eh.bind_target("todo-create", "/w");
    eh.bind_target("todo-done", "/w");
    eh
}
fn build_app() -> Arc<dyn ServerApp + Send + Sync> {
    build_app_from_dir(&app_dir())
        .expect("build examples/todo_postgres_app (zero authored Rust)")
        .0
}
fn app_request(method: &str, path: &str, idem_key: Option<&str>) -> ServerRequest {
    // P18: create body must be a JSON string literal (the title); done ignores the body.
    let mut req = ServerRequest::new(method, path, json!("Buy milk"));
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

// ── THE e2e: one product contour stitching read + write ──────────────────────────────────────────

#[test]
fn product_read_then_write_e2e() {
    let app = build_app();
    // WRITE decisions are computed by the sync VM BEFORE entering the runtime (P4 nesting constraint).
    let create_req = app_request("POST", "/accounts/acct-7/todos", Some("evt-create-1"));
    let create_d1 = app.call(create_req.clone());
    let create_d2 = app.call(create_req.clone()); // replay: same key, deterministic same decision.

    rt().block_on(async move {
        // ── READ: found path → app-owned 200 carrying the rows ──
        let m = load_app_contracts();
        let plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-7"}))
            .await
            .unwrap();
        assert_eq!(
            plan["source"],
            json!("todos"),
            "app QueryPlan, not Rust SQL"
        );
        assert_eq!(plan["op"], json!("select"));
        assert_eq!(
            plan["filters"][0]["field"],
            json!("account_id"),
            "host gate keys on app filter"
        );

        let adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", todo_rows()));
        let out = host_read(&plan, todos_policy(100), adapter.clone()).await;
        assert_eq!(out.kind, OutcomeKind::Succeeded);
        assert_eq!(out.result["count"], json!(2));
        assert_eq!(adapter.query_count(), 1, "host adapter ran once");

        let rows_json = serde_json::to_string(&out.result["rows"]).unwrap();
        let found = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req(), "rows_json": rows_json}),
            )
            .await
            .unwrap();
        assert_eq!(found["__arm"], json!("Respond"));
        assert_eq!(found["status"], json!(200), "found rows → app 200");
        assert!(found["body"].as_str().unwrap().contains("todo-1"));

        // ── READ: empty path → app-owned 404 (product decision, not infra failure) ──
        let empty_plan = m
            .dispatch("ListTodosByAccount", json!({"account_id": "acct-none"}))
            .await
            .unwrap();
        let empty_adapter = Arc::new(FakePostgresAdapter::new()); // allowlisted source, no rows.
        let empty_out = host_read(&empty_plan, todos_policy(100), empty_adapter).await;
        assert_eq!(empty_out.result["count"], json!(0));
        let empty_rows = serde_json::to_string(&empty_out.result["rows"]).unwrap();
        assert_eq!(empty_rows, "[]");
        let not_found = m
            .dispatch(
                "AccountTodoIndexFromRows",
                json!({"req": min_req(), "rows_json": empty_rows}),
            )
            .await
            .unwrap();
        assert_eq!(
            not_found["status"],
            json!(404),
            "empty rows → app 404, not infra error"
        );

        // ── WRITE: keyed create EXECUTES through the machine effect host → committed receipt ──
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let (s1, body1, executed1) = execute(&eh, &create_req, create_d1).await;
        assert!(executed1, "keyed create → final InvokeEffect, executed");
        assert_eq!(s1, 200, "committed effect → 200, body={body1}");
        assert_eq!(body1["status"], json!("committed"));
        assert_eq!(st.exec.attempts(), 1, "exactly one write effect performed");
        // executed response carries no capability identity.
        assert!(body1.get("capability_id").is_none());
        assert!(body1.get("scope").is_none());
        assert!(body1.get("operation").is_none());

        // ── WRITE: replay with the SAME idempotency key → still exactly ONE executor mutation ──
        let (s2, _b2, _e2) = execute(&eh, &create_req, create_d2).await;
        assert_eq!(s2, 200);
        assert_eq!(
            st.exec.attempts(),
            1,
            "same idempotency key → machine dedup keeps it at one mutation"
        );
    });
}

// ── App authority hygiene: the authored product app names no DB/effect identity ──────────────────

#[test]
fn product_app_has_no_authority_surface() {
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
        "select ",
        "insert into",
        "where ",
        "capability_id",
        "io.postgres",
        "io.todowrite",
        "passport",
        "dsn",
        "postgres://",
        "secret",
        "[effects]",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
    // the only DB-ish token is the logical `source: "todos"`; effects name only logical targets.
    assert!(handlers.contains("source: \"todos\""));
    assert!(handlers.contains("\"todo-create\"") && handlers.contains("\"todo-done\""));
}
