# LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2 - Measure IgWeb route cost at 10/100/500 routes

Status: CLOSED
Lane: parallel / IgWeb / performance
Type: measurement-proof
Delegation code: OPUS-IGNITER-WEB-ROUTE-SCALING-BENCH-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1` produced the first app-pressure benchmark harness and found that route
position affects request cost. The immediate hot-path suspicion is regex recompilation in the VM; P4 owns the
runtime cache fix.

This card owns the second question:

```text
After (or before, if P4 is not merged yet) regexp-cache, how does IgWeb dispatch cost scale with route count?
```

We need a curve before designing a route index. Do not jump to a trie/router implementation here.

## Goal

Extend or add a zero-dependency bench harness that synthesizes IgWeb apps with route counts:

```text
10 routes
100 routes
500 routes
```

and measures early / middle / late / miss dispatch cases.

Output must be machine-readable JSON, explicitly labelled lab-local and non-public.

## Verify First

Read live code before editing:

- `server/igniter-web/examples/app_pressure_bench.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/tests/builder_tests.rs`
- `lang/igniter-compiler/src/igweb.rs`
- `lab-docs/lang/lab-lang-app-pressure-proto-bench-p1-v0.md`
- current status of `LAB-LANG-REGEXP-RUNTIME-CACHE-P4` if it has already landed

Confirm or correct:

- whether synthetic apps can be generated in a tempdir using `build_igweb_app`;
- whether compile/load time should be separated from dispatch time;
- whether `Serve` route order is preserved exactly;
- whether benchmark should run under default only or `--features machine`;
- whether route count 500 is practical inside the local harness.

Live code wins over this card.

## Measurement Shape

Preferred scenarios:

```text
compile_load_routes_10
compile_load_routes_100
compile_load_routes_500
dispatch_10_first / middle / last / miss
dispatch_100_first / middle / last / miss
dispatch_500_first / middle / last / miss
```

Route patterns should include at least:

- exact static route: `/r/123`
- param route: `/items/:id`
- one grouped same-path method case if cheap

Keep the first slice simple. Static routes alone are acceptable if param routes make fixture generation too
large, but document the limitation.

## Required Acceptance

- [x] Bench runs with no DB, no network, no env vars.
- [x] Bench uses generated authored `.igweb` + `.ig` files (real `build_igweb_app`), not Rust-only shortcuts.
- [x] Compile/load timing separated from dispatch timing.
- [x] Measures first/middle/last/miss — **10/50/90** (the 100/500 target is **not buildable**: a ~116-route
      compile wall; probed 115 ok / 118 fail; documented).
- [x] Stable JSON with scenario names, iterations, median timing, warning/no-claim field.
- [x] Records `regexp_cache_p4_present: true`.
- [x] No Criterion / benchmark dependency (zero-dep `std::time::Instant`).
- [x] No `igniter-server` change.
- [x] No route trie/index implemented.
- [x] `app_pressure_bench` remains runnable (`all_ok:true`).
- [x] `igniter-web cargo test` green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Deliverable:** `server/igniter-web/examples/route_scaling_bench.rs` — zero-dep harness synthesizing
authored `.igweb`+`.ig` apps with N param routes, timing compile/load separately from first/middle/last/miss
dispatch. Proof doc: `lab-docs/lang/lab-igniter-web-route-scaling-bench-p2-v0.md`. One new file; no
production code change.

**Headline finding (bigger than the card expected):** the 100/500 target is **not achievable** — IgWeb route
lowering emits an **O(N)-deep nested-if SemanticIR**, and the machine LOAD's **serde recursion limit (~128)
is exceeded at ~116 routes** → `Load(SerializationError("recursion limit exceeded"))`. Probed exactly: **115
builds OK, 118 fails**; far beyond (~500) the typechecker stack-overflows. **An app with >115 routes cannot
be built today** — a hard structural ceiling, not a slowdown.

**Dispatch curve (10/50/90, P4 cache present, median_us):** scales ~linearly with N — a route-position
effect (last ≈ 1.35× first, ~25–28 µs/route) **plus** a base O(N) per-dispatch cost (first itself grows
839→3826→6984, consistent with the per-request fresh-VM + dispatch-table build). miss ≈ last (walks all
arms). compile/load super-linear (48→126→244 ms).

**Recommendation:** open a **route-index / flat-dispatch readiness** card — motivated mainly by the
**compile wall**, not dispatch µs. A flat, order-preserving route-table-as-data + bounded walk (NOT a
most-specific-wins trie) would remove **both** the recursion wall and the O(N) scan; app-owned index derived
from `.igweb`, server stays route-free, P18 priority preserved. Not implemented here (card forbids the trie).

**Proof — green:** default run `all_ok:true`; probe `-- 118` records the wall gracefully (non-ok
`compile_load` + `note`, no panic); `app_pressure_bench` intact; igniter-web `cargo test` green;
`git diff --check` clean.

## Required Verification

Run and report:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example app_pressure_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example route_scaling_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
git diff --check
```

If the bench is folded into `app_pressure_bench`, report the actual command and scenario list.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-route-scaling-bench-p2-v0.md
```

It must include:

- exact generated app shape;
- exact route counts;
- exact scenario table;
- raw JSON sample or compact excerpt;
- interpretation limited to lab-local trend signals;
- whether regex-cache was present;
- recommendation: no route index / route index readiness / more measurement.

Update this card with a closing report.

## Closed Scope

- No optimizer.
- No trie/radix router.
- No route reordering.
- No server route table.
- No public perf claim.
- No canon claim.
