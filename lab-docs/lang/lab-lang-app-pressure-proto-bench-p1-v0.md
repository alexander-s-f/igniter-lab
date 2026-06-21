# lab-lang-app-pressure-proto-bench-p1-v0 — proto-benchmark harness for app-pressure paths

**Card:** `LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1` · **Delegation:** `OPUS-LANG-APP-PRESSURE-PROTO-BENCH-P1`
**Status:** CLOSED (lab implementation-proof) — a **zero-dependency** `std::time::Instant` harness that
times the app-pressure contours (compile/load + per-request dispatch/render) of the authored Todo view
app, emitting machine-readable JSON. **Lab-local trend measurement only — NOT a public performance claim.
No DB/network/env; timing never causes failure.**
**Authority:** Lab tooling. One new example file; no production code change, no new dependency.

## Verify-first (live)

- **No `criterion`/bench dependency** anywhere in `igniter-web` (`Cargo.toml` is serde+tokio+path-deps) →
  **zero-dep `std::time::Instant`** is the smallest honest path (per card guidance).
- `examples/todo_server.rs` is a top-level example → an `examples/app_pressure_bench.rs` runs via
  `cargo run --example app_pressure_bench`. The crate owns it (no separate tool crate needed).
- Public API confirmed: `igniter_web::build_igweb_app(IgWebBuildInput { sources, entry })`,
  `igniter_server::protocol::{ServerRequest::new, ServerApp::call}`. The **render happens INSIDE**
  `IgWebServerApp::call` (via `map_decision` → `igniter_render_html`), so timing `app.call` on a
  RenderView route is the real per-request render cost.
- The harness runs entirely **without DB/network/env** (the Todo view app is fake-data, no Postgres).

## What it measures (5 scenarios, no DB)

| Scenario | Contour |
|---|---|
| `compile_load_todo_view_app` | `build_igweb_app` = compile + **desugar** + machine-load of `todo_views.ig` + `routes.igweb` |
| `dispatch_render_list_html` | `GET /todos/list-html` → VM dispatch `Serve` → `map` domain→nodes → `call_contract` helpers → `render_html` → escaped HTML |
| `dispatch_render_pending_html` | `GET /todos/pending-html` → `filter` then `map` → render |
| `dispatch_respond_view_json` | `GET /` → `RespondView` structured JSON (no HTML render) — cheaper baseline |
| `dispatch_respond_plain` | `GET /api/health` → plain `Respond` (fixed JSON body) |

**Deferred (explicit):** `effect_host_write_fake_commit` (structured `InvokeEffect` through a fake write
executor) needs the machine effect host + a fake executor — out of this zero-dep no-DB slice; sequenced to
P2 alongside the local-Postgres baseline.

**Desugar / zero-runtime-overhead:** the new language surfaces (string escapes, collection comprehensions,
signature-bound records) desugar to the **same SIR at compile time**, so any cost they add lands in
`compile_load_*`, never at dispatch. `compile_load_todo_view_app` is therefore the desugar-cost
measurement, and the per-request scenarios confirm zero runtime overhead by construction.

## Command + sample output

```text
$ cd server/igniter-web && cargo run --quiet --example app_pressure_bench
{
  "kind": "igniter_app_pressure_bench_v0",
  "warning": "lab-local timing for trend comparison only; NOT a public performance claim",
  "build_iters": 3, "dispatch_iters": 2000, "all_ok": true,
  "deferred": ["effect_host_write_fake_commit (needs machine effect host + fake executor — P2)"],
  "scenarios": [
    { "name": "compile_load_todo_view_app",  "ok": true, "n": 3,    "min_us": 33320, "median_us": 34013, "max_us": 35934 },
    { "name": "dispatch_render_list_html",   "ok": true, "n": 2000, "min_us": 1236,  "median_us": 1320,  "max_us": 2137 },
    { "name": "dispatch_render_pending_html","ok": true, "n": 2000, "min_us": 1334,  "median_us": 1423,  "max_us": 1567 },
    { "name": "dispatch_respond_view_json",  "ok": true, "n": 2000, "min_us": 1033,  "median_us": 1105,  "max_us": 1428 },
    { "name": "dispatch_respond_plain",      "ok": true, "n": 2000, "min_us": 2030,  "median_us": 2139,  "max_us": 2494 }
  ]
}
```
(Numbers are an unoptimized debug run on one machine — illustrative, not authoritative.)

### Honest observation (a signal, not a claim)

`dispatch_respond_plain` (`/api/health`) is *slower* than the render routes — counterintuitive until you
see why: `/api/health` is **late in the route match-chain**, so the generated `Serve` contract runs more
`matches(req.path, …)` regex checks before reaching it, while `/` and `/todos/list-html` are earlier. So
**per-request cost is dominated by route position (linear regex match-chain depth), not by Respond-vs-render**.
That is exactly the kind of trend signal this harness exists to surface; it is a lab-local observation, not
a performance claim, and a future optimization (e.g. a dispatch table) would show up here.

## Why this is NOT a public performance claim

- Single machine, debug build, no statistical rigor, no warmup-isolation beyond a coarse pass.
- No comparison to Rails/Ruby/Rust (the card forbids it).
- Absolute microseconds are not portable; only **same-machine, same-build deltas across revisions** are
  meaningful. The report carries a `warning` field saying so, and the harness exits non-zero **only** on a
  behavior error (a non-200 response), **never** on timing.

## How to compare future runs safely

Run on the **same machine + same build profile** before and after a change; compare `median_us` per
scenario as a **relative delta**. Treat anything under a few× variance as noise. Add `--release` for a
steadier read. Never gate CI on absolute numbers.

## What this harness cannot measure yet

- Real effect-host write (fake executor + receipt/replay) — deferred to P2.
- Local Postgres read/write contours — deferred until correctness lands (P8) and a no-DB skip is wired.
- Concurrency / throughput under load (this is single-threaded latency).
- VM hot-spots / allocation profile (that is `…-HOTPATH-READINESS-P3`, a profiler pass, not timings).

## Acceptance — mapping

- [x] Runs without DB/network/env vars.
- [x] ≥4 app-pressure scenarios (5: compile_load + 4 dispatch).
- [x] Machine-readable JSON.
- [x] Labels itself lab-local / no public perf claim (`warning` field).
- [x] No absolute timing threshold causes failure.
- [x] Failures mean behavior errors (status check → `ok:false` → exit 1), not "too slow".
- [x] Structured `InvokeEffect.input` path **explicitly deferred** (in `deferred` field + here).
- [x] A language-surface desugar path measured (`compile_load`) + zero-runtime-by-construction explained.
- [x] Existing tests green for touched crate (`igniter-web` all suites; e2e `--features machine` 2 passed).
- [x] No production code path changed (one example file only).
- [x] No new dependency (verify-first: none present; zero-dep chosen).
- [x] `git diff --check` clean.

## Verification

```text
$ cargo run --example app_pressure_bench                                   → JSON, all_ok=true (above)
$ cd server/igniter-web && cargo test                                      → all suites green (incl. todo_view_app 14)
$ cargo test --features machine --test todo_postgres_api_read_write_e2e_tests → 2 passed
$ git diff --check                                                         → clean (only the new example added)
```

## Closed scope (honored)

No Criterion; no CI perf thresholds; no public performance claim; no Rails/Ruby/Rust comparison; no local
Postgres/network/DSN; no optimizer work; no runtime refactor. One example file; no production code change.

## Next

1. `LAB-LANG-APP-PRESSURE-BENCH-BASELINE-P2` — capture a named baseline artifact (and add the fake
   effect-host write scenario) after local-Postgres P8.
2. `LAB-LANG-RUNTIME-HOTPATH-READINESS-P3` — profile actual hot spots (the route match-chain observation
   above is a candidate) before any optimization.
3. `LAB-TODOAPP-API-PROTO-BENCH-P*` — add local-Postgres contours once correctness is proven (no-DB skip).

---

*Lab implementation-proof. Compiled 2026-06-21; zero-dep harness, 5 scenarios all `ok`, igniter-web suites
green + e2e 2 passed, `git diff --check` clean. Lab-local trend timing only — no public performance claim.*
