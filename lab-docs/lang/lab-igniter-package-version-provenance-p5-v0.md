# lab-igniter-package-version-provenance-p5-v0 — toolchain version provenance in the lock

**Card:** `LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5` · **Delegation:** `OPUS-IGNITER-PACKAGE-VERSION-PROVENANCE-P5`
**Status:** CLOSED (lab implementation-proof) — `igniter.lock` now pins the **producing compiler version**, so
rebuilding with a different compiler is **detectable drift** (`LockDrift::Toolchain`). **`project.rs` +
`main.rs` drift rendering + tests only — digest semantics unchanged, no registry/solver/hooks, no
`compile`-path / server / web / machine change, no new crate dependency.**

## Verify-first delta (live wins over the card title)

The card title said "compiler/stdlib/lowerer". Live code exposes only **one** static, build-time toolchain
constant the compiler crate can authoritatively stamp:

| Candidate | Reality in live code | Verdict |
|---|---|---|
| **compiler version** | `env!("CARGO_PKG_VERSION")` of `igniter_compiler` (`Cargo.toml version = "0.1.0"`) | **pinned** — the one real, static, build-time anchor |
| grammar version | `parser::determine_grammar_version(...)` is computed **per program** (dynamic) | rejected — a *program* property, not a *toolchain* identity |
| stdlib version | stdlib is resolved from an **inventory**, not a crate dependency — **no version reachable** from the compiler crate | deferred — needs the crate to expose a constant first |

So P5 pins **`toolchain.compiler`** honestly and **defers** stdlib/grammar/lowerer rather than inventing
values. This corrects the card's optimistic title against the code.

## What changed (`project.rs` + `main.rs`)

1. **`Toolchain { compiler: String }`** + `WorkspaceLock` gains `toolchain`. `current_toolchain()` returns
   `{ compiler: env!("CARGO_PKG_VERSION") }`; `workspace_lock` stamps it.
2. **`to_value`/`from_value`** carry a `"toolchain": { "compiler": "…" }` block. **Backward-compatible:** a
   pre-P5 lock with no `toolchain` parses as **unpinned** (empty compiler).
3. **`verify_lock`** adds `LockDrift::Toolchain { field, locked, actual }` when a **pinned** compiler differs
   from the current one — *only* when the lock actually pinned a compiler (unpinned = no toolchain claim →
   never drifts). `main.rs drift_to_json` renders it; `igc verify` exits 1.

## Live behavior (smoke, temp copy of `workspace`)

```text
$ igc lock --project-root <ws>/app   # igniter.lock now carries:
  "toolchain": { "compiler": "0.1.0" }

$ igc verify --project-root <ws>/app                       # clean
{ "ok": true, "drift": [] }                                                          # exit 0

# tamper toolchain.compiler → "0.0.0-bogus":
$ igc verify --project-root <ws>/app
{ "ok": false, "drift": [
    { "kind": "toolchain", "field": "compiler",
      "locked": "0.0.0-bogus", "actual": "0.1.0" } ] }                               # exit 1
```

## Backward-compatibility (proven)

An unpinned lock (no `toolchain` block, or empty compiler) produces **no** toolchain drift, so any pre-P5
`igniter.lock` still verifies on dependency digests exactly as before. Tested both at the API
(`unpinned_lock_has_no_toolchain_drift`) and JSON-parse (`pre_p5_lock_json_parses_unpinned`) levels.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 16 passed (12 P2/P3 + 4 NEW P5)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 5 passed  (4 P4 + 1 NEW P5 CLI)
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P5 tests (5): `lock_stamps_compiler_version`, `toolchain_drift_detected`,
`unpinned_lock_has_no_toolchain_drift`, `pre_p5_lock_json_parses_unpinned` (API) +
`cli_verify_detects_toolchain_drift` (binary e2e — tamper the on-disk lock's compiler field → exit 1 with a
`toolchain` drift). The P3 `lock_json_roundtrips` literal was updated for the new `toolchain` field.

## Acceptance — mapping

- [x] `WorkspaceLock` carries `toolchain.compiler`; `workspace_lock` stamps `env!("CARGO_PKG_VERSION")`.
- [x] `verify_lock` reports `Toolchain` drift when a pinned compiler differs.
- [x] Backward-compatible: an unpinned (no-toolchain) lock yields no toolchain drift.
- [x] `igc verify` exits 1 on toolchain drift, with JSON detail; `igc lock` writes the toolchain block.
- [x] Only compiler pinned (verify-first delta vs stdlib/lowerer, documented).
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`Toolchain`, `current_toolchain`, `WorkspaceLock.toolchain`,
  `to_value`/`from_value` toolchain block, `verify_lock` toolchain drift, `LockDrift::Toolchain`).
- `lang/igniter-compiler/src/main.rs` (`drift_to_json` toolchain arm).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+4 P5 tests; updated `lock_json_roundtrips`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+1 CLI toolchain-drift test).

## Deferred (explicit)

- **stdlib version** — needs `igniter-stdlib` to expose a version constant reachable from the compiler
  (today it is inventory-resolved, not a crate dep). Same for a dedicated **lowerer** version.
- **grammar_version** in the lock — it is per-program; if ever pinned it belongs to a *program* record, not
  the *toolchain* block.
- Semver-range compatibility checks, `igc lock --frozen` / CI gating, registry/solver, blake3-unification.

## Next

`LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6` — expose a stdlib version constant the compiler can read,
then add `toolchain.stdlib` to the lock (the deferred field, unblocked). After that: strict direct-dep
import scoping; registry/solver remain far later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 16 green, `package_lockfile_cli_tests`
5 green, full `igniter-compiler` suite green, `git diff --check` clean. `igniter.lock` now pins the compiler
version (`env!("CARGO_PKG_VERSION")`) with backward-compatible unpinned-lock handling — toolchain drift is
detectable, honestly scoped to the one real build-time constant.*
