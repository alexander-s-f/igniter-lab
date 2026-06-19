//! `igweb-serve <app_dir>` — the generic lab IgWeb runner (LAB-IGNITER-WEB-RUNNER-P12).
//!
//! An Igniter-only author writes `routes.igweb` + handler `.ig` + `igweb.toml` (no Rust) and runs this
//! pre-built binary. It loads the manifest, builds the app via `igniter_web::build_igweb_app`, composes
//! P8 middleware from the manifest, holds the app in `ReloadableApp`, and serves a bounded loopback
//! `serve_loop`. The server owns transport/loop/reload; the app owns routing/domain. Lab v0 — NOT a
//! stable CLI. Loopback only; no public bind; no live effect execution.

use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use igniter_web::runner::{
    build_app_from_dir, check_app_dir, parse_cli_args, resolve_sources, RunnerCliCommand,
};
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
    let app_dir = cli.app_dir;
    let (app, manifest) = build_app_from_dir(&app_dir)?;

    let listener = TcpListener::bind(cli.addr)?;
    let addr = listener.local_addr()?;
    let source_count = resolve_sources(&app_dir, &manifest)?.len();
    let max = cli.max_requests.or(manifest.max_requests).unwrap_or(1024);
    println!(
        "igweb-serve: app_dir={} entry={} sources={} listening http://{} (loopback, bounded to {} request(s))",
        app_dir.display(), manifest.entry, source_count, addr, max
    );

    // The host owns the loop + reload unit; the manifest-built (composed) app is the swap unit.
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
