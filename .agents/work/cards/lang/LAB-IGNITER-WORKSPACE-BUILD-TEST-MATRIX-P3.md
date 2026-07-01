# LAB-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3 — `igniter workspace build/test` bounded core checks

Status: DONE
Lane: distribution / command center / workspace Dev lane
Type: implementation
Delegation code: OPUS-IGNITER-WORKSPACE-BUILD-TEST-MATRIX-P3
Date: 2026-07-01
Skill: idd-agent-protocol

## Context

P1 decided that `igniter` should become the command center. P2 adds read-only workspace status/doctor.

This card adds the next Dev-lane slice: a bounded build/test matrix for core contributors.

The goal is **not** full CI, not release validation, and not a root Cargo workspace. The goal is a memorable
front door for the checks we already know matter:

```text
igniter workspace build
igniter workspace test
```

The command should encode the current core graph without making developers remember paths.

## Dependency

Prefer running after `LAB-IGNITER-WORKSPACE-STATUS-DOCTOR-P2`, because this card should reuse the workspace
layout checks and diagnostic language. If P2 is not landed yet, stop and either implement P2 first or narrow
this card to a readiness packet.

## Verify first

Read:

- `bin/igniter` after P2
- `lab-docs/lang/lab-igniter-command-center-autonomy-readiness-p1-v0.md`
- the latest mirror-check proof from P2/P3 flatten wave
- current `Cargo.toml` files for:
  - `igniter-stdlib`
  - `igniter-compiler`
  - `igniter-vm`
  - `igniter-tbackend`
  - `igniter-machine`

Confirm the current bounded matrix live. Do not assume stale test counts.

## Goal

Implement:

```text
igniter workspace build [--json]
igniter workspace test [--json] [--quick]
```

Recommended v0 matrix:

### Build

Run `cargo build` or `cargo test --no-run` for each core crate package-locally:

- `igniter-stdlib`
- `igniter-compiler`
- `igniter-vm`
- `igniter-tbackend`
- `igniter-machine`

Use the crate-local `Cargo.toml`; do not create a root workspace.

### Test

Run a bounded matrix with sensible defaults:

- stdlib tests;
- compiler tests;
- vm tests;
- tbackend tests if not too heavy;
- machine pure-core lane:
  `cargo test --manifest-path igniter-machine/Cargo.toml --no-default-features --no-fail-fast`

If the full matrix is too slow/noisy, define:

- `workspace test --quick`: metadata + key smoke targets;
- `workspace test`: the bounded core matrix.

But do not silently skip machine pure-core checks: that is the proof that mirror/core autonomy works.

## Output contract

Human output should show:

```text
workspace build:
  igniter-stdlib     ok
  igniter-compiler   ok
  ...
```

JSON should use a simple result object or the existing diagnostic record shape. If this card finds the current
doctor schema is insufficient for command duration/exit code, document that as pressure for P4 and keep v0
minimal.

At minimum each item needs:

- `scope`: `workspace`
- `check`: e.g. `build igniter-vm`
- `severity`: `ok` / `fail`
- `detail`: command summary
- `suggest`: next action

## Known caveat

If a test is known-flaky, do not hide it. Report it explicitly in the closing report with exact test name,
rerun evidence, and recommended follow-up. Do not mark a failing suite green by default.

## Design constraints

- No root Cargo workspace.
- No `Cargo.toml` rewrites.
- No mirror push/fetch/pull.
- No network except ordinary Cargo dependency resolution already required by local builds.
- No registry/semver policy.
- Do not broaden into release packaging.
- Do not mutate source files.

## Tests / verification

At minimum run:

```text
bin/igniter workspace build --json
bin/igniter workspace test --quick --json
bin/igniter workspace test --quick
git diff --check
```

If runtime is acceptable, run full:

```text
bin/igniter workspace test
```

Also verify a fresh mirror/sibling checkout if this card changes matrix semantics.

## Acceptance

- [x] `igniter workspace build` exists and runs core crate build checks.
- [x] `igniter workspace test` exists and runs a bounded core matrix.
- [x] `--quick` exists if full matrix is too slow for default development loops.
- [x] `--json` exists and is machine-readable.
- [x] Missing `igniter-lang` sibling fails clearly before compiler/machine checks.
- [x] Machine pure-core lane is included or explicitly justified if gated.
- [x] Known flake handling is explicit, not swept under the rug.
- [x] No root workspace created.
- [x] No `Cargo.toml` rewrites.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-07-01. Changes staged (not committed). No mirrors pushed, no root workspace, no `Cargo.toml`
touched.

**Implemented** in `bin/igniter`: `workspace build` + `workspace test [--quick]` via `ws_matrix` + `ws_step`
+ `_ws_matrix_render`, wired into `cmd_workspace` and both usages. Package-LOCAL cargo per crate (each crate's
own `Cargo.toml`; no root workspace). Reuses the P2 diagnostic-record schema — `--json` emits
`[{scope:"workspace",check,severity,detail,suggest}]` (ok/warn/fail/info). `ws_step` captures cargo output
and, on failure only, echoes the tail to STDERR so `--json` on STDOUT stays a clean array. Exit 1 on any
matrix failure, 2 on usage.

**Matrix (verified live, all package-local):**
- `build` → `cargo build` each of stdlib/vm/tbackend/compiler + `igniter-machine` with `--no-default-features`
  (the pure-core build). → **6/6 ok, exit 0.**
- `test` (full) → stdlib + tbackend tests, then a **`cargo build --release --bin tbackend`** prep (vm's
  `reactive_tests` spawns that daemon — the matrix encodes the real graph so vm is honest-green), then vm +
  compiler tests, then the **machine PURE-CORE lane** `cargo test --no-default-features --no-fail-fast` (the
  mirror/core autonomy proof). → **all steps ok, exit 0.**
- `test --quick` → `cargo metadata --no-deps` per crate (fast resolve/manifest) + a pure-core **compile** of
  machine. Does NOT skip the pure-core lane — narrows it to a compile check. → **7 records, 0 fail, exit 0.**

**Sibling preflight (acceptance):** the canon `igniter-lang` inventory is checked first; when absent the
compiler + machine steps are emitted as `fail` ("skipped: canon sibling absent") **without running cargo**,
and the run exits 1 — verified by renaming the inventory away (`[fail] igniter-lang sibling` + `[fail]
compile igniter-machine (pure-core) skipped` → exit 1; restored). Leaf crates (stdlib/vm/tbackend) don't need
canon and still run.

**Known-flake handling (not swept under the rug):** the machine default-feature suite has one known flaky
test, `wire_atomic_gate_tests::plain_run_write_effect_doubles_under_forced_interleave` (forced-interleave
concurrency; 3/3 green in isolation, only flaps under full parallel scheduling — documented in P3
devdep-reconcile). The workspace matrix runs the machine **pure-core** lane (`--no-default-features`), where
it did **not** manifest across the full runs here; the matrix uses `--no-fail-fast` so a real failure would
surface every case rather than stop early. No suite is marked green by default — exit code is the cargo truth.

**Verification (this box):** `workspace build --json` / `test --quick --json` / `test --quick` → exit 0;
full `workspace test` → all ok, exit 0; arg rejections (`build --quick`, `test <positional>`, `build extra`)
→ exit 2; missing-sibling → exit 1. New wrapper tests in `server/igniter-web/tests/igniter_workspace_tests.rs`
(now **9/9**, P2+P3): help documents build/test + `--quick` + pure-core, `build` rejects `--quick`, `test`
rejects a positional. The heavy matrix itself is verified by direct invocation (not nested inside `cargo
test`). Regression: `igniter_doctor_tests` → 6/6. `git diff --check` clean; no trailing whitespace.

**Pressure noted for P4:** the doctor record schema carries no per-command duration or overall exit-code
field — fine for v0 (exit code is the process's), but a unified JSON/MCP contract (P4) should add an envelope
with overall status + timing so CI/agents get one machine-readable summary instead of scanning records.
`workspace sync` was intentionally NOT implemented (out of this card's read-plus-build scope).
