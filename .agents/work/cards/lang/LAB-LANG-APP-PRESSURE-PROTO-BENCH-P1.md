# LAB-LANG-APP-PRESSURE-PROTO-BENCH-P1 - Proto benchmark harness for app-pressure paths

Status: CLOSED
Lane: parallel / language-surface / effectiveness
Type: implementation-proof
Delegation code: OPUS-LANG-APP-PRESSURE-PROTO-BENCH-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Language ergonomics are improving under TodoApp pressure, but effectiveness needs evidence too. The question
is not "is Igniter faster than imperative Rust/Ruby" yet. The first useful step is a stable local harness
that measures the same app-pressure paths across revisions.

This card must avoid public performance claims. It produces **lab-local measurement infrastructure** only:

```text
compile/load/dispatch/render/effect-host contours
  -> repeatable local timings
  -> JSON/CSV report
  -> no benchmark authority, no release claim
```

## Goal

Add a small proto-benchmark harness that can answer:

- how expensive is compiling/loading TodoApp-shaped `.ig` / `.igweb`?
- how expensive is dispatching a pure handler?
- how expensive is a read-continuation flow with fake host adapter?
- how expensive is a write-effect fake-host flow with receipt/replay?
- how much overhead do the new language surfaces add after desugar? (ideally no runtime overhead)

The harness should be stable enough for trend comparison, not statistically perfect.

## Verify First

Read live surfaces:

- `lang/igniter-compiler/tests/{signature_contract_surface_tests,fallible_binding_tests,collection_comprehension_tests}.rs`
- `server/igniter-web/tests/todo_postgres_api_read_write_e2e_tests.rs`
- `server/igniter-web/tests/todo_view_app_tests.rs`
- `server/igniter-web/src/lib.rs`
- `runtime/igniter-machine/tests/postgres_{read,write}_tests.rs`
- any existing bench/proof scripts:
  - `runtime/igniter-tbackend/bench.rb`
  - `lang/igniter-research/ivm-ruby-runtime/examples/*benchmark*`

Confirm or correct:

- whether Rust `criterion` is already a dependency anywhere;
- whether adding a benchmark dependency is acceptable, or a zero-dep `std::time::Instant` harness is better;
- which crate should own the harness (`server/igniter-web`, `lang/igniter-compiler`, or a lab tool);
- whether the harness can run without DB, network, or external services;
- how to avoid noisy CI-style failure from timing variance.

Live code wins over this card.

## Recommended Shape

Prefer **zero new dependencies** for P1 unless live code already has a bench dependency.

Suggested file:

```text
server/igniter-web/examples/app_pressure_bench.rs
```

or, if examples are not appropriate:

```text
tools/app_pressure_bench.rs
```

The harness should:

1. warm up once;
2. run bounded iteration counts;
3. print machine-readable JSON lines or a small JSON object;
4. report median-ish / min / max / total counts if cheap;
5. never fail based on absolute timing;
6. fail only if the path itself errors;
7. clearly label results as lab-local, not public perf claims.

## Candidate Scenarios

Measure at least four:

1. `compiler_load_todo_postgres_app` — build/load authored Todo app.
2. `dispatch_query_contract` — app-authored `ListTodosByAccount`.
3. `dispatch_continuation` — rows JSON into continuation.
4. `igweb_call_read_route_fake` or equivalent direct contour.
5. `effect_host_write_fake_commit` — structured `InvokeEffect` through fake write executor.
6. `render_view_html` — ViewArtifact/RenderView path.
7. `desugar_parity_compile` — signature/comprehension/fallible fixtures compile/load.

Do not require all seven if the harness would become too broad. Four good scenarios beat seven noisy ones.

## Output Contract

Example output:

```json
{
  "kind": "igniter_app_pressure_bench_v0",
  "warning": "lab-local timing only; not a public performance claim",
  "iterations": 1000,
  "scenarios": [
    { "name": "dispatch_query_contract", "ok": true, "n": 1000, "total_us": 12345, "min_us": 8, "max_us": 44 }
  ]
}
```

No secrets, DSNs, row values from external DBs, or host-specific absolute paths in the report unless needed for
debugging and explicitly scrubbed.

## Required Acceptance

- [x] Harness runs without DB/network/env vars.
- [x] Harness covers at least four app-pressure scenarios (5: compile_load + 4 dispatch).
- [x] Harness output is machine-readable JSON or JSONL.
- [x] Harness labels itself as lab-local / no public perf claim (`warning` field).
- [x] No absolute timing threshold causes failure.
- [x] Failures mean behavior errors, not "too slow".
- [x] Structured `InvokeEffect.input` path is explicitly deferred (P2, in `deferred` field).
- [x] At least one language-surface desugar path is measured (`compile_load`) + zero-runtime explained.
- [x] Existing tests remain green for touched crates.
- [x] No production code path changes (one example file only).
- [x] No new dependency (verify-first: none present; zero-dep `std::time::Instant`).
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Deliverable:** `server/igniter-web/examples/app_pressure_bench.rs` — a **zero-dependency**
`std::time::Instant` harness (no `criterion`; verify-first confirmed none present). Proof doc:
`lab-docs/lang/lab-lang-app-pressure-proto-bench-p1-v0.md`. One example file; no production code change.

**5 scenarios, no DB/network/env:** `compile_load_todo_view_app` (compile+desugar+machine-load),
`dispatch_render_list_html` / `dispatch_render_pending_html` (VM dispatch → filter/map → helpers →
`render_html`, render happens inside `app.call`), `dispatch_respond_view_json` (RespondView), and
`dispatch_respond_plain` (plain Respond). Output is machine-readable JSON with a `warning` field; the
process exits non-zero **only** on a behavior error (non-200), never on timing. `InvokeEffect` write
deferred to P2; desugar cost measured via `compile_load` (new surfaces desugar to the same SIR → zero
runtime overhead by construction).

**Honest finding (signal, not claim):** `/api/health` dispatched *slower* than the render routes because it
sits **late in the generated route match-chain** (more `matches(req.path,…)` regex checks) — i.e.
per-request cost is dominated by route position, not Respond-vs-render. A future dispatch-table optimization
would show up here. Lab-local only.

**Proof — all green:** `cargo run --example app_pressure_bench` → `all_ok:true`; igniter-web `cargo test`
all suites green (todo_view_app 14, …); e2e `--features machine` 2 passed; `git diff --check` clean.

**Next:** `…-BENCH-BASELINE-P2` (named baseline + fake effect-host write, after local-Postgres P8) →
`…-RUNTIME-HOTPATH-READINESS-P3` (profile the route match-chain hot spot before optimizing).

## Required Verification

Run and report:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo run --example app_pressure_bench
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_write_e2e_tests
git diff --check
```

If the harness lands in another crate, adjust commands and explain why.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-lang-app-pressure-proto-bench-p1-v0.md
```

It must include:

- exact scenarios measured;
- exact command/output sample;
- why results are not a public performance claim;
- how to compare future runs safely;
- what this harness cannot measure yet;
- next benchmark refinement.

Update this card with a closing report.

## Closed Scope

- No Criterion dependency unless live code makes it the obvious smallest path.
- No CI perf thresholds.
- No public performance claim.
- No comparison against Rails/Ruby/Rust as a claim.
- No local Postgres / network / DSN.
- No optimizer work.
- No broad runtime refactor.

## Suggested Next

If P1 lands cleanly:

1. `LAB-LANG-APP-PRESSURE-BENCH-BASELINE-P2` — capture a named baseline artifact after local Postgres P8;
2. `LAB-LANG-RUNTIME-HOTPATH-READINESS-P3` — inspect actual hot spots before optimizing;
3. `LAB-TODOAPP-API-PROTO-BENCH-P*` — add local Postgres contours once correctness is proven.
