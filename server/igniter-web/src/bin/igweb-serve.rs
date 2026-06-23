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
#[cfg(feature = "machine")]
use igniter_web::runner::RunnerCliOptions;
use igniter_web::runner::{
    build_app_from_dir, check_app_dir, parse_cli_args, resolve_sources, RunnerCliCommand,
};
use igniter_web::runner_diag::{classify_runner_error, RunnerDiagnostic};
use std::net::TcpListener;

/// Print a coded, redacted diagnostic to stderr and exit with its stable non-zero code.
/// stdout stays reserved for the machine-readable `listening http://…` line.
fn fail(diag: RunnerDiagnostic) -> ! {
    eprintln!("{diag}");
    std::process::exit(diag.exit_code());
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let parsed = match parse_cli_args(std::env::args().skip(1)) {
        Ok(p) => p,
        Err(e) => fail(classify_runner_error(&e)),
    };
    let cli = match parsed {
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
        match run_machine_mode(&cli, host_config_path) {
            Ok(()) => return Ok(()),
            Err(diag) => fail(diag),
        }

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
) -> Result<(), RunnerDiagnostic> {
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
    use igniter_web::runner_diag::{classify_host_config_error, classify_runner_error, DiagCode};
    use std::sync::Arc;

    // 1. Parse + resolve host config — env var expansion happens here; secrets never interpolated.
    //    Both failures happen BEFORE any socket bind and name the section/key/env-var, not values.
    let host_cfg =
        load_host_config(host_config_path).map_err(|e| classify_host_config_error(&e))?;
    let resolved = resolve_host_config(&host_cfg).map_err(|e| classify_host_config_error(&e))?;

    if !resolved.effects.is_empty() {
        println!(
            "igweb-serve: machine-mode {} effect target(s) configured",
            resolved.effects.len()
        );
    }
    if resolved.postgres_read_dsn.is_some() {
        #[cfg(feature = "postgres")]
        println!("igweb-serve: machine-mode postgres.read DSN resolved; connecting real executor");
        #[cfg(not(feature = "postgres"))]
        println!(
            "igweb-serve: machine-mode postgres.read DSN resolved \
             (build with --features postgres to wire a real executor; ReadThen denied by host)"
        );
    }
    if resolved.postgres_write_dsn.is_some() {
        #[cfg(feature = "postgres")]
        println!("igweb-serve: machine-mode postgres.write DSN resolved; connecting real executor");
        #[cfg(not(feature = "postgres"))]
        println!(
            "igweb-serve: machine-mode postgres.write DSN resolved \
             (build with --features postgres to wire a real executor; InvokeEffect denied by host)"
        );
    }

    // 2. Build the loaded app (async dispatch path, never calls ServerApp::call)
    let (app, manifest) =
        build_loaded_app_from_dir(&cli.app_dir).map_err(|e| classify_runner_error(&e))?;
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

    // 4. Run bounded loopback tokio loop; block_on blocks until max requests are served
    let app_dir_str = cli.app_dir.display().to_string();
    let entry = manifest.entry.clone();
    let addr = cli.addr;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| {
            RunnerDiagnostic::new(DiagCode::RunnerInternal, format!("tokio runtime: {e}"))
        })?;
    rt.block_on(async {
        // Known DSN values the runner holds — passed to the POSTGRES_CONNECT redactor so an adapter
        // connect error (which can embed the connection string) never reaches the operator log.
        #[cfg(feature = "postgres")]
        let known_dsns: Vec<&str> = [
            resolved.postgres_read_dsn.as_deref(),
            resolved.postgres_write_dsn.as_deref(),
        ]
        .into_iter()
        .flatten()
        .collect();

        // Build the active read host: real executor under --features postgres when [postgres.read]
        // is configured; fail-closed empty registry otherwise (ReadThen → 403 host-denied).
        #[cfg(feature = "postgres")]
        let read_host = {
            use igniter_web::host_binding::build_staged_read_host_from_resolved;
            match build_staged_read_host_from_resolved(&host_cfg, &resolved).await {
                Ok(Some(h)) => {
                    println!("igweb-serve: machine-mode postgres.read executor connected");
                    h
                }
                Ok(None) => {
                    let reg = CapabilityExecutorRegistry::new();
                    let recs: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
                    StagedReadHost::new(reg, recs, "IO.PostgresRead")
                }
                Err(e) => {
                    return Err(RunnerDiagnostic::postgres_connect(
                        format!("postgres.read: {e}"),
                        &known_dsns,
                    ))
                }
            }
        };
        #[cfg(not(feature = "postgres"))]
        let read_host = {
            let reg = CapabilityExecutorRegistry::new();
            let recs: Arc<dyn TBackend> = Arc::new(InMemoryBackend::new());
            StagedReadHost::new(reg, recs, "IO.PostgresRead")
        };

        // Build the active write host: real executor + coordination under --features postgres when
        // [postgres.write] + [effects.*] + passport_env are all configured. Returns early with the
        // real effect host; falls through to the no-op host when the section is absent.
        #[cfg(feature = "postgres")]
        {
            use igniter_machine::ingress::EffectBridgeConfig;
            use igniter_web::host_binding::build_write_host_from_resolved;
            let write_opt = match build_write_host_from_resolved(&host_cfg, &resolved).await {
                Ok(opt) => opt,
                Err(e) => {
                    return Err(RunnerDiagnostic::postgres_connect(
                        format!("postgres.write: {e}"),
                        &known_dsns,
                    ))
                }
            };
            if let Some(state) = write_opt {
                println!("igweb-serve: machine-mode postgres.write executor connected");
                let bridge_cfg = EffectBridgeConfig {
                    registry: &state.registry,
                    receipts: &state.receipts,
                    effect_clock: &state.clk,
                    effect_passport: &state.ep,
                    single_flight: &state.sf,
                    capability_id: state.capability_id.clone(),
                    operation: "write_record".to_string(),
                    scope: "write".to_string(),
                };
                let mut real_effect_host =
                    igniter_server::effect_host::MachineEffectHost::new(
                        &state.router, &state.hub, &bridge_cfg,
                    );
                for (target, route) in &state.bind_targets {
                    real_effect_host.bind_target(target, route);
                }
                let listener = tokio::net::TcpListener::bind(addr).await.map_err(|e| {
                    RunnerDiagnostic::new(DiagCode::BindRefused, format!("bind {addr}: {e}"))
                })?;
                let bound = listener.local_addr().map_err(|e| {
                    RunnerDiagnostic::new(DiagCode::RunnerInternal, format!("local_addr: {e}"))
                })?;
                println!(
                    "igweb-serve: machine-mode app_dir={} entry={} listening http://{} \
                     (loopback, bounded to {} request(s))",
                    app_dir_str, entry, bound, max
                );
                let policy = ServingPolicy::new(max).loopback_only();
                let report = machine_runner::serve_loop_loaded_with_read(
                    &listener, &app, &real_effect_host, &read_host, &policy,
                )
                .await
                .map_err(|e| {
                    RunnerDiagnostic::new(DiagCode::RunnerInternal, format!("serve loop: {e}"))
                })?;
                println!(
                    "igweb-serve: machine-mode served {} request(s); exiting",
                    report.requests_served
                );
                return Ok(());
            }
        }

        // Fallback: no-op effect host (no [postgres.write] section, no passport_env, or no
        // --features postgres). InvokeEffect → 502 "unbound target" (fail-closed).
        let listener = tokio::net::TcpListener::bind(addr).await.map_err(|e| {
            RunnerDiagnostic::new(DiagCode::BindRefused, format!("bind {addr}: {e}"))
        })?;
        let bound = listener.local_addr().map_err(|e| {
            RunnerDiagnostic::new(DiagCode::RunnerInternal, format!("local_addr: {e}"))
        })?;
        println!(
            "igweb-serve: machine-mode app_dir={} entry={} listening http://{} (loopback, bounded to {} request(s))",
            app_dir_str, entry, bound, max
        );
        let policy = ServingPolicy::new(max).loopback_only();
        let report =
            machine_runner::serve_loop_loaded_with_read(&listener, &app, &effect_host, &read_host, &policy)
                .await
                .map_err(|e| {
                    RunnerDiagnostic::new(DiagCode::RunnerInternal, format!("serve loop: {e}"))
                })?;
        println!(
            "igweb-serve: machine-mode served {} request(s); exiting",
            report.requests_served
        );
        Ok::<(), RunnerDiagnostic>(())
    })?;

    Ok(())
}
