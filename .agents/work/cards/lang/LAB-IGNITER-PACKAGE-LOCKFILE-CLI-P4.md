# LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4 — persist igniter.lock + lock/verify CLI

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-LOCKFILE-CLI-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3` added the `project::{workspace_lock, verify_lock}` API (per-
workspace sha256 dependency digests + drift detection) as a library function. This card surfaces it as the
**developer workflow**: persist a deterministic `igniter.lock` and add `lock` / `verify` CLI subcommands.

## Goal

In `lang/igniter-compiler/src/main.rs` only, add two subcommands over the P3 API:
- `igc lock [--project-root ROOT]` → compute the lock, write a **deterministic** `ROOT/igniter.lock`
  (idempotent: re-running yields a byte-identical file), print a JSON result.
- `igc verify [--project-root ROOT]` → read `igniter.lock`, recompute, report **drift** (changed/new/
  missing). Exit 0 when reproducible; exit 1 on drift / missing / malformed lock.

`--project-root` defaults to `.`. Output is machine-readable JSON.

## Closed scope

- No new lock semantics (reuse P3 `workspace_lock`/`verify_lock`/`WorkspaceLock`).
- No registry, network, version solver, install hooks, transitive package graph.
- No `compile`-path change; no server/web/machine change; no new crate dependency.
- No compiler/stdlib/lowerer version fields (digest-only, P3 carry-over).
- No canon claim.

## Verify first

- `lang/igniter-compiler/src/main.rs` — `fn main` command dispatch (`compile` only today), `run_project_mode`
  flag-parsing style, existing JSON output convention.
- `lang/igniter-compiler/src/project.rs` — `workspace_lock`, `verify_lock`, `WorkspaceLock::{to_value,
  from_value}`, `LockDrift`.

Confirm: `igc` rejects unknown commands; `serde_json` (no preserve_order) → deterministic `to_string_pretty`;
the lock JSON is name-sorted (deterministic).

## Required implementation

`main.rs`:
1. Dispatch `lock` / `verify` subcommands before the unknown-command rejection.
2. `run_lock(args)` — `workspace_lock(root)` → write `ROOT/igniter.lock` (pretty JSON + trailing newline) →
   print `{ kind, lockfile, dependencies, written }`.
3. `run_verify(args)` — read+parse `igniter.lock` → `verify_lock(root, &lock)` → print `{ kind, lockfile, ok,
   drift[] }`; exit 1 if not ok / missing / malformed.

## Required tests (binary e2e; never write into the fixture tree)

Copy the `workspace` fixture to a tempdir, run the binary there:
1. **lock then verify clean** — `lock` writes `igniter.lock` (exit 0, deps=1); `verify` → exit 0, `ok:true`.
2. **lock idempotent** — running `lock` twice yields a byte-identical `igniter.lock`.
3. **verify detects drift** — after lock, mutate a dependency source file → `verify` exit 1 with a `changed`
   drift for the dependency.
4. **verify missing lockfile** — `verify` with no `igniter.lock` → exit 1.

## Required acceptance

- [x] `igc lock` writes a deterministic `igniter.lock`; idempotent.
- [x] `igc verify` exits 0 on clean, 1 on drift / missing / malformed, with JSON drift detail.
- [x] `--project-root` defaults to `.`; output is machine-readable JSON.
- [x] Reuses P3 API; no new lock semantics; no registry/solver/hooks.
- [x] `compile` path unchanged; full `igniter-compiler` suite green; no server/web/machine change; no new crate.
- [x] `git diff --check` clean (tests use a tempdir; no fixture pollution).

## Required proof doc

`lab-docs/lang/lab-igniter-package-lockfile-cli-p4-v0.md` — CLI shape, deterministic-file proof, drift
semantics, exact tests/counts, deferred (version fields, registry), next card.

---

## Closing Report (2026-06-21)

**Implementation (`main.rs` + tests only):** `lock` / `verify` subcommands dispatched before the unknown-
command rejection, over the P3 `project::{workspace_lock, verify_lock}` API. `run_lock` writes a
deterministic `ROOT/igniter.lock` (pretty JSON + trailing newline, name-sorted → idempotent byte-identical
re-run) and prints `{kind, lockfile, dependencies, written}`. `run_verify` reads+parses the lock, recomputes,
prints `{kind, lockfile, ok, drift[]}`, exits 1 on drift / missing / malformed. `--project-root` defaults to
`.`. Proof doc: `lab-docs/lang/lab-igniter-package-lockfile-cli-p4-v0.md`.

**Live smoke (temp copy of `workspace`):** `lock` → `igniter.lock` with `lib`'s `sha256:d907bb2f…` digest +
`written:true`; `verify` clean → `ok:true` exit 0; after editing `../lib/src/util.ig` → `verify` reports a
`changed` drift (`locked` vs `actual` digest), `ok:false`, exit 1.

**Proof — all green:** `package_lockfile_cli_tests` **4 passed** (lock+verify-clean, lock-idempotent,
verify-detects-drift, verify-missing-lockfile); `package_workspace_tests` 12 (P2+P3) intact; full
`igniter-compiler` suite green (0 failed); `git diff --check` clean. Tests **copy the fixture into a
tempdir**, so the version-controlled tree is never written to. `compile` path unchanged; no server/web/
machine change; no new crate.

**Deferred:** compiler/stdlib/lowerer-version lock fields; `igc lock --frozen` / CI gating; registry/solver;
transitive package graph; blake3-unification. **Next:** `LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5` (toolchain
version fields in the lock so a compiler/stdlib change is detectable drift), then strict direct-dep import scoping.
