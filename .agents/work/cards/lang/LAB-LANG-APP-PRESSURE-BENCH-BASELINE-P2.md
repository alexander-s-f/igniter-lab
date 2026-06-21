# LAB-LANG-APP-PRESSURE-BENCH-BASELINE-P2 - Named lab baseline for app-pressure performance

Status: CLOSED
Lane: parallel / language-surface / performance evidence
Type: evidence
Delegation code: OPUS-LANG-APP-PRESSURE-BENCH-BASELINE-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1` created a zero-dependency lab-local benchmark harness for TodoApp-
shaped paths. `LAB-IGNITER-WEB-ROUTE-SCALING-BENCH-P2` added route scaling evidence. P4/P5/P6-style work
will change route lowering and host contours, so we need a named baseline artifact for comparison.

This is not a public performance claim. It is a local trend baseline.

## Goal

Capture one named baseline packet from the current repo state:

- app-pressure bench output;
- route-scaling bench output;
- targeted test counts;
- current commit hash;
- machine/env caveats;
- known limitations and non-claims.

The result should be easy to compare against after prefix-grouped lowering.

## Verify First

Read:

- `server/igniter-web/examples/app_pressure_bench.rs`
- `server/igniter-web/examples/route_scaling_bench.rs`
- `lab-docs/lang/lab-lang-app-pressure-proto-bench-p1-v0.md`
- `lab-docs/lang/lab-igniter-web-route-scaling-bench-p2-v0.md`
- latest git commit hash

Confirm whether P4 prefix-grouped lowering has already landed. If it has landed, label this as
`post-prefix-grouped` instead of `pre-prefix-grouped`.

## Required Measurements

Run:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example app_pressure_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example route_scaling_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler && cargo test --test igweb_lowering_tests
```

Optional:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
```

## Required Acceptance

- [x] Records exact git commit hash (`90d5a4e…`) + uncommitted-P4 caveat.
- [x] Records exact commands.
- [x] Stores raw benchmark JSON snippets / values (both benches).
- [x] Labels output lab-local / no public perf claim.
- [x] Separates compile/load from dispatch.
- [x] Calls out route-position effect — **now REMOVED**.
- [x] Calls out the route-count wall — **REMOVED** (118/200/500 OK vs P2 115/118).
- [x] Does not introduce thresholds.
- [x] Does not change production code (the modified `igweb.rs` is the neighbour's P4).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-lang-app-pressure-bench-baseline-p2-v0.md` — named lab-local baseline at
commit **`90d5a4e`** (with an **uncommitted neighbour P4 `igweb.rs`** in the tree → labelled
**post-prefix-grouped**). No production code change; `git diff --check` clean.

**Two headline deltas vs P1 (pre-prefix-grouped):**
1. **Route-count wall REMOVED** — N = **118 / 200 / 500** all compile + dispatch (P2 had 115 ok / 118 fail).
2. **Route-position penalty REMOVED** — `app_pressure_bench` `/api/health` (a late route) went from the
   **slowest** (median **2139 µs** in P1) to **1450 µs** (tied cheapest); `route_scaling_bench`
   first ≈ middle ≈ last ≈ miss within each N.

**Honest counter-finding:** the synthetic `route_scaling_bench` uses **all-distinct first segments**
(`/r{i}/:id`), so there's no shared prefix to group — dispatch still scales ~linearly with N (10→1.2 ms,
50→5.6 ms, 90→9.9 ms). **The prefix-grouping *dispatch win* is therefore unmeasured here** and needs the
**SparkCRM-shaped shared-prefix fixture (P5 §Q9)**. compile/load grows ≈O(N) (33/144/261 ms at 10/50/90).

**Tests:** igniter-web all green (todo_view_app 14 …); `igweb_lowering_tests` **11 passed** (P4 lowering is
behavior-preserving so far). **Next:** re-capture a clean baseline once P4 commits, and add a shared-prefix
route-scaling fixture to measure the grouping dispatch win.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-app-pressure-bench-baseline-p2-v0.md
```

Update this card with a closing report.

## Closed Scope

- No optimizer implementation.
- No Criterion dependency.
- No CI perf gate.
- No public speed claim.
- No comparison against Rails/Ruby/Rust as a claim.
