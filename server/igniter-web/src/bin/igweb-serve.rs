//! `igweb-serve <app_dir>` — the generic lab IgWeb runner.
//!
//! Without `--host-config`: sync `std::net::TcpListener` + `serve_loop` (unchanged from P12).
//! With `--host-config`:    async tokio loop via `machine_runner::serve_loop_loaded_with_read` (P23).
//!
//! `--host-config` parses and resolves `host.toml` (env-var expansion) before binding the socket.
//! Missing env vars exit immediately; inline secrets are rejected at parse time.
//! Requires `--features machine`. Not a stable CLI surface. Loopback only.

use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use igniter_web::runner::{
    build_app_from_dir, check_app_dir, parse_cli_args, resolve_sources, RunnerCliCommand,
};
#[cfg(feature = "machine")]
use igniter_web::runner::RunnerCliOptions;
use std::net::TcpListener;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = match parse_cli_args(std::env::args().skip(1))? {
        RunnerCliCommand::Help(text) => {
            println!("{text}");
            return Ok(());
        }
        RunnerCliCommand::Check(cli) => {
            let report = check_app_dir(&cli.app_dir)?;
            println!(
                "igweb-serve: check ok app_dir={} entry={} sources={} (no socket opened)",
                cli.app_dir.display(),
                report.entry,
                report.source_count
            );
            return Ok(());
        }
        RunnerCliCommand::Run(cli) => cli,
    };

    // Machine-mode path: async tokio loop, no ServerApp::call
    if let Some(host_config_path) = &cli.host_config_path {
        #[cfg(feature = "machine")]
        return run_machine_mode(&cli, host_config_path);

        #[cfg(not(feature = "machine"))]
        {
            let _ = host_config_path;
            eprintln!(
                "igweb-serve: --host-config requires the `machine` feature; \
                 recompile with --features machine"
            );
            std::process::exit(1);
        }
    }

    // Sync path (unchanged)
    let app_dir = &cli.app_dir;
    let (app, manifest) = build_app_from_dir(app_dir)?;
    let listener = TcpListener::bind(cli.addr)?;
    let addr = listener.local_addr()?;
    let source_count = resolve_sources(app_dir, &manifest)?.len();
    let max = cli.max_requests.or(manifest.max_requests).unwrap_or(1024);
    println!(
        "igweb-serve: app_dir={} entry={} sources={} listening http://{} (loopback, bounded to {} request(s))",
        app_dir.display(), manifest.entry, source_count, addr, max
    );
    let reloadable = ReloadableApp::new(app);
    let report = serve_loop(
        &listener,
        &reloadable,
        &ServingPolicy::new(max).loopback_only(),
    )?;
    println!(
        "igweb-serve: served {} request(s); exiting",
        report.requests_served
    );
    Ok(())
}

/// Async machine-mode runner: parse+resolve host config, build loaded app, run tokio loop.
/// Invoked only when `--host-config` is present. Feature-gated to avoid unused-import warnings.
#[cfg(feature = "machine")]
fn run_machine_mode(
    cli: &RunnerCliOptions,
    host_config_path: &std::path::Path,
) -> Result<(), Box<dyn std::error::Error>> {
    use igniter_machine::backend::{InMemoryBackend, TBackend};
    use igniter_machine::capability::{CapabilityExecutorRegistry, CapabilityPassport};
    use igniter_machine::clock::{ClockProvider, SystemClock};
    use igniter_machine::coordination::CoordinationHub;
    use igniter_machine::ingress::{EffectBridgeConfig, IngressRouter};
    use igniter_machine::single_flight::SingleFlight;
    use igniter_server::effect_host::MachineEffectHost;
    use igniter_server::serving_loop::ServingPolicy;
    use igniter_web::host_config::{load_host_config, resolve_host_config};
    use igniter_web::machine_runner;
    use igniter_web::read_dispatch::StagedReadHost;
    use igniter_web::runner::build_loaded_app_from_dir;
    use std::sync::Arc;

    // 1. Parse + resolve host config — env var expansion happens here; secrets never interpolated
    let host_cfg = load_host_config(host_config_path)?;
    let resolved = resolve_host_config(&host_cfg)?;

    if !resolved.effects.is_empty() {
        println!(
            "igweb-serve: machine-mode {} effect target(s) configured",
            resolved.effects.len()
        );
    }
    if resolved.postgres_read_dsn.is_some() {
        println!(
            "igweb-serve: machine-mode postgres.read DSN resolved \
             (v0: executor not yet wired; ReadThen decisions denied by host)"
        );
    }
    if resolved.postgres_write_dsn.is_some() {
        println!("igweb-serve: machine-mode postgres.write DSN resolved");
    }

    // 2. Build the loaded app (async dispatch path, never calls ServerApp::call)
    let (app, manifest) = build_loaded_app_from_dir(&cli.app_dir)?;
    let max = cli.max_requests.or(manifest.max_requests).unwrap_or(1024);

    // 3. Build a no-op effect host (v0: InvokeEffect from continuation is the next card)
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

    // Build a minimal staged-read host (v0: empty registry).
    // ReadThen decisions return 403 host-denied until an executor is wired from resolved DSN.
    // Authority stays host-owned; the empty registry is the fail-closed posture for v0.
    let read_registry = CapabilityExecutorRegistry::new();
    let read_receipts: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
    let read_host = StagedReadHost::new(read_registry, read_receipts, "IO.PostgresRead");

    // 4. Run bounded loopback tokio loop; block_on blocks until max requests are served
    let app_dir_str = cli.app_dir.display().to_string();
    let entry = manifest.entry.clone();
    let addr = cli.addr;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(async {
        let listener = tokio::net::TcpListener::bind(addr).await?;
        let bound = listener.local_addr()?;
        println!(
            "igweb-serve: machine-mode app_dir={} entry={} listening http://{} (loopback, bounded to {} request(s))",
            app_dir_str, entry, bound, max
        );
        let policy = ServingPolicy::new(max).loopback_only();
        let report =
            machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy).await?;
        println!(
            "igweb-serve: machine-mode served {} request(s); exiting",
            report.requests_served
        );
        Ok::<(), std::io::Error>(())
    })?;

    Ok(())
}
