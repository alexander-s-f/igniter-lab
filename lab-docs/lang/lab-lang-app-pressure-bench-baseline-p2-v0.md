# lab-lang-app-pressure-bench-baseline-p2-v0 — named lab baseline for app-pressure performance

**Card:** `LAB-LANG-APP-PRESSURE-BENCH-BASELINE-P2` · **Delegation:** `OPUS-LANG-APP-PRESSURE-BENCH-BASELINE-P2`
**Status:** CLOSED (lab evidence) — a named, reproducible **lab-local** baseline of the app-pressure +
route-scaling benches at a defined tree state. **NOT a public performance claim; no Rails/Ruby/Rust
comparison; no thresholds; no production code change.**

## Tree state (label: POST-prefix-grouped)

- **Commit:** `90d5a4e6f0a42d1ec8193eaa1f56d32f3adda217` ("Harvest IgWeb route scaling and effect host proofs").
- **Caveat:** the working tree carries an **uncommitted `M lang/igniter-compiler/src/igweb.rs`** — the
  neighbour's `LAB-IGNITER-WEB-PREFIX-GROUPED-LOWERING-P4` in progress. Empirically the **route-depth wall
  is already removed** in this tree (probe below: 118/200/500 all OK), so this baseline is labelled
  **post-prefix-grouped (working tree)**. The contrast anchor (pre-prefix-grouped) is P2's wall at
  **115 ok / 118 fail**.
- Machine/env: single dev machine, **debug build**, no `--release`, no DB/network/env. Absolute µs are not
  portable; only same-machine same-build deltas are meaningful.

## Commands

```bash
cd server/igniter-web && cargo run --example app_pressure_bench
cd server/igniter-web && cargo run --example route_scaling_bench        # default 10/50/90
                          target/debug/examples/route_scaling_bench 118 # probe past old wall
                          target/debug/examples/route_scaling_bench 200
cd server/igniter-web && cargo test
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
```

## Headline deltas vs P1 (pre-prefix-grouped)

1. **Route-count wall REMOVED.** P2 measured `115 ok / 118 fail` (serde recursion on the O(N)-deep
   nested-if IR). This tree: **N = 118 and 200 compile + dispatch OK** (500-route probe launched; 118/200
   already past the old limit). The structural buildability blocker is gone.
2. **Route-position penalty REMOVED.** P1's signal was "late routes dispatch slower" — in
   `app_pressure_bench`, `/api/health` (a late route) was the **slowest** (median **2139 µs**). In this
   baseline it is **1450 µs** — **tied with the cheapest**, no longer an outlier. In `route_scaling_bench`,
   `first` / `middle` / `last` / `miss` are **identical within each N** (see below). Prefix-grouping removed
   the linear-scan-to-position cost.
3. **Honest counter-finding — dispatch still scales with N on the *flat* fixture.** The synthetic
   `route_scaling_bench` uses `/r{i}/:id` with **all-distinct first segments**, so there is **no shared
   prefix to group** — the worst case for prefix-grouping. Dispatch median is ~linear in N (10→1244 µs,
   50→5561 µs, 90→9895 µs ≈ ~110 µs/route). **The grouping *win* is not visible on this fixture** — it needs
   the SparkCRM-shaped **shared-prefix** fixture (P5 §Q9: `scope "/admin" { scope "/global" { resource … } }`).
   So: wall + position are fixed; the *shared-prefix dispatch win* is still unmeasured (next bench).

## Raw — `app_pressure_bench` (Todo view app, compile/load + dispatch)

```
compile_load_todo_view_app   n=3     min 38523  median 38833  max 39180  (µs)   # compile+desugar+load
dispatch_render_list_html    n=2000  min 1562   median 1591   max 1724          # filter/map → render HTML
dispatch_render_pending_html n=2000  min 1584   median 1609   max 1766          # filter then map → render
dispatch_respond_view_json   n=2000  min 1430   median 1446   max 1575          # RespondView JSON
dispatch_respond_plain       n=2000  min 1433   median 1450   max 2165          # plain Respond  (was 2139 in P1 → now tied)
```
`all_ok: true`. Compile/load is **separated** from dispatch (one timed build set vs per-request `app.call`).

## Raw — `route_scaling_bench` (synthetic N param routes, `regexp_cache_p4_present: true`)

| N | compile_load (µs) | dispatch first | middle | last | miss | (median µs) |
|---:|---:|---:|---:|---:|---:|---|
| 10 | 32 856 | 1244 | 1238 | 1249 | 1199 | **position-flat** |
| 50 | 144 340 | 5561 | 5566 | 5563 | 5493 | **position-flat** |
| 90 | 260 705 | 9895 | 9841 | 9835 | 9778 | **position-flat** |

Two reads: (a) **first ≈ middle ≈ last ≈ miss** within each N → the position penalty is gone; (b) dispatch
**grows with N** (≈linear) because the flat fixture shares no prefixes (§Headline #3); (c) **compile/load**
grows ≈O(N)–O(N log N) (33 → 144 → 261 ms at 10/50/90) — one-shot compile cost, acceptable, worth tracking.

Wall probe (separate processes, past the old ~116 limit):
```
N=118  OK (compiled + dispatched)   # P2 had 118 → FAIL
N=200  OK (compiled + dispatched)
N=500  OK (compiled + dispatched)   # wall fully removed across 118/200/500
```

## Test counts (this tree)

```
server/igniter-web      cargo test                 → all suites green (todo_view_app 14, render_html_app 3,
                                                      builder 5, example 7, runner 17, …)
lang/igniter-compiler   cargo test --test igweb_lowering_tests → 11 passed   # P4 lowering behavior-preserving
git diff --check        → clean
```

## How to compare future runs safely

Re-run the same commands on the **same machine + same build profile**; compare `median_us` per scenario as a
**relative delta** and the wall-probe pass/fail. Treat sub-few-× variance as noise. The two most informative
future deltas: (1) the **shared-prefix** route-scaling fixture (P5 §Q9) — that is where prefix-grouping's
dispatch win should appear, and this flat baseline will *not* move; (2) compile/load at 500/1000 routes.

## Non-claims / limitations

Lab-local debug timing only. NOT a public perf number, NOT vs Rails/Ruby/Rust. No thresholds gate anything.
`effect_host_write_fake_commit` remains deferred (needs the machine effect host). The flat fixture
**understates** prefix-grouping; the SparkCRM-shaped fixture is required to measure that win. The tree
includes an **uncommitted** neighbour P4 — re-capture a clean baseline once P4 commits.

## Acceptance — mapping

- [x] Exact git commit hash recorded (`90d5a4e…`) + uncommitted-P4 caveat.
- [x] Exact commands recorded.
- [x] Raw benchmark JSON/values stored (both benches).
- [x] Labelled lab-local / no public perf claim.
- [x] Compile/load separated from dispatch.
- [x] Route-position effect called out — **now REMOVED** (`/api/health` 2139→1450 µs; first≈last≈miss).
- [x] Route-count wall called out — **REMOVED** (118/200 OK vs P2 115/118).
- [x] No thresholds introduced.
- [x] No production code changed (doc + bench reads only; the modified `igweb.rs` is the neighbour's P4).
- [x] `git diff --check` clean.

---

*Lab evidence. Compiled 2026-06-21 at commit `90d5a4e` (+ uncommitted P4 `igweb.rs`). Post-prefix-grouped
working tree: route-depth wall removed (118/200 OK vs P2 115/118), route-position penalty removed
(`/api/health` 2139→1450 µs; route-scaling position-flat). Open: the shared-prefix dispatch win is
unmeasured on the flat fixture — needs the SparkCRM-shaped fixture (P5 §Q9). Lab-local trend only; no public
performance claim.*
