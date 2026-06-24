//! async_machine_runner_tests.rs — LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2
//!
//! Proves the async IgWeb runner:
//!
//! 1. `IgWebLoadedApp::dispatch` called inside a tokio runtime — no nested `block_on` hazard.
//! 2. `serve_once_loaded` accepts a real `tokio::net::TcpListener`, reads an HTTP request, dispatches
//!    through `IgWebLoadedApp::dispatch`, routes `InvokeEffect` through `MachineEffectHost`, and
//!    returns a committed receipt response over the socket.
//! 3. Replay: same idempotency key → no second mutation (machine dedup).
//! 4. App sources carry no authority surface (verified against authored files).
//!
//! Fake write executor — no live DB. Gated `--features machine`.
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
use igniter_server::protocol::{ServerDecision, ServerRequest};
use igniter_web::machine_runner;
use igniter_web::runner::build_loaded_app_from_dir;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const WRITE_CAP: &str = "IO.TodoWrite";

// ── scaffolding (mirrors todo_postgres_effect_host_runner_tests.rs) ──────────────────────────────

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

/// Thin decorator that unwraps the bridge envelope `{ intent: <WriteIntent> }`.
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

async fn shaping_capsule_bytes() -> Vec<u8> {
    let m = IgniterMachine::new(None, "in_memory").unwrap();
    m.load_contract_source(
        "contract ShapeTodoWrite {\n\
         input operation : String\n  input target : String\n  input key : String\n\
         input values : Unknown\n  input correlation_id : String\n\
         compute intent = { operation: operation, target: target, key: key, values: values, correlation_id: correlation_id }\n\
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
        duplicate_policy: Some(dup_policy()),
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
fn write_policy() -> PostgresWritePolicy {
    PostgresWritePolicy::new()
        .allow_target("todos")
        .allow_ops(&["insert", "upsert"])
}
struct EffectState {
    adapter: Arc<FakePostgresWriteAdapter>,
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    eclock: Arc<dyn ClockProvider>,
    ep: CapabilityPassport,
    sf: SingleFlight,
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
    r: &'a IngressRouter,
    h: &'a CoordinationHub,
    c: &'a EffectBridgeConfig<'a>,
) -> MachineEffectHost<'a> {
    let mut eh = MachineEffectHost::new(r, h, c);
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

// ── helper: send one HTTP POST and read the raw response ─────────────────────────────────────────

async fn post_todo(addr: std::net::SocketAddr, idem_key: &str) -> String {
    let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
    // P45: the object create body is the ONLY accepted shape (legacy string body removed).
    let body = "{\"title\":\"Buy milk\"}";
    let raw = format!(
        "POST /accounts/acct-1/todos HTTP/1.1\r\nHost: x\r\n\
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

// ── 1: IgWebLoadedApp dispatches async — no nested block_on ──────────────────────────────────────

#[test]
fn loaded_app_dispatches_async_no_block_on() {
    let (loaded, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
    rt().block_on(async {
        // `dispatch` is awaited directly inside the tokio runtime — no block_on nesting.
        let req = ServerRequest::new("GET", "/health", serde_json::Value::Null);
        let decision = loaded.dispatch(req).await;
        match decision {
            ServerDecision::Respond { response } => {
                assert_eq!(response.status, 200, "health route → 200");
            }
            other => panic!("expected Respond, got {other:?}"),
        }
    });
}

// ── 2: serve_once_loaded over real tokio socket → InvokeEffect committed ─────────────────────────

#[test]
fn serve_once_loaded_executes_invoke_effect_over_socket() {
    let (loaded, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        // Spawn HTTP client; serve_once_loaded accepts the connection.
        let client = tokio::spawn(async move { post_todo(addr, "evt-p2-a1").await });
        machine_runner::serve_once_loaded(&listener, &loaded, &eh)
            .await
            .unwrap();
        let raw = client.await.unwrap();

        assert_eq!(http_status(&raw), 200, "committed → 200; raw={raw}");
        assert_eq!(st.adapter.attempts(), 1, "one adapter attempt");
        assert_eq!(st.adapter.business_row_count(), 1, "one business row");
        assert_eq!(st.adapter.effect_receipt_count(), 1, "one PG-side receipt");
    });
}

// ── 3: replay through socket — same idempotency key → no second mutation ─────────────────────────

#[test]
fn replay_same_key_no_second_mutation_over_socket() {
    let (loaded, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    rt().block_on(async {
        let (h, r) = prod(3).await;
        let st = effect_state();
        let c = cfg(&st);
        let eh = effect_host(&r, &h, &c);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        for i in 1..=2u16 {
            let client = tokio::spawn(async move { post_todo(addr, "evt-replay-p2").await });
            machine_runner::serve_once_loaded(&listener, &loaded, &eh)
                .await
                .unwrap();
            let raw = client.await.unwrap();
            assert_eq!(http_status(&raw), 200, "request {i} → 200");
        }

        assert_eq!(st.adapter.attempts(), 1, "dedup: one adapter attempt");
        assert_eq!(st.adapter.business_row_count(), 1, "one business row");
    });
}

// ── 4: async path carries no authority surface ────────────────────────────────────────────────────

#[test]
fn async_path_carries_no_authority_surface() {
    let handlers = std::fs::read_to_string(app_dir().join("todo_handlers.ig")).unwrap();
    let routes = std::fs::read_to_string(app_dir().join("routes.igweb")).unwrap();
    let strip_comments = |s: &str| {
        s.lines()
            .map(|l| l.split("--").next().unwrap_or(""))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let code = format!("{}\n{}", strip_comments(&handlers), strip_comments(&routes)).to_lowercase();
    for forbidden in [
        "capability_id",
        "io.todowrite",
        "io.postgres",
        "passport",
        "dsn",
        "postgres://",
        "select ",
        "insert into",
    ] {
        assert!(
            !code.contains(forbidden),
            "authored app must not contain `{forbidden}`"
        );
    }
    assert!(code.contains("\"todo-create\""), "only logical targets");
}

// ── 5: host config v0 — parser smoke test ────────────────────────────────────────────────────────

#[test]
fn host_config_accepts_env_ref_rejects_inline_secrets() {
    use igniter_web::host_config::{parse_host_config, HostConfigError};

    let good = r#"
[host]
mode = "loopback"
[effects.todo-create]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"
[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"
"#;
    let cfg = parse_host_config(good).expect("valid host config");
    assert_eq!(cfg.effects["todo-create"].route, "/w");
    assert_eq!(
        cfg.postgres_write.as_ref().unwrap().dsn_env,
        "IGNITER_PG_WRITE_DSN"
    );

    // Inline DSN must be rejected.
    let bad = "[postgres.write]\ndsn = \"postgres://localhost/db\"";
    assert!(matches!(
        parse_host_config(bad).unwrap_err(),
        HostConfigError::InlineSecret { .. }
    ));

    // Inline passport must be rejected.
    let bad2 = "[effects.x]\nroute = \"/w\"\npassport = \"raw\"";
    assert!(matches!(
        parse_host_config(bad2).unwrap_err(),
        HostConfigError::InlineSecret { .. }
    ));

    // Unknown section must fail closed.
    let bad3 = "[vault]\npath = \"secret\"";
    assert!(matches!(
        parse_host_config(bad3).unwrap_err(),
        HostConfigError::UnknownSection(_)
    ));
}
