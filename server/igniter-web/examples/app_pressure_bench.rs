// examples/app_pressure_bench.rs — LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1
//
// A tiny, ZERO-DEPENDENCY proto-benchmark harness for the app-pressure contours (compile/load + per-
// request dispatch/render) of the authored Todo view app. It uses `std::time::Instant` only.
//
// IMPORTANT: this is LAB-LOCAL timing for trend comparison across revisions — it is NOT a public
// performance claim, NOT a benchmark against Rails/Ruby/Rust, and timing never causes a failure. The
// process exits non-zero ONLY if a measured path produces wrong BEHAVIOR (e.g. a non-200 response or a
// build error), never because something was "slow". No DB, no network, no env vars.
//
// Run:  cargo run --example app_pressure_bench   (add --release for a steadier read)

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest};
use igniter_web::{build_igweb_app, IgWebBuildInput};
use serde_json::{json, Value};

fn example_dir(name: &str) -> PathBuf {
    PathBuf::from(format!("{}/examples/{}", env!("CARGO_MANIFEST_DIR"), name))
}

fn todo_view_sources() -> Vec<PathBuf> {
    ["todo_views.ig", "routes.igweb"]
        .iter()
        .map(|f| example_dir("todo_view_app").join(f))
        .collect()
}

fn build_view_app() -> Arc<dyn ServerApp + Send + Sync> {
    build_igweb_app(IgWebBuildInput {
        sources: todo_view_sources(),
        entry: "Serve".to_string(),
    })
    .expect("build todo_view_app (compile + machine load) must succeed")
}

/// Min / median / max / total micros over a sample, plus an `ok` behavior flag.
struct Scenario {
    name: &'static str,
    ok: bool,
    samples_us: Vec<u128>,
}

impl Scenario {
    fn to_json(&self) -> Value {
        let mut sorted = self.samples_us.clone();
        sorted.sort_unstable();
        let n = sorted.len();
        let total: u128 = sorted.iter().sum();
        let median = if n == 0 { 0 } else { sorted[n / 2] };
        json!({
            "name": self.name,
            "ok": self.ok,
            "n": n,
            "total_us": total as u64,
            "min_us": sorted.first().copied().unwrap_or(0) as u64,
            "median_us": median as u64,
            "max_us": sorted.last().copied().unwrap_or(0) as u64,
        })
    }
}

/// Time `build_igweb_app` (the compile + desugar + machine-load contour). New language surfaces
/// (string escapes, comprehensions, signature-bound records) desugar to the SAME SIR at compile time,
/// so any cost they add lands HERE, never at dispatch — this scenario is the desugar-cost measurement,
/// and the per-request scenarios below show the surfaces add zero runtime overhead by construction.
fn bench_compile_load(iters: usize) -> Scenario {
    let mut samples = Vec::with_capacity(iters);
    for _ in 0..iters {
        let t = Instant::now();
        let app = build_view_app();
        samples.push(t.elapsed().as_micros());
        // touch the app so the optimizer can't elide the build
        let _ = app.identity();
    }
    Scenario {
        name: "compile_load_todo_view_app",
        ok: true,
        samples_us: samples,
    }
}

/// Time `app.call` for a route. For a render route this includes the full per-request contour:
/// VM dispatch of `Serve` → filter/map → `call_contract` node helpers → `igniter_render_html`. The
/// render happens INSIDE `IgWebServerApp::call` (via `map_decision`), so this is the real render cost.
/// `ok` is a BEHAVIOR check (expected status), never a timing threshold.
fn bench_dispatch(
    name: &'static str,
    app: &(dyn ServerApp + Send + Sync),
    method: &str,
    path: &str,
    expect_status: u16,
    iters: usize,
) -> Scenario {
    let mut samples = Vec::with_capacity(iters);
    let mut ok = true;
    for _ in 0..iters {
        let req = ServerRequest::new(method, path, Value::Null);
        let t = Instant::now();
        let decision = app.call(req);
        samples.push(t.elapsed().as_micros());
        let status_ok = match &decision {
            ServerDecision::Respond { response } => response.status == expect_status,
            _ => false,
        };
        if !status_ok {
            ok = false;
        }
    }
    Scenario {
        name,
        ok,
        samples_us: samples,
    }
}

fn main() {
    // Warm up the compiler/runtime once before any measured run (caches, allocator, JIT-of-nothing).
    let app = build_view_app();
    for _ in 0..50 {
        let _ = app.call(ServerRequest::new("GET", "/todos/list-html", Value::Null));
    }

    let build_iters = 3; // builds are expensive; a few is enough for a min/median/max read.
    let dispatch_iters = 2000;

    let mut scenarios: Vec<Scenario> = Vec::new();
    scenarios.push(bench_compile_load(build_iters));
    // RenderView contours: domain collection → filter/map → nodes → escaped HTML bytes.
    scenarios.push(bench_dispatch(
        "dispatch_render_list_html",
        &*app,
        "GET",
        "/todos/list-html",
        200,
        dispatch_iters,
    ));
    scenarios.push(bench_dispatch(
        "dispatch_render_pending_html",
        &*app,
        "GET",
        "/todos/pending-html",
        200,
        dispatch_iters,
    ));
    // RespondView JSON contour (structured view descriptor, no HTML render) — a cheaper dispatch baseline.
    scenarios.push(bench_dispatch(
        "dispatch_respond_view_json",
        &*app,
        "GET",
        "/",
        200,
        dispatch_iters,
    ));
    // Plain Respond contour (the cheapest dispatch: a fixed JSON body, no view).
    scenarios.push(bench_dispatch(
        "dispatch_respond_plain",
        &*app,
        "GET",
        "/api/health",
        200,
        dispatch_iters,
    ));

    let all_ok = scenarios.iter().all(|s| s.ok);
    let report = json!({
        "kind": "igniter_app_pressure_bench_v0",
        "warning": "lab-local timing for trend comparison only; NOT a public performance claim",
        "build_iters": build_iters,
        "dispatch_iters": dispatch_iters,
        "deferred": ["effect_host_write_fake_commit (needs machine effect host + fake executor — P2)"],
        "all_ok": all_ok,
        "scenarios": scenarios.iter().map(Scenario::to_json).collect::<Vec<_>>(),
    });
    println!("{}", serde_json::to_string_pretty(&report).unwrap());

    if !all_ok {
        eprintln!("FAIL: a measured path produced wrong behavior (not a timing failure)");
        std::process::exit(1);
    }
}
