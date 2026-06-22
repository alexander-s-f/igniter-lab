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
use igniter_web::runner::{parse_cli_args, RunnerCliCommand, RunnerCliOptions};
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
        RunnerCliCommand::Run(RunnerCliOptions { host_config_path, app_dir, .. }) => {
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
        RunnerCliCommand::Run(RunnerCliOptions { host_config_path, .. }) => {
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
        assert_eq!(status, 200, "GET /health in machine mode → 200; raw={response}");
        assert!(response.contains("ok"), "body must be 'ok'");
    });
}

// ── helpers ───────────────────────────────────────────────────────────────────────────────────────

fn stamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}
