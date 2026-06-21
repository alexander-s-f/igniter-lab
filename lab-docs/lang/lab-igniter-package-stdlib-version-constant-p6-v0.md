# lab-igniter-package-stdlib-version-constant-p6-v0 — stdlib version constant + toolchain.stdlib

**Card:** `LAB-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6` · **Delegation:** `OPUS-IGNITER-PACKAGE-STDLIB-VERSION-CONSTANT-P6`
**Status:** CLOSED (lab implementation-proof) — the P5-deferred `toolchain.stdlib` is now pinned. The compiler
exposes a `STDLIB_VERSION` constant (the stdlib **surface** it implements), `igniter.lock` records it, and a
stdlib change is **detectable drift**. **`lib.rs` const + `project.rs` + tests only — no build.rs, no new
Cargo dependency on `igniter-stdlib`, digest semantics unchanged, no compile/server/web/machine change.**

## Verify-first facts (what unblocked the P5 deferral)

P5 deferred `toolchain.stdlib` saying "stdlib has no version reachable from the compiler crate." Confirmed
the *why*, then resolved it honestly:

| Fact | Evidence |
|---|---|
| `igniter-stdlib` is **not** a Cargo dependency of `igniter_compiler` | no `igniter_stdlib` in `Cargo.toml` |
| the compiler's stdlib knowledge is **baked-in signatures** | `typechecker/stdlib_calls.rs` (`stdlib.*` arms) |
| the real stdlib crate version | `igniter-stdlib/Cargo.toml version = "0.1.0"` |

So the honest "stdlib version the compiler can read" is the version of the **stdlib contract surface this
compiler implements** — a fact the compiler crate authoritatively owns. P6 declares it as a constant,
**mirrors** the stdlib crate's version, and **guards the mirror with a test** so it cannot silently diverge.
No build.rs reaching the sibling crate (fragile in the non-workspace lab), no new Cargo dep.

## What changed (`lib.rs` + `project.rs`)

1. **`pub const STDLIB_VERSION: &str = "0.1.0"`** in `igniter_compiler` (documented: the baked-in stdlib
   surface version; bump when `stdlib_calls.rs` changes).
2. **`Toolchain` gains `stdlib`**; `current_toolchain()` stamps `crate::STDLIB_VERSION`; `to_value`/
   `from_value` carry `"stdlib"` (lenient parse → empty = unpinned).
3. **`verify_lock` generalized to per-field toolchain drift** — iterates `[(compiler, …), (stdlib, …)]`,
   reporting `LockDrift::Toolchain { field, locked, actual }` only for a **pinned** (non-empty) field that
   differs. `main.rs drift_to_json` already renders `Toolchain` (P5), so the CLI surfaces stdlib drift with
   no change.

## Backward-compatibility (proven, per-field)

Each toolchain field is independently optional. A **pre-P5** lock (no `toolchain`) → both empty → no
toolchain drift. A **P5** lock (`compiler` pinned, no `stdlib`) → stdlib empty → compiler still checked,
**no** stdlib drift. Tested at API level (`unpinned_stdlib_has_no_stdlib_drift`) and via the P5
backward-compat tests (still green).

## Live behavior (smoke, temp copy of `workspace`)

```text
$ igc lock --project-root <ws>/app   # igniter.lock toolchain block:
  "toolchain": { "compiler": "0.1.0", "stdlib": "0.1.0" }

# tamper toolchain.stdlib → "0.0.0-bogus-stdlib":
$ igc verify --project-root <ws>/app
{ "ok": false, "drift": [
    { "kind": "toolchain", "field": "stdlib",
      "locked": "0.0.0-bogus-stdlib", "actual": "0.1.0" } ] }                        # exit 1
```

## The guard test

`stdlib_version_mirrors_crate`: if `../igniter-stdlib/Cargo.toml` is reachable, assert its `[package]`
`version` equals `STDLIB_VERSION` — catching silent divergence between the compiler-owned mirror and the
real stdlib crate. If the sibling is not present (isolated CI), the check is **skipped**, so the test never
flakes. This turns "manually mirrored constant" into a **test-guarded** mirror.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 20 passed (16 + 4 NEW P6)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 6 passed  (5 + 1 NEW P6 CLI)
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P6 tests (5): `lock_stamps_stdlib_version`, `stdlib_drift_detected`, `unpinned_stdlib_has_no_stdlib_drift`,
`stdlib_version_mirrors_crate` (guard) + `cli_lock_writes_stdlib_and_verify_detects_stdlib_drift` (binary
e2e). The P5 `lock_json_roundtrips` `Toolchain` literal gained the `stdlib` field.

## Acceptance — mapping

- [x] `STDLIB_VERSION` constant exposed; `current_toolchain` stamps `toolchain.stdlib`.
- [x] `verify_lock` reports stdlib drift when a pinned stdlib differs; unpinned → no drift.
- [x] Guard test ties the constant to `igniter-stdlib/Cargo.toml` (skips if unreachable).
- [x] `igc lock` writes `toolchain.stdlib`; `igc verify` exits 1 on tampered stdlib.
- [x] No build.rs / new Cargo dep on stdlib; mirror documented (verify-first).
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/lib.rs` (`STDLIB_VERSION` constant).
- `lang/igniter-compiler/src/project.rs` (`Toolchain.stdlib`, `current_toolchain` stamp, `to_value`/
  `from_value` stdlib field, `verify_lock` per-field toolchain drift).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+4 P6 tests; updated `lock_json_roundtrips`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+1 CLI stdlib-drift test).

## Deferred (explicit)

- **Build-time derivation** of `STDLIB_VERSION` from the stdlib crate / a content hash of `stdlib/*.ig`
  (avoids the manual bump) — fragile without a workspace; deferred. The guard test is the interim safety net.
- **grammar / lowerer** toolchain fields (grammar is per-program; lowerer has no constant yet).
- Semver-range compatibility, `igc lock --frozen` / CI gating, registry/solver, blake3-unification.

## Next

`LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7` — strict direct-dependency import scoping (reject phantom transitive
imports per the P2 explicit-graph philosophy), now that provenance (content + compiler + stdlib) is complete.
Registry/solver remain far later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 20 green, `package_lockfile_cli_tests`
6 green, full `igniter-compiler` suite green, `git diff --check` clean. `igniter.lock` now pins both the
compiler and the stdlib-surface version, with a test-guarded mirror to the stdlib crate — the P5-deferred
field, unblocked honestly.*
