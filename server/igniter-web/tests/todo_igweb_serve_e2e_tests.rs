//! todo_igweb_serve_e2e_tests.rs — LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11
//!
//! Proves `examples/todo_postgres_app` through the `igweb-serve --host-config` binary path.
//! Distinguishing feature from LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10:
//!   - P10: READ_CAP, WRITE_CAP, policy, and targets were hardcoded test constants.
//!   - P11: all capability ids, policy allowlists, and effect target→route bindings are
//!     derived from a temporary `host.toml` via `host_binding::{read_policy_binding,
//!     write_binding_plan, build_staged_read_host_with_adapter}`.
//!
//! Uses extracted binary core (same code paths as `run_machine_mode` after P23); does NOT
//! spawn a subprocess. The closing report documents this distinction explicitly.
//!
//! All adapters are fake. No live Postgres. Gated `--features machine`.
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
use igniter_machine::postgres_read::FakePostgresAdapter;
use igniter_machine::postgres_write::{
    FakePostgresWriteAdapter, FakeWriteBehavior, PostgresWriteExecutor,
};
use igniter_machine::single_flight::SingleFlight;
use igniter_server::effect_host::MachineEffectHost;
use igniter_server::serving_loop::ServingPolicy;
use igniter_web::host_binding::{
    build_staged_read_host_with_adapter, read_policy_binding, write_binding_plan,
};
use igniter_web::host_config::{load_host_config, resolve_host_config};
use igniter_web::machine_runner;
use igniter_web::runner::build_loaded_app_from_dir;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

// ── app dir ───────────────────────────────────────────────────────────────────────────────────────

fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

// ── IntentBridgeExecutor ──────────────────────────────────────────────────────────────────────────

/// Thin decorator that unwraps `{ intent: <WriteIntent> }` bridge envelope before forwarding to
/// `PostgresWriteExecutor`. Same shape as in async_machine_runner_tests and P10 smoke tests.
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
        self.inner
            .execute(&EffectRequest {
                capability_id: req.capability_id.clone(),
                idempotency_key: req.idempotency_key.clone(),
                authority_ref: req.authority_ref.clone(),
                args: intent,
            })
            .await
    }
}

// ── coordination hub scaffolding (same shape as P10 / async_machine_runner_tests) ─────────────────

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

async fn shaping_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract ShapeTodoWrite {\n\
         input operation : String\n  input target : String\n  input key : String\n\
         input values : Unknown\n  input correlation_id : String\n\
         compute intent = { operation: operation, target: target, key: key, values: values, \
         correlation_id: correlation_id }\n\
         output intent : Unknown\n}",
        "ShapeTodoWrite",
    )
    .unwrap();
    m.checkpoint_bytes().await.unwrap()
}

fn dup_policy() -> DuplicatePolicy {
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

fn service_recipe(digest: &str, n: u32) -> ServiceRecipe {
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
        duplicate_policy: Some(dup_policy()),
    }
}

/// Build the coordination hub + ingress router (3 shaping capsules, recipe accepted, vtok wired).
/// The ingress route `/w` → pool `"svc"` is wired here; target→route binding comes from host.toml
/// via `write_binding_plan`.
async fn build_coordination() -> (CoordinationHub, IngressRouter) {
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
    for _ in 0..3 {
        digest = h
            .add_capsule(&vendor(), "svc", bytes.clone(), vec![])
            .await
            .unwrap()
            .capsule_id;
    }
    h.accept_recipe(
        &cpass("dev", "coordination", &["accept_recipe"]),
        "svc",
        service_recipe(&digest, 3),
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

// ── host.toml file builder ────────────────────────────────────────────────────────────────────────

/// Write a temporary `host.toml` with full read/write/effect config and set the required env vars.
/// Returns (path, read_var_name, write_var_name). Caller must `remove_var` after the test.
fn write_host_toml(stamp: u128) -> (PathBuf, String, String) {
    let read_var = format!("IGWEB_P11_READ_DSN_{stamp}");
    let write_var = format!("IGWEB_P11_WRITE_DSN_{stamp}");
    // Set fake DSN values so resolve_host_config succeeds (value unused for fake adapters).
    std::env::set_var(&read_var, "postgres://fake-p11-read/db");
    std::env::set_var(&write_var, "postgres://fake-p11-write/db");

    let dir = std::env::temp_dir()
        .join(format!("igweb_p11_{}_{stamp}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    let toml = format!(
        "[postgres.read]\n\
         dsn_env = \"{read_var}\"\n\
         source = \"todos\"\n\
         fields = \"id,account_id,title,done\"\n\
         row_limit = \"100\"\n\
         capability = \"IO.PostgresRead\"\n\
         \n\
         [postgres.write]\n\
         dsn_env = \"{write_var}\"\n\
         targets = \"todos\"\n\
         ops = \"insert,upsert\"\n\
         capability = \"IO.TodoWrite\"\n\
         \n\
         [effects.todo-create]\n\
         route = \"/w\"\n\
         \n\
         [effects.todo-done]\n\
         route = \"/w\"\n"
    );
    std::fs::write(&path, toml).unwrap();
    (path, read_var, write_var)
}

// ── write-side state ──────────────────────────────────────────────────────────────────────────────

struct WriteState {
    adapter: Arc<FakePostgresWriteAdapter>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
    capability_id: String,
}

/// Build write-side state from the host.toml-derived `WriteBindingPlan`.
/// Policy + capability_id come from the plan; adapter is injected by the caller.
fn build_write_state(capability_id: &str, adapter: Arc<FakePostgresWriteAdapter>, plan: &igniter_web::host_binding::WriteBindingPlan) -> WriteState {
    let exec = Arc::new(IntentBridgeExecutor {
        cap: capability_id.to_string(),
        inner: PostgresWriteExecutor::new(capability_id, adapter.clone(), plan.write_policy.clone()),
    });
    let mut registry = CapabilityExecutorRegistry::new();
    registry.register(exec);
    WriteState {
        adapter,
        registry,
        receipts: Arc::new(InMemoryBackend::new()),
        eclock: clock(),
        ep: cpass("host", capability_id, &["write"]),
        sf: SingleFlight::new(),
        capability_id: capability_id.to_string(),
    }
}

fn write_bridge_cfg(st: &WriteState) -> EffectBridgeConfig<'_> {
    EffectBridgeConfig {
        registry: &st.registry,
        receipts: &st.receipts,
        effect_clock: &st.eclock,
        effect_passport: &st.ep,
        single_flight: &st.sf,
        capability_id: st.capability_id.clone(),
        operation: "write_record".into(),
        scope: "write".into(),
    }
}

fn build_effect_host_with_plan<'a>(
    router: &'a IngressRouter,
    hub: &'a CoordinationHub,
    cfg: &'a EffectBridgeConfig<'a>,
    bind_targets: &[(String, String)],
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(router, hub, cfg);
    for (target, route) in bind_targets {
        eh.bind_target(target, route);
    }
    eh
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────────────────────────

async fn get_todos(addr: std::net::SocketAddr, account_id: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let raw = format!(
        "GET /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n"
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

async fn post_todo(addr: std::net::SocketAddr, account_id: &str, idem_key: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    let body = "{}";
    let raw = format!(
        "POST /accounts/{account_id}/todos HTTP/1.1\r\nHost: x\r\n\
         Authorization: Bearer vtok\r\n\
         idempotency-key: {idem_key}\r\n\
         Content-Length: {}\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(raw.as_bytes()).await.unwrap();
    stream.flush().await.unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    String::from_utf8_lossy(&buf).to_string()
}

fn http_status(raw: &str) -> u16 {
    raw.split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

fn sample_todos(account_id: &str) -> Vec<Value> {
    vec![
        json!({"id": "t1", "account_id": account_id, "title": "Buy milk", "done": false}),
        json!({"id": "t2", "account_id": account_id, "title": "Write spec", "done": true}),
    ]
}

fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

// ── 1: read — found rows → ReadThen → HTTP 200 ───────────────────────────────────────────────────

#[test]
fn e2e_read_found_via_host_config_200() {
    let s = stamp();
    let (host_toml_path, read_var, write_var) = write_host_toml(s);

    // Binary path: load + resolve config before socket bind.
    let cfg = load_host_config(&host_toml_path).expect("load host.toml");
    let _resolved = resolve_host_config(&cfg).expect("resolve host.toml (env var check before bind)");

    // Read host: policy from host.toml, rows from fake adapter.
    let rc = cfg.postgres_read.as_ref().unwrap();
    let read_binding = read_policy_binding(rc);
    let account_id = format!("acct-p11-found-{s}");
    let read_adapter =
        Arc::new(FakePostgresAdapter::new().with_table("todos", sample_todos(&account_id)));
    let read_host = build_staged_read_host_with_adapter(&read_binding, read_adapter.clone());

    // Write host: capability + policy + bind_targets all from host.toml.
    let plan = write_binding_plan(&cfg);
    let write_cap = plan.capability_id.clone();
    let write_adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let st = build_write_state(&write_cap, write_adapter, &plan);
    let bridge_cfg = write_bridge_cfg(&st);

    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (hub, router) = build_coordination().await;
        let effect_host = build_effect_host_with_plan(&router, &hub, &bridge_cfg, &plan.bind_targets);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let acct = account_id.clone();
        let client = tokio::spawn(async move { get_todos(addr, &acct).await });
        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();
        assert_eq!(http_status(&raw), 200, "found rows → ReadThen → 200; raw={raw}");
        assert!(raw.contains("Buy milk"), "response body carries todo title");
        assert_eq!(read_adapter.query_count(), 1, "adapter queried once");
    });

    std::env::remove_var(&read_var);
    std::env::remove_var(&write_var);
}

// ── 2: read — empty rows → app-owned HTTP 404 ────────────────────────────────────────────────────

#[test]
fn e2e_read_empty_via_host_config_404() {
    let s = stamp();
    let (host_toml_path, read_var, write_var) = write_host_toml(s);

    let cfg = load_host_config(&host_toml_path).expect("load host.toml");
    let _resolved = resolve_host_config(&cfg).expect("resolve host.toml");

    let rc = cfg.postgres_read.as_ref().unwrap();
    let read_binding = read_policy_binding(rc);
    let read_adapter = Arc::new(FakePostgresAdapter::new().with_table("todos", vec![]));
    let read_host = build_staged_read_host_with_adapter(&read_binding, read_adapter);

    let plan = write_binding_plan(&cfg);
    let write_cap = plan.capability_id.clone();
    let write_adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let st = build_write_state(&write_cap, write_adapter, &plan);
    let bridge_cfg = write_bridge_cfg(&st);

    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (hub, router) = build_coordination().await;
        let effect_host = build_effect_host_with_plan(&router, &hub, &bridge_cfg, &plan.bind_targets);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client = tokio::spawn(async move { get_todos(addr, "acct-p11-empty").await });
        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();
        assert_eq!(http_status(&raw), 404, "empty rows → app-owned 404; raw={raw}");
    });

    std::env::remove_var(&read_var);
    std::env::remove_var(&write_var);
}

// ── 3: write — keyed create → committed receipt ───────────────────────────────────────────────────

#[test]
fn e2e_write_create_via_host_config_committed() {
    let s = stamp();
    let (host_toml_path, read_var, write_var) = write_host_toml(s);

    let cfg = load_host_config(&host_toml_path).expect("load host.toml");
    let _resolved = resolve_host_config(&cfg).expect("resolve host.toml");

    // Read host present but not exercised by POST.
    let rc = cfg.postgres_read.as_ref().unwrap();
    let read_binding = read_policy_binding(rc);
    let read_host =
        build_staged_read_host_with_adapter(&read_binding, Arc::new(FakePostgresAdapter::new()));

    let plan = write_binding_plan(&cfg);
    let write_cap = plan.capability_id.clone();
    let write_adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let st = build_write_state(&write_cap, write_adapter, &plan);
    let bridge_cfg = write_bridge_cfg(&st);

    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (hub, router) = build_coordination().await;
        let effect_host = build_effect_host_with_plan(&router, &hub, &bridge_cfg, &plan.bind_targets);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let client = tokio::spawn(async move {
            post_todo(addr, "acct-p11-write", &format!("evt-p11-c1-{s}")).await
        });
        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy)
            .await
            .unwrap();
        let raw = client.await.unwrap();
        assert_eq!(http_status(&raw), 200, "committed write → HTTP 200; raw={raw}");
        assert!(raw.contains("committed"), "response confirms committed status");
        assert_eq!(st.adapter.attempts(), 1, "one write adapter attempt");
        assert_eq!(st.adapter.business_row_count(), 1, "one business row committed");
        assert_eq!(st.adapter.effect_receipt_count(), 1, "one effect receipt written");
    });

    std::env::remove_var(&read_var);
    std::env::remove_var(&write_var);
}

// ── 4: write — replay same idempotency key → no second mutation ───────────────────────────────────

#[test]
fn e2e_write_replay_no_second_mutation() {
    let s = stamp();
    let (host_toml_path, read_var, write_var) = write_host_toml(s);

    let cfg = load_host_config(&host_toml_path).expect("load host.toml");
    let _resolved = resolve_host_config(&cfg).expect("resolve host.toml");

    let rc = cfg.postgres_read.as_ref().unwrap();
    let read_binding = read_policy_binding(rc);
    let read_host =
        build_staged_read_host_with_adapter(&read_binding, Arc::new(FakePostgresAdapter::new()));

    let plan = write_binding_plan(&cfg);
    let write_cap = plan.capability_id.clone();
    let write_adapter = Arc::new(FakePostgresWriteAdapter::new(FakeWriteBehavior::Commit));
    let st = build_write_state(&write_cap, write_adapter, &plan);
    let bridge_cfg = write_bridge_cfg(&st);

    let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (hub, router) = build_coordination().await;
        let effect_host = build_effect_host_with_plan(&router, &hub, &bridge_cfg, &plan.bind_targets);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let idem_key = format!("evt-p11-replay-{s}");
        let k1 = idem_key.clone();
        let k2 = idem_key.clone();
        let client = tokio::spawn(async move {
            let r1 = post_todo(addr, "acct-p11-replay", &k1).await;
            let r2 = post_todo(addr, "acct-p11-replay", &k2).await;
            (r1, r2)
        });
        let policy = ServingPolicy::new(2).loopback_only();
        machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy)
            .await
            .unwrap();
        let (r1, r2) = client.await.unwrap();
        assert_eq!(http_status(&r1), 200, "first create → 200; raw={r1}");
        assert_eq!(http_status(&r2), 200, "replay → still 200; raw={r2}");
        assert_eq!(
            st.adapter.attempts(),
            1,
            "same key → dedup: only one adapter attempt"
        );
        assert_eq!(st.adapter.business_row_count(), 1, "only one business row committed");
    });

    std::env::remove_var(&read_var);
    std::env::remove_var(&write_var);
}

// ── helpers ───────────────────────────────────────────────────────────────────────────────────────

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}
