# lab-igniter-package-lockfile-cli-p4-v0 — persist igniter.lock + lock/verify CLI

**Card:** `LAB-IGNITER-PACKAGE-LOCKFILE-CLI-P4` · **Delegation:** `OPUS-IGNITER-PACKAGE-LOCKFILE-CLI-P4`
**Status:** CLOSED (lab implementation-proof) — the P3 lock API is now a **developer workflow**: `igc lock`
writes a deterministic `igniter.lock`, `igc verify` checks drift. **`main.rs` + tests only — reuses the P3
`workspace_lock`/`verify_lock` API, no new lock semantics, no registry/solver/hooks, no `compile`-path
change, no server/web/machine change, no new crate dependency.**

## What changed (`main.rs` only)

Two subcommands dispatched before the unknown-command rejection, over the P3 API:
- **`igc lock [--project-root ROOT]`** → `project::workspace_lock(ROOT)` → write `ROOT/igniter.lock`
  (pretty JSON + trailing newline) → print `{ kind, lockfile, dependencies, written }`. **Idempotent:**
  re-running yields a **byte-identical** file (lock is name-sorted; `serde_json` has no `preserve_order` →
  stable key order).
- **`igc verify [--project-root ROOT]`** → read+parse `igniter.lock` → `project::verify_lock(ROOT, &lock)`
  → print `{ kind, lockfile, ok, drift[] }`. **Exit 0** when reproducible; **exit 1** on drift / missing /
  malformed lock.

`--project-root` defaults to `.`. Output is machine-readable JSON. The lockfile lives at the workspace root
and is never a `.ig` file, so it does not affect resolution or dependency digests.

## Live behavior (smoke, on a temp copy of the `workspace` fixture)

```text
$ igc lock --project-root <ws>/app
{ "kind": "igniter_lock_result", "lockfile": "<ws>/app/igniter.lock", "dependencies": 1, "written": true }

$ cat <ws>/app/igniter.lock
{
  "dependencies": [
    { "digest": "sha256:d907bb2f…eac69ae", "name": "lib", "path": "../lib" }
  ],
  "version": 1
}

$ igc verify --project-root <ws>/app           # clean
{ "kind": "igniter_verify_result", "lockfile": "…", "ok": true, "drift": [] }        # exit 0

# after editing ../lib/src/util.ig:
$ igc verify --project-root <ws>/app
{ "kind": "igniter_verify_result", "ok": false, "drift": [
    { "kind": "changed", "name": "lib",
      "locked": "sha256:d907bb2f…", "actual": "sha256:2a8aba3a…" } ] }                # exit 1
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests   → 4 passed; 0 failed
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests      → 12 passed (P2+P3 intact)
$ cd lang/igniter-compiler && cargo test                                     → full suite green (0 failed)
$ git diff --check                                                           → clean
```

New CLI e2e tests (4) — each **copies the `workspace` fixture into a tempdir** and runs the binary there, so
the version-controlled fixture tree is **never written to**:
- `cli_lock_then_verify_clean` — `lock` writes `igniter.lock` (exit 0, `dependencies:1`, `written:true`);
  `verify` → exit 0, `ok:true`, empty drift.
- `cli_lock_is_idempotent` — `lock` run twice → **byte-identical** `igniter.lock`.
- `cli_verify_detects_drift` — after `lock`, mutate a dependency source file → `verify` exit 1 with a
  `changed` drift for `lib`.
- `cli_verify_missing_lockfile_fails` — `verify` with no lockfile → exit 1.

## Acceptance — mapping

- [x] `igc lock` writes a deterministic `igniter.lock`; idempotent (byte-identical re-run).
- [x] `igc verify` exits 0 on clean, 1 on drift / missing / malformed, with JSON drift detail.
- [x] `--project-root` defaults to `.`; output machine-readable JSON.
- [x] Reuses the P3 API; no new lock semantics; no registry/solver/hooks.
- [x] `compile` path unchanged; full `igniter-compiler` suite green; no server/web/machine change; no new crate.
- [x] `git diff --check` clean (tests use a tempdir; no fixture pollution).

## Files changed

- `lang/igniter-compiler/src/main.rs` (`lock`/`verify` dispatch + `run_lock`/`run_verify`/`project_root_arg`/
  `drift_to_json`; `use igniter_compiler::project`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (new, 4 e2e tests + tempdir copy helper).

## Deferred (explicit)

`igniter.lock` schema fields for compiler/stdlib/lowerer versions (digest-only, P3 carry-over); a
`--write`/`--check` distinction or `igc lock --frozen`; CI integration; registry/solver; transitive package
graph; blake3-unification with the machine side.

## Next

`LAB-IGNITER-PACKAGE-VERSION-PROVENANCE-P5` — add compiler/stdlib/lowerer-version fields to the lock (so a
toolchain change is detectable drift), then strict direct-dep import scoping; registry/solver remain far
later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_lockfile_cli_tests` 4 green, `package_workspace_tests`
12 intact, full `igniter-compiler` suite green, `git diff --check` clean. `igc lock`/`igc verify` make the P3
lock a real developer workflow — deterministic `igniter.lock` + drift detection, no registry/solver/hooks.*
