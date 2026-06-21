# LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5 — toolchain version provenance in the lock

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-VERSION-PROVENANCE-P5
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4` persisted a deterministic `igniter.lock` (per-dependency sha256
digests) + `igc lock`/`verify`. The lock is **digest-only**: it pins dependency *content* but not the
*toolchain* that produced the build. This card adds **toolchain provenance** so that rebuilding with a
different compiler is **detectable drift**.

## Verify-first delta (live wins over the card title)

The card title says "compiler/stdlib/lowerer". Live code only exposes **one** static, build-time toolchain
constant the compiler crate can authoritatively stamp:
- **compiler version** — `env!("CARGO_PKG_VERSION")` of `igniter_compiler` (`Cargo.toml version = "0.1.0"`).
- `grammar_version` is **per-program** (`parser::determine_grammar_version`, dynamic) — a *program* property,
  not a *toolchain* identity, so it does not belong in a toolchain block.
- **stdlib has no version reachable from the compiler crate** — stdlib is resolved from an inventory, not a
  crate dependency, so there is no honest constant to pin without inventing one.

So P5 pins the **compiler version** (the one real anchor) and **defers** stdlib/lowerer fields until those
crates expose a version constant — documented, not faked.

## Goal

In `project.rs` (+ `main.rs` drift rendering) only:
1. `WorkspaceLock` gains a `toolchain: Toolchain { compiler: String }`; `workspace_lock` stamps
   `compiler = env!("CARGO_PKG_VERSION")`.
2. `to_value`/`from_value` carry the toolchain block. **Backward-compatible:** a lock with no `toolchain`
   parses as *unpinned* (empty compiler) → no toolchain drift (old P4 locks still verify on deps).
3. `verify_lock` adds `LockDrift::Toolchain { field, locked, actual }` when a **pinned** compiler differs
   from the current one. `main.rs` `drift_to_json` renders it; `igc verify` exits 1 on toolchain drift.

## Closed scope

- Only the **compiler version** is pinned (verify-first). No stdlib/grammar/lowerer fields (deferred, named).
- No registry, solver, hooks, transitive graph; digest semantics unchanged (P3/P4).
- No `compile`-path change; no server/web/machine change; no new crate dependency.
- No canon claim.

## Verify first

- `src/parser.rs determine_grammar_version` (per-program, dynamic).
- `Cargo.toml version` + `env!("CARGO_PKG_VERSION")` (compiler crate version).
- `src/project.rs` `WorkspaceLock`/`verify_lock`/`LockDrift`; `src/main.rs` `drift_to_json`/`run_verify`.

## Required tests

1. **stamps compiler version** — `workspace_lock(root).toolchain.compiler == env!("CARGO_PKG_VERSION")`.
2. **toolchain drift detected** — verify against a lock with a different `toolchain.compiler` → `Toolchain`
   drift.
3. **unpinned (old) lock → no toolchain drift** — a lock with empty toolchain compiler verifies clean on
   deps (backward-compat).
4. **lock JSON round-trips** with the toolchain block.
5. **CLI: `igc verify` exits 1 on toolchain drift** — tamper the lock's compiler field on disk → verify
   exit 1 with a toolchain drift.
6. P3/P4 tests + full `igniter-compiler` suite stay green.

## Required acceptance

- [x] `WorkspaceLock` carries `toolchain.compiler`; `workspace_lock` stamps `env!("CARGO_PKG_VERSION")`.
- [x] `verify_lock` reports `Toolchain` drift when a pinned compiler differs.
- [x] Backward-compatible: an unpinned (no-toolchain) lock yields no toolchain drift.
- [x] `igc verify` exits 1 on toolchain drift, with JSON detail; `igc lock` writes the toolchain block.
- [x] Only compiler pinned (verify-first delta vs stdlib/lowerer, documented).
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Required proof doc

`lab-docs/lang/lab-igniter-package-version-provenance-p5-v0.md` — the verify-first delta (why only compiler),
toolchain block shape, backward-compat, drift semantics, tests/counts, deferred (stdlib/grammar/lowerer
needing a version constant first), next card.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + `main.rs` drift rendering + tests):** `Toolchain { compiler }` +
`WorkspaceLock.toolchain`; `current_toolchain()` = `env!("CARGO_PKG_VERSION")`; `workspace_lock` stamps it;
`to_value`/`from_value` carry a `"toolchain"` block (pre-P5 locks parse as **unpinned**); `verify_lock` emits
`LockDrift::Toolchain { field, locked, actual }` only when a pinned compiler differs; `main.rs drift_to_json`
renders it; `igc verify` exits 1. Proof doc: `lab-docs/lang/lab-igniter-package-version-provenance-p5-v0.md`.

**Verify-first delta (honest):** only **compiler version** is pinned — the sole static build-time constant
the compiler crate authoritatively exposes. `grammar_version` is per-program (dynamic, not a toolchain
identity); stdlib has no version reachable from the compiler crate (inventory-resolved). stdlib/grammar/
lowerer fields **deferred**, documented, not faked.

**Live smoke:** `lock` writes `"toolchain":{"compiler":"0.1.0"}`; `verify` clean → `ok:true` exit 0; tamper
compiler→`0.0.0-bogus` → `verify` reports `{kind:toolchain,field:compiler,locked:0.0.0-bogus,actual:0.1.0}`,
`ok:false`, exit 1.

**Proof — all green:** `package_workspace_tests` **16 passed** (12 P2/P3 + 4 P5 API), `package_lockfile_cli_tests`
**5 passed** (4 P4 + 1 P5 CLI), full `igniter-compiler` suite green (0 failed), `git diff --check` clean.
Backward-compat proven at API + JSON-parse levels. No compile/server/web/machine change; no new crate.

**Deferred:** `toolchain.stdlib` (needs a stdlib version constant first → `…-STDLIB-VERSION-CONSTANT-P6`),
lowerer version, semver checks, `--frozen`/CI gating, registry/solver, blake3-unification. **Next:**
`LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6` (expose stdlib version → add `toolchain.stdlib`).
