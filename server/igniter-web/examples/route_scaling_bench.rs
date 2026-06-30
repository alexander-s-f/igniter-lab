// examples/route_scaling_bench.rs — LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2
//
// How does IgWeb dispatch cost scale with ROUTE COUNT? P1 found later routes dispatch slower (more
// `matches(req.path, …)` arms in the generated `Serve` if-chain); P4 added a process-global regexp cache
// so patterns compile once. This harness turns that "latent" worry into a measured curve: it SYNTHESIZES
// authored `.igweb` + `.ig` apps with 10 / 100 / 500 routes, separates compile/load from dispatch, and
// times the early / middle / late / miss dispatch positions.
//
// LAB-LOCAL timing for trend comparison only — NOT a public performance claim, NO Rails/Ruby/Rust
// comparison. Zero dependencies (`std::time::Instant`). No DB, no network, no env vars. The process exits
// non-zero ONLY on a behavior error (wrong status), never on timing.
//
// Run:  cargo run --example route_scaling_bench   (add --release for a steadier read)

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use igniter_server::protocol::{ServerApp, ServerDecision, ServerRequest};
use igniter_web::{build_igweb_app, IgWebBuildInput};
use serde_json::{json, Value};

// P4 (LAB-LANG-REGEXP-RUNTIME-CACHE) landed a process-global compiled-regex cache in `igniter-vm`; this
// run reflects the tree WITH that cache. (Verified by reading `igniter-vm/src/vm.rs` `cached_regex`.)
const REGEXP_CACHE_P4_PRESENT: bool = true;

const DEFAULT_ROUTE_COUNTS: [usize; 3] = [10, 50, 90];
const DISPATCH_ITERS: usize = 1000;

/// Route counts from argv (e.g. `-- 10 50 90`), else the default set. Lets a single N be probed in its own
/// process — needed because the typechecker stack-overflows (aborts) on very deep route chains (see doc).
fn route_counts() -> Vec<usize> {
    let from_args: Vec<usize> = std::env::args()
        .skip(1)
        .filter_map(|a| a.parse().ok())
        .collect();
    if from_args.is_empty() {
        DEFAULT_ROUTE_COUNTS.to_vec()
    } else {
        from_args
    }
}

/// N param routes `/r{i}/:id -> Handler{i}` + N matching handlers. Each route is a distinct anchored
/// pattern, so a request walks the generated `Serve` if-chain to its arm — the depth = route position.
fn gen_handlers(n: usize) -> String {
    let mut s = String::from("module SynthHandlers\nimport IgWebPrelude\n");
    for i in 0..n {
        s.push_str(&format!(
            "pure contract Handler{i} {{\n  input req : Request\n  input id : Option[String]\n  compute d : Decision = Respond {{ status: 200, body: \"ok\" }}\n  output d : Decision\n}}\n"
        ));
    }
    s
}

fn gen_routes(n: usize) -> String {
    let mut s = String::from("app SynthWeb entry Serve {\n  handlers SynthHandlers\n");
    for i in 0..n {
        s.push_str(&format!("  route GET \"/r{i}/:id\" -> Handler{i}\n"));
    }
    s.push_str("}\n");
    s
}

fn write_synth_app(n: usize) -> Vec<PathBuf> {
    let dir = std::env::temp_dir().join(format!("igweb_scale_{}_{}", n, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let h = dir.join("handlers.ig");
    let r = dir.join("routes.igweb");
    std::fs::write(&h, gen_handlers(n)).unwrap();
    std::fs::write(&r, gen_routes(n)).unwrap();
    vec![h, r]
}

struct Scenario {
    name: String,
    ok: bool,
    samples_us: Vec<u128>,
    note: Option<String>,
}

impl Scenario {
    fn to_json(&self) -> Value {
        let mut s = self.samples_us.clone();
        s.sort_unstable();
        let n = s.len();
        let mut obj = json!({
            "name": self.name,
            "ok": self.ok,
            "n": n,
            "total_us": s.iter().sum::<u128>() as u64,
            "min_us": s.first().copied().unwrap_or(0) as u64,
            "median_us": if n == 0 { 0 } else { s[n / 2] } as u64,
            "max_us": s.last().copied().unwrap_or(0) as u64,
        });
        if let Some(note) = &self.note {
            obj.as_object_mut()
                .unwrap()
                .insert("note".to_string(), Value::String(note.clone()));
        }
        obj
    }
}

/// Build the synth app, timing compile/load SEPARATELY from dispatch. A build FAILURE (e.g. the deep
/// nested-if SemanticIR hitting serde's recursion limit at high N) is recorded as a non-ok scenario with
/// the error, not a panic — that is the measured wall, not a harness bug. (A raw typechecker stack
/// overflow at extreme N still aborts the process; see the proof doc for the practical ceiling.)
fn time_build(
    n: usize,
    sources: &[PathBuf],
) -> (Option<Arc<dyn ServerApp + Send + Sync>>, Scenario) {
    let t = Instant::now();
    let built = build_igweb_app(IgWebBuildInput {
        sources: sources.to_vec(),
        entry: "Serve".to_string(),
    });
    let us = t.elapsed().as_micros();
    match built {
        Ok(app) => (
            Some(app),
            Scenario {
                name: format!("compile_load_routes_{n}"),
                ok: true,
                samples_us: vec![us],
                note: None,
            },
        ),
        Err(e) => (
            None,
            Scenario {
                name: format!("compile_load_routes_{n}"),
                ok: false,
                samples_us: vec![us],
                note: Some(format!("BUILD FAILED at {n} routes: {e:?}")),
            },
        ),
    }
}

fn time_dispatch(
    label: &str,
    app: &(dyn ServerApp + Send + Sync),
    path: &str,
    expect_status: u16,
) -> Scenario {
    let mut samples = Vec::with_capacity(DISPATCH_ITERS);
    let mut ok = true;
    for _ in 0..DISPATCH_ITERS {
        let req = ServerRequest::new("GET", path, Value::Null);
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
        name: label.to_string(),
        ok,
        samples_us: samples,
        note: None,
    }
}

fn main() {
    let counts = route_counts();
    let mut scenarios: Vec<Scenario> = Vec::new();

    for &n in &counts {
        let sources = write_synth_app(n);
        let (app_opt, build_scn) = time_build(n, &sources);
        let build_ok = build_scn.ok;
        scenarios.push(build_scn);
        let app = match app_opt {
            Some(a) => a,
            None => {
                // build hit the wall (e.g. serde recursion limit on the deep nested-if IR) — recorded
                // above; skip dispatch for this N and keep going.
                eprintln!(
                    "note: build failed at {n} routes (the route-lowering scaling wall) — see JSON"
                );
                continue;
            }
        };
        let _ = build_ok;

        // warm up: prime the regexp cache for this app's patterns (so dispatch measures match, not first-touch compile).
        let _ = app.call(ServerRequest::new(
            "GET",
            &format!("/r{}/123", n - 1),
            Value::Null,
        ));

        // early / middle / late / miss — the route-chain depth curve.
        let first = "/r0/123".to_string();
        let middle = format!("/r{}/123", n / 2);
        let last = format!("/r{}/123", n - 1);
        let miss = "/nope/123".to_string(); // matches no route → 404, walks every arm.

        scenarios.push(time_dispatch(
            &format!("dispatch_{n}_first"),
            &*app,
            &first,
            200,
        ));
        scenarios.push(time_dispatch(
            &format!("dispatch_{n}_middle"),
            &*app,
            &middle,
            200,
        ));
        scenarios.push(time_dispatch(
            &format!("dispatch_{n}_last"),
            &*app,
            &last,
            200,
        ));
        scenarios.push(time_dispatch(
            &format!("dispatch_{n}_miss"),
            &*app,
            &miss,
            404,
        ));
    }

    let all_ok = scenarios.iter().all(|s| s.ok);
    // exit-1 is reserved for DISPATCH behavior errors (wrong status). A build wall at high N is a measured
    // finding (recorded as a non-ok compile_load scenario), not a harness failure.
    let dispatch_behavior_ok = scenarios
        .iter()
        .filter(|s| s.name.starts_with("dispatch_"))
        .all(|s| s.ok);
    let report = json!({
        "kind": "igniter_web_route_scaling_bench_v0",
        "warning": "lab-local timing for trend comparison only; NOT a public performance claim",
        "regexp_cache_p4_present": REGEXP_CACHE_P4_PRESENT,
        "route_counts": counts,
        "dispatch_iters": DISPATCH_ITERS,
        "app_shape": "synthetic: N param routes `/r{i}/:id -> Handler{i}`, authored .igweb + .ig in tempdir",
        "all_ok": all_ok,
        "scenarios": scenarios.iter().map(Scenario::to_json).collect::<Vec<_>>(),
    });
    println!("{}", serde_json::to_string_pretty(&report).unwrap());

    if !dispatch_behavior_ok {
        eprintln!(
            "FAIL: a dispatched route produced wrong behavior (not a timing or build-wall finding)"
        );
        std::process::exit(1);
    }
}
