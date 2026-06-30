//! igweb_serve_machine_mode_tests.rs — LAB-IGNITER-WEB-IGWEB-SERVE-MACHINE-MODE-P22
//!
//! Proves the `--host-config` additions to `igweb-serve`:
//!
//!   1. CLI parse recognises `--host-config <path>`.
//!   2. Inline secrets in host.toml are rejected before any socket bind.
//!   3. Missing env var in host.toml fails before any socket bind.
//!   4. Smoke: machine-mode path resolves config, builds app, serves one request over socket.
//!
//! Tests 1–3 run without the `machine` feature gate (they only exercise CLI parsing and host_config).
//! Test 4 is feature-gated to `machine`.

use igniter_web::host_config::{load_host_config, resolve_host_config};
use igniter_web::runner::{RunnerCliCommand, RunnerCliOptions, parse_cli_args};
use std::path::PathBuf;

#[cfg(feature = "machine")]
fn app_dir() -> PathBuf {
    PathBuf::from(format!(
        "{}/examples/todo_postgres_app",
        env!("CARGO_MANIFEST_DIR")
    ))
}

// ── 1: CLI parse ──────────────────────────────────────────────────────────────────────────────────

#[test]
fn cli_parse_host_config_flag() {
    let cmd = parse_cli_args(["--host-config", "/etc/host.toml", "app_dir"]).unwrap();
    match cmd {
        RunnerCliCommand::Run(RunnerCliOptions {
            host_config_path,
            app_dir,
            ..
        }) => {
            assert_eq!(
                host_config_path,
                Some(PathBuf::from("/etc/host.toml")),
                "--host-config must be parsed into host_config_path"
            );
            assert_eq!(app_dir, PathBuf::from("app_dir"));
        }
        other => panic!("expected Run, got {other:?}"),
    }
}

#[test]
fn cli_parse_host_config_requires_value() {
    let err = parse_cli_args(["--host-config"]).unwrap_err();
    assert!(
        err.to_string().contains("--host-config"),
        "error must mention --host-config; got: {err}"
    );
}

#[test]
fn cli_parse_without_host_config_has_none() {
    let cmd = parse_cli_args(["app_dir"]).unwrap();
    match cmd {
        RunnerCliCommand::Run(RunnerCliOptions {
            host_config_path, ..
        }) => {
            assert!(
                host_config_path.is_none(),
                "no --host-config → host_config_path must be None"
            );
        }
        other => panic!("expected Run, got {other:?}"),
    }
}

#[test]
fn cli_help_documents_host_config() {
    let usage = igniter_web::runner::usage();
    assert!(
        usage.contains("--host-config"),
        "--host-config must appear in usage text"
    );
}

// ── 2: inline secret rejected ─────────────────────────────────────────────────────────────────────

#[test]
fn host_config_inline_dsn_rejected() {
    let toml = "[postgres.read]\ndsn = \"postgres://localhost/db\"\n";
    let dir = std::env::temp_dir().join(format!(
        "igweb_p22_inline_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();

    let err = load_host_config(&path).unwrap_err();
    assert!(
        err.to_string().contains("dsn") || err.to_string().contains("inline"),
        "inline dsn must be rejected; got: {err}"
    );
}

#[test]
fn host_config_inline_passport_rejected() {
    let toml = "[effects.write]\nroute = \"/effect\"\npassport = \"secret-value\"\n";
    let dir = std::env::temp_dir().join(format!(
        "igweb_p22_passport_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();

    let err = load_host_config(&path).unwrap_err();
    assert!(
        err.to_string().contains("passport") || err.to_string().contains("inline"),
        "inline passport must be rejected; got: {err}"
    );
}

// ── 3: missing env var fails before socket bind ───────────────────────────────────────────────────

#[test]
fn host_config_missing_env_var_fails() {
    let var_name = format!("IGWEB_P22_NONEXISTENT_{}", stamp());
    // Ensure the var is absent (it is, being random)
    std::env::remove_var(&var_name);

    let toml = format!("[postgres.read]\ndsn_env = \"{var_name}\"\n");
    let dir = std::env::temp_dir().join(format!(
        "igweb_p22_missing_env_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();

    let cfg = load_host_config(&path).expect("parse must succeed for env-name reference");
    let err = resolve_host_config(&cfg).unwrap_err();
    assert!(
        err.to_string().contains(&var_name) || err.to_string().contains("env"),
        "missing env var must be reported; got: {err}"
    );
}

#[test]
fn host_config_present_env_var_resolves() {
    let var_name = format!("IGWEB_P22_TEST_DSN_{}", stamp());
    std::env::set_var(&var_name, "postgres://localhost/test");

    let toml = format!("[postgres.read]\ndsn_env = \"{var_name}\"\n");
    let dir = std::env::temp_dir().join(format!(
        "igweb_p22_present_env_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("host.toml");
    std::fs::write(&path, toml).unwrap();

    let cfg = load_host_config(&path).unwrap();
    let resolved = resolve_host_config(&cfg).expect("set env var must resolve");
    assert!(resolved.postgres_read_dsn.is_some(), "DSN must be present");
    // Do not assert the value — secrets must not appear in test output
    std::env::remove_var(&var_name);
}

// ── 4: smoke — machine mode resolves config, builds app, serves one request ───────────────────────

#[cfg(feature = "machine")]
#[test]
fn machine_mode_smoke_serves_health_request() {
    use igniter_machine::backend::{InMemoryBackend, TBackend};
    use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
    use igniter_machine::clock::{ClockProvider, SystemClock};
    use igniter_machine::coordination::CoordinationHub;
    use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
    use igniter_machine::single_flight::SingleFlight;
    use igniter_server::effect_host::MachineEffectHost;
    use igniter_server::serving_loop::ServingPolicy;
    use igniter_web::machine_runner;
    use igniter_web::runner::build_loaded_app_from_dir;
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    // Write a minimal host.toml that requires no env vars
    let toml = "[host]\nmode = \"loopback\"\n";
    let dir = std::env::temp_dir().join(format!(
        "igweb_p22_smoke_{}_{}",
        std::process::id(),
        stamp()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let host_toml_path = dir.join("host.toml");
    std::fs::write(&host_toml_path, toml).unwrap();

    // Resolve config (proves env-var expansion path runs before socket bind)
    let host_cfg = load_host_config(&host_toml_path).expect("parse minimal host.toml");
    let resolved = resolve_host_config(&host_cfg).expect("resolve minimal host.toml");
    assert_eq!(resolved.host_mode, "loopback");

    // Build the loaded app (never calls ServerApp::call)
    let (app, _manifest) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");

    // Build a no-op effect host (matches what the binary constructs in machine mode)
    let router = IngressRouter::new();
    let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let clk: Arc<dyn ClockProvider> = Arc::new(SystemClock);
    let hub = CoordinationHub::new(audit.clone(), Arc::clone(&clk));
    let registry = CapabilityExecutorRegistry::new();
    let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let ep = CapabilityPassport {
        subject: "host".to_string(),
        capability_id: "noop".to_string(),
        scopes: vec![],
        issued_at: 0.0,
        expires_at: None,
        revoked: false,
        evidence_digest: String::new(),
    };
    let sf = SingleFlight::new();
    let cfg = EffectBridgeConfig {
        registry: &registry,
        receipts: &receipts,
        effect_clock: &clk,
        effect_passport: &ep,
        effect_passport_verifier: None,
        single_flight: &sf,
        capability_id: "noop".to_string(),
        operation: "noop".to_string(),
        scope: "noop".to_string(),
    };
    let effect_host = MachineEffectHost::new(&router, &hub, &cfg);

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    rt.block_on(async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        assert!(addr.ip().is_loopback(), "bound addr must be loopback");

        let client = tokio::spawn(async move {
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            let raw = "GET /health HTTP/1.1\r\nHost: x\r\ncontent-length: 0\r\n\r\n";
            stream.write_all(raw.as_bytes()).await.unwrap();
            stream.flush().await.unwrap();
            let mut buf = Vec::new();
            stream.read_to_end(&mut buf).await.unwrap();
            String::from_utf8_lossy(&buf).to_string()
        });

        // Serve exactly one request — proves machine-mode path uses dispatch, not ServerApp::call
        let policy = ServingPolicy::new(1).loopback_only();
        machine_runner::serve_loop_loaded(&listener, &app, &effect_host, &policy)
            .await
            .unwrap();

        let response = client.await.unwrap();
        let status: u16 = response
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        assert_eq!(
            status, 200,
            "GET /health in machine mode → 200; raw={response}"
        );
        assert!(response.contains("ok"), "body must be 'ok'");
    });
}

// ── 5: ReadThen in machine-mode socket path (P23) ─────────────────────────────────────────────────
//
// Mirrors what `igweb-serve --host-config` does after P23:
//   machine_mode_readthen_found_rows_http_200     — fake executor, found rows → ReadThen → 200
//   machine_mode_readthen_empty_rows_http_200_empty_list — fake executor, empty table → ReadThen → 200 []
//   machine_mode_readthen_no_executor_host_denied — empty registry (v0 binary posture) → 403
//
// All use serve_loop_loaded_with_read + build_loaded_app_from_dir(&app_dir()) + no-op write host.

#[cfg(feature = "machine")]
mod readthen_p23 {
    use super::{app_dir, stamp};
    use igniter_machine::backend::{InMemoryBackend, TBackend};
    use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
    use igniter_machine::clock::{ClockProvider, SystemClock};
    use igniter_machine::coordination::CoordinationHub;
    use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
    use igniter_machine::postgres_read::{
        FakePostgresAdapter, PostgresReadExecutor, PostgresReadPolicy,
    };
    use igniter_machine::single_flight::SingleFlight;
    use igniter_server::effect_host::MachineEffectHost;
    use igniter_server::serving_loop::ServingPolicy;
    use igniter_web::machine_runner;
    use igniter_web::read_dispatch::StagedReadHost;
    use igniter_web::runner::build_loaded_app_from_dir;
    use serde_json::json;
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    const READ_CAP: &str = "IO.PostgresRead";

    // `done` is a STRING — `host.example.toml` allowlists `todos` fields untyped → Text decode (P50).
    fn sample_todos(account_id: &str) -> Vec<serde_json::Value> {
        vec![
            json!({"id": "t1", "account_id": account_id, "title": "Buy milk", "done": "false"}),
            json!({"id": "t2", "account_id": account_id, "title": "Write spec", "done": "true"}),
        ]
    }

    /// P38: an `accounts` row so the index's stage-1 existence read finds the account.
    fn sample_account(account_id: &str) -> Vec<serde_json::Value> {
        vec![json!({"id": account_id, "name": "Test Account"})]
    }

    fn make_read_host(adapter: Arc<FakePostgresAdapter>) -> StagedReadHost {
        let policy = PostgresReadPolicy::new(100)
            .allow_ops(&["select"])
            .allow_source("todos", &["id", "account_id", "title", "done"])
            .allow_source("accounts", &["id", "name"]);
        let exec = Arc::new(PostgresReadExecutor::new(READ_CAP, adapter, policy.clone()));
        let mut registry = CapabilityExecutorRegistry::new();
        registry.register(exec);
        let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        // P50: the typed list continuation needs the policy attached to build its ProjectionSpec.
        StagedReadHost::new(registry, receipts, READ_CAP).with_read_policy(policy)
    }

    /// Components for a no-op write-side effect host. All borrows must outlive the host.
    struct NoopParts {
        router: IngressRouter,
        hub: CoordinationHub,
        registry: CapabilityExecutorRegistry,
        receipts: Arc<dyn TBackend>,
        clk: Arc<dyn ClockProvider>,
        ep: CapabilityPassport,
        sf: SingleFlight,
    }
    impl NoopParts {
        fn new() -> Self {
            let router = IngressRouter::new();
            let audit: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            let clk: Arc<dyn ClockProvider> = Arc::new(SystemClock);
            let hub = CoordinationHub::new(audit.clone(), Arc::clone(&clk));
            let registry = CapabilityExecutorRegistry::new();
            let receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            let ep = CapabilityPassport {
                subject: "host".to_string(),
                capability_id: "noop".to_string(),
                scopes: vec![],
                issued_at: 0.0,
                expires_at: None,
                revoked: false,
                evidence_digest: String::new(),
            };
            let sf = SingleFlight::new();
            Self {
                router,
                hub,
                registry,
                receipts,
                clk,
                ep,
                sf,
            }
        }
    }

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

    fn http_status(raw: &str) -> u16 {
        raw.split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0)
    }

    #[test]
    fn machine_mode_readthen_found_rows_http_200() {
        let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
        let account_id = format!("acct-p23-found-{}", stamp());
        let adapter = Arc::new(
            FakePostgresAdapter::new()
                .with_table("accounts", sample_account(&account_id))
                .with_table("todos", sample_todos(&account_id)),
        );
        let read_host = make_read_host(adapter);

        let parts = NoopParts::new();
        let cfg = EffectBridgeConfig {
            registry: &parts.registry,
            receipts: &parts.receipts,
            effect_clock: &parts.clk,
            effect_passport: &parts.ep,
            effect_passport_verifier: None,
            single_flight: &parts.sf,
            capability_id: "noop".to_string(),
            operation: "noop".to_string(),
            scope: "noop".to_string(),
        };
        let effect_host = MachineEffectHost::new(&parts.router, &parts.hub, &cfg);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let acct = account_id.clone();
            let client = tokio::spawn(async move { get_todos(addr, &acct).await });
            let policy = ServingPolicy::new(1).loopback_only();
            machine_runner::serve_loop_loaded_with_read(
                &listener,
                &app,
                &effect_host,
                &read_host,
                &policy,
            )
            .await
            .unwrap();
            let raw = client.await.unwrap();
            assert_eq!(
                http_status(&raw),
                200,
                "found rows → ReadThen → 200 in machine-mode path; raw={raw}"
            );
            assert!(
                raw.contains("Buy milk"),
                "response body carries the todo title"
            );
        });
    }

    #[test]
    fn machine_mode_readthen_empty_rows_http_200_empty_list() {
        let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
        let adapter = Arc::new(
            FakePostgresAdapter::new()
                .with_table("accounts", sample_account("acct-p23-empty"))
                .with_table("todos", vec![]),
        );
        let read_host = make_read_host(adapter);

        let parts = NoopParts::new();
        let cfg = EffectBridgeConfig {
            registry: &parts.registry,
            receipts: &parts.receipts,
            effect_clock: &parts.clk,
            effect_passport: &parts.ep,
            effect_passport_verifier: None,
            single_flight: &parts.sf,
            capability_id: "noop".to_string(),
            operation: "noop".to_string(),
            scope: "noop".to_string(),
        };
        let effect_host = MachineEffectHost::new(&parts.router, &parts.hub, &cfg);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let client = tokio::spawn(async move { get_todos(addr, "acct-p23-empty").await });
            let policy = ServingPolicy::new(1).loopback_only();
            machine_runner::serve_loop_loaded_with_read(
                &listener,
                &app,
                &effect_host,
                &read_host,
                &policy,
            )
            .await
            .unwrap();
            let raw = client.await.unwrap();
            assert_eq!(
                http_status(&raw),
                200,
                "empty rows → 200 [] in machine-mode path (a list, not 404); raw={raw}"
            );
            assert!(
                raw.contains("[]"),
                "body carries the empty array; raw={raw}"
            );
        });
    }

    #[test]
    fn machine_mode_readthen_no_executor_host_denied() {
        // Proves the v0 binary posture: empty StagedReadHost → ReadThen → 403 host-denied.
        // The binary builds exactly this until a real executor is wired from the resolved DSN.
        let (app, _) = build_loaded_app_from_dir(&app_dir()).expect("build todo_postgres_app");
        let read_receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
        let read_host =
            StagedReadHost::new(CapabilityExecutorRegistry::new(), read_receipts, READ_CAP);

        let parts = NoopParts::new();
        let cfg = EffectBridgeConfig {
            registry: &parts.registry,
            receipts: &parts.receipts,
            effect_clock: &parts.clk,
            effect_passport: &parts.ep,
            effect_passport_verifier: None,
            single_flight: &parts.sf,
            capability_id: "noop".to_string(),
            operation: "noop".to_string(),
            scope: "noop".to_string(),
        };
        let effect_host = MachineEffectHost::new(&parts.router, &parts.hub, &cfg);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let client = tokio::spawn(async move { get_todos(addr, "acct-p23-denied").await });
            let policy = ServingPolicy::new(1).loopback_only();
            machine_runner::serve_loop_loaded_with_read(
                &listener,
                &app,
                &effect_host,
                &read_host,
                &policy,
            )
            .await
            .unwrap();
            let raw = client.await.unwrap();
            assert_eq!(
                http_status(&raw),
                403,
                "empty registry → host-denied 403 (v0 binary posture); raw={raw}"
            );
        });
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────────────────────────

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}
