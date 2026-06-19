//! `igweb-serve <app_dir>` — the generic lab IgWeb runner (LAB-IGNITER-WEB-RUNNER-P12).
//!
//! An Igniter-only author writes `routes.igweb` + handler `.ig` + `igweb.toml` (no Rust) and runs this
//! pre-built binary. It loads the manifest, builds the app via `igniter_web::build_igweb_app`, composes
//! P8 middleware from the manifest, holds the app in `ReloadableApp`, and serves a bounded loopback
//! `serve_loop`. The server owns transport/loop/reload; the app owns routing/domain. Lab v0 — NOT a
//! stable CLI. Loopback only; no public bind; no live effect execution.

use igniter_server::reload::ReloadableApp;
use igniter_server::serving_loop::{serve_loop, ServingPolicy};
use igniter_web::runner::build_app_from_dir;
use std::net::TcpListener;
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let app_dir = PathBuf::from(std::env::args().nth(1).ok_or("usage: igweb-serve <app_dir>")?);
    let (app, manifest) = build_app_from_dir(&app_dir)?;

    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    let addr = listener.local_addr()?;
    let source_count = igniter_web::runner::resolve_sources(&app_dir, &manifest)?.len();
    let max = manifest.max_requests.unwrap_or(1024);
    println!(
        "igweb-serve: app_dir={} entry={} sources={} listening http://{} (loopback, bounded to {} request(s))",
        app_dir.display(), manifest.entry, source_count, addr, max
    );

    // The host owns the loop + reload unit; the manifest-built (composed) app is the swap unit.
    let reloadable = ReloadableApp::new(app);
    let report = serve_loop(&listener, &reloadable, &ServingPolicy::new(max).loopback_only())?;
    println!("igweb-serve: served {} request(s); exiting", report.requests_served);
    Ok(())
}
