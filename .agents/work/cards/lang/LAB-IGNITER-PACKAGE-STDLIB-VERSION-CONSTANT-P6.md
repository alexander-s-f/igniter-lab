# LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6 — expose stdlib version + add toolchain.stdlib

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5` pinned `toolchain.compiler` in `igniter.lock` and **deferred**
`toolchain.stdlib` because "stdlib has no version reachable from the compiler crate." This card removes that
blocker: expose a stdlib version constant the compiler authoritatively owns, then add `toolchain.stdlib`.

## Verify-first facts

- `igniter-stdlib` is **NOT** a Cargo dependency of `igniter_compiler` (confirmed: no `igniter_stdlib` in
  `Cargo.toml`). The compiler's stdlib knowledge is **baked-in signatures** (`typechecker/stdlib_calls.rs`),
  not a linked crate.
- The real stdlib crate version is `igniter-stdlib/Cargo.toml version = "0.1.0"`.
- So the honest "stdlib version the compiler can read" is the version of the **stdlib contract surface this
  compiler implements** — a fact the compiler crate authoritatively owns. Pin that, mirroring the stdlib
  crate's version, and **guard the mirror with a test** so it cannot silently diverge.

## Goal

1. Declare `pub const STDLIB_VERSION: &str = "0.1.0"` in `igniter_compiler` (the stdlib *surface* version this
   compiler implements; source-of-truth = `igniter-stdlib/Cargo.toml`, mirrored).
2. `Toolchain` gains `stdlib`; `current_toolchain()` stamps `STDLIB_VERSION`; `to_value`/`from_value` carry
   it; `verify_lock` reports `Toolchain { field: "stdlib", … }` drift when a **pinned** stdlib differs.
3. Backward-compat unchanged: an unpinned field (pre-P5/P5 lock without `stdlib`) → no drift for that field.
4. A **guard test**: if `../igniter-stdlib/Cargo.toml` is reachable, assert its `version` equals
   `STDLIB_VERSION` (catches silent divergence); skip gracefully when not present (isolation-safe).

## Closed scope

- Mirror the stdlib crate version via a compiler-owned constant; **no** build.rs reaching the sibling crate
  (fragile, deferred), **no** new Cargo dependency on `igniter-stdlib`.
- No grammar/lowerer fields (still deferred); digest semantics unchanged; no registry/solver/hooks.
- No `compile`-path / server / web / machine change; no canon claim.

## Verify first

- `Cargo.toml` (no stdlib dep), `../igniter-stdlib/Cargo.toml` (`version`).
- `src/typechecker/stdlib_calls.rs` (baked-in surface), `src/project.rs` `Toolchain`/`current_toolchain`/
  `verify_lock`, `src/lib.rs` (const home), `src/main.rs` `drift_to_json` (already renders Toolchain).

## Required tests

1. **stamps stdlib version** — `workspace_lock(root).toolchain.stdlib == STDLIB_VERSION`.
2. **stdlib drift detected** — verify against a lock with a different `toolchain.stdlib` → `Toolchain{field:
   "stdlib"}` drift.
3. **unpinned stdlib → no drift** — a lock with empty stdlib (P5-style) verifies clean on stdlib.
4. **guard: constant mirrors the stdlib crate** — `STDLIB_VERSION` == `igniter-stdlib/Cargo.toml version`
   when reachable; skip otherwise.
5. **CLI** — `igc lock` writes `toolchain.stdlib`; `igc verify` exits 1 on a tampered stdlib field.
6. P5 tests + full `igniter-compiler` suite stay green.

## Required acceptance

- [x] `STDLIB_VERSION` constant exposed; `current_toolchain` stamps `toolchain.stdlib`.
- [x] `verify_lock` reports stdlib drift when a pinned stdlib differs; unpinned → no drift.
- [x] Guard test ties the constant to `igniter-stdlib/Cargo.toml` (skips if unreachable).
- [x] `igc lock` writes `toolchain.stdlib`; `igc verify` exits 1 on tampered stdlib.
- [x] No build.rs / new Cargo dep on stdlib; mirror documented (verify-first).
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change.
- [x] `git diff --check` clean.

## Required proof doc

`lab-docs/lang/lab-igniter-package-stdlib-version-constant-p6-v0.md` — why a compiler-owned surface constant
(not a crate dep / build.rs), the guard test, toolchain.stdlib shape, drift + backward-compat, tests/counts,
deferred (grammar/lowerer, build-time derivation), next card.

---

## Closing Report (2026-06-21)

**Implementation (`lib.rs` const + `project.rs` + tests):** `pub const STDLIB_VERSION = "0.1.0"` (the stdlib
**surface** the compiler implements); `Toolchain.stdlib` + `current_toolchain` stamps it; `to_value`/
`from_value` carry it (lenient → empty = unpinned); `verify_lock` generalized to **per-field** toolchain
drift over `[compiler, stdlib]`. `main.rs drift_to_json` already rendered `Toolchain` (P5), so the CLI
surfaced stdlib drift with no change. Proof doc: `lab-docs/lang/lab-igniter-package-stdlib-version-constant-p6-v0.md`.

**Verify-first (honest):** `igniter-stdlib` is not a Cargo dep of the compiler (baked-in signatures in
`stdlib_calls.rs`), so the compiler authoritatively owns the surface version. Mirrored from
`igniter-stdlib/Cargo.toml` and **test-guarded** (`stdlib_version_mirrors_crate`, skips if the sibling is
unreachable) — no build.rs, no new Cargo dep.

**Live smoke:** `lock` writes `"toolchain":{"compiler":"0.1.0","stdlib":"0.1.0"}`; tamper stdlib →
`verify` reports `{kind:toolchain, field:stdlib, locked:0.0.0-bogus-stdlib, actual:0.1.0}`, exit 1.

**Proof — all green:** `package_workspace_tests` **20 passed** (16 + 4 P6 incl. guard), `package_lockfile_cli_tests`
**6 passed** (5 + 1 P6 CLI), full `igniter-compiler` suite green (0 failed), `git diff --check` clean.
Per-field backward-compat proven (pre-P5 + P5 locks unaffected). No compile/server/web/machine change.

**Deferred:** build-time derivation of `STDLIB_VERSION` (content hash of `stdlib/*.ig`); grammar/lowerer
fields; semver checks; `--frozen`/CI gating; registry/solver. **Next:** `LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7`
(strict direct-dep import scoping — reject phantom transitive imports), now that provenance is complete.
