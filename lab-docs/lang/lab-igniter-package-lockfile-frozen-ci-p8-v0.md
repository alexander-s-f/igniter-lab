# lab-igniter-package-lockfile-frozen-ci-p8-v0 — frozen lock + strict verify (CI trust gate)

**Card:** `LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8` · **Delegation:** `OPUS-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8`
**Status:** CLOSED (lab implementation-proof) — CI can now **trust a workspace** with two mutation-aware
gates: **`igc lock --frozen`** asserts the committed lock is current without writing, and **`igc verify
--strict`** asserts drift-clean **and** assembly-clean (no duplicate modules / phantom imports). **`project.rs`
refactor (shared integrity) + `main.rs` flags + tests only — no new lock/scope semantics, no compile/server/
web/machine change, no new crate.**

## The CI story

Provenance (P3–P6) and scoping (P7) gave the *guarantees*; P8 makes them **enforceable in CI without
mutating the repo**:

| Command | Question | Mutates? | Fails (exit 1) when |
|---|---|---|---|
| `igc lock --frozen` | "is the committed lock current?" | **no** | lock missing or would differ (`reason: missing` / `out-of-date`) |
| `igc verify --strict` | "does the locked workspace also assemble cleanly?" | no | drift **or** OOF-IMP4 / OOF-IMP6 integrity fault |

CI runs `igc lock --frozen && igc verify --strict` → the workspace is reproducible (content + toolchain),
its lock is committed and current, and it has import integrity. Plain `lock` / `verify` keep their P4
behavior (developer-facing, mutating / drift-only).

## What changed

**`project.rs` (refactor, behavior-preserving):** the OOF-IMP4 (duplicate) + OOF-IMP6 (phantom) checks were
extracted from `resolve_entry_with_overlays` into a shared `index_integrity(&index, &config) ->
Option<ProjectDiagnostic>`, plus a new entry-free **`pub fn check_workspace_integrity(root)`**. The compile
path and the CI gate now enforce **exactly the same rules** (no logic fork). All P2–P7 diagnostics are
byte-identical (23 workspace tests unchanged).

**`main.rs`:**
- `run_lock` gains `--frozen`: compute the lock, compare to the on-disk `igniter.lock` **byte-for-byte**
  (same pretty-JSON + trailing newline `lock` would write), print `{ ok, reason, written:false }`, **never
  write**, exit 1 unless `up-to-date`.
- `run_verify` gains `--strict`: after drift, run `check_workspace_integrity`; add an `integrity` block to
  the JSON; `ok = drift.is_empty() && integrity.ok`.

## Live behavior (smoke)

```text
# A. frozen, current lock:
$ igc lock --project-root <ws>/app --frozen
{ "ok": true,  "reason": "up-to-date",  "written": false }                            # exit 0

# B. frozen after a dependency edit (lock untouched):
$ igc lock --project-root <ws>/app --frozen
{ "ok": false, "reason": "out-of-date", "written": false }                            # exit 1

# C. strict verify on a phantom workspace — drift-clean but integrity-dirty:
$ igc verify --project-root <ws>/app --strict
{ "ok": false, "drift": [],
  "integrity": { "ok": false, "diagnostic": {
      "rule": "OOF-IMP6",
      "message": "out-of-scope import: module 'Lib1.A' (package lib1) imports 'Lib2.B' (package lib2), …" } } }
                                                                                       # exit 1
```

Smoke C is the crux: **plain `verify` passes** (no lock drift — the phantom does not change dependency
digests), while **`verify --strict` fails** on the OOF-IMP6 integrity fault. The strict flag is what ties
P7's scoping into the CI trust gate.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 11 passed (6 + 5 NEW P8)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → 25 passed (23 + 2 NEW P8 integrity API)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests           → 9 passed (integrity refactor preserved)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New P8 tests (7): API — `check_workspace_integrity_flags_phantom`, `check_workspace_integrity_ok_on_clean`.
CLI — `cli_lock_frozen_passes_when_current` (no rewrite), `cli_lock_frozen_fails_when_missing` (no file
created), `cli_lock_frozen_fails_when_stale` (lock untouched), `cli_verify_strict_catches_phantom` (plain
verify passes, strict fails OOF-IMP6), `cli_verify_strict_passes_clean`.

## Acceptance — mapping

- [x] `igc lock --frozen` never writes; exit 0 iff the committed lock is byte-current; else `missing`/`out-of-date`.
- [x] `igc verify --strict` = drift + workspace integrity (OOF-IMP4/OOF-IMP6); JSON `integrity` block.
- [x] Plain `lock`/`verify` keep P4 behavior (mutating / drift-only).
- [x] Integrity rules shared with the compile path (`index_integrity`); P2–P7 diagnostics byte-identical.
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean (CLI tests use tempdirs; no fixture pollution).

## Files changed

- `lang/igniter-compiler/src/project.rs` (`index_integrity` extraction + `check_workspace_integrity`).
- `lang/igniter-compiler/src/main.rs` (`run_lock --frozen`, `run_verify --strict`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+2 integrity API tests).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+5 CLI tests; generalized temp-fixture helper).

## Deferred (explicit)

- A single combined `igc ci` command (frozen + strict in one) — composition of the two is enough for v0.
- Strict-mode coverage of an entry/whole-project **compile** (today integrity = assembly, not full type-check);
  CI can still call `igc compile` separately.
- Semver ranges, registry/solver, transitive package graph, module-level visibility — all later.

## Next

With trust enforced, the next structural slices are **module-level visibility/export** (restrict which of a
dependency's modules are importable — today all are) or a **transitive package graph**, per the user's
sequencing. Registry/semver remain far later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_lockfile_cli_tests` 11 green, `package_workspace_tests`
25 green, `project_mode` 9 intact, full `igniter-compiler` suite green, `git diff --check` clean. `igc lock
--frozen` + `igc verify --strict` make the workspace CI-trustable — committed-lock currency + drift + import
integrity, mutation-aware, over the now-complete content/toolchain/scope guarantees.*
