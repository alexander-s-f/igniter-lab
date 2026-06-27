# lab-igniter-compiler-lock-on-build-p2-v0

Status: DONE
Date: 2026-06-27
Lane: igniter-lab / lang / igniter-compiler / supply-chain integrity
Authority: lab implementation proof; `igniter-lang` canon unchanged.

## Decision

Chosen CLI shape:

```text
igc compile --project-root ROOT --entry MODULE --out OUT.igapp --locked
```

`--frozen` is accepted as an alias for CI scripts that already use
`igc lock --frozen`. The compile flag is explicit and project-mode only:

- single-file `.ig` compile: unchanged;
- project compile without `--locked`: unchanged, including no-lock projects;
- project compile with `--locked` / `--frozen`: fail before project resolve,
  emit, or assemble unless the committed lock is present/current and strict
  workspace integrity passes.

## Enforcement

`lang/igniter-compiler/src/main.rs` now runs `enforce_project_lock(root)` in
`run_project_mode` before `resolve_entry_with_overlays`.

The gate reuses the same trust code as the existing CI path:

- `WorkspaceLock::from_value` reads `igniter.lock`;
- `project::verify_lock(root, &lock)` checks dependency content and
  compiler/stdlib toolchain drift;
- `project::check_workspace_integrity(root)` checks the same entry-free
  integrity rules used by `verify --strict` (`OOF-IMP4`, `OOF-IMP6`,
  `OOF-IMP7`, `OOF-IMP8`, `OOF-IMP9` as applicable).

Diagnostics:

- missing lock: `OOF-LOCK-MISSING`;
- malformed lock: `OOF-LOCK-MALFORMED`;
- stale/drifted lock: `OOF-LOCK-DRIFT` with structured `details.drift`;
- workspace integrity faults: existing structured project diagnostic, for
  example `OOF-IMP6`;
- IO/assembly trouble during the lock gate: `OOF-LOCK-IO` or
  `OOF-LOCK-INTEGRITY`.

Lock-gate refusals print a `compiler_result` with `status:"oof"` and
`source_path:"project:lock"`; `igapp_path` and `compilation_report_path` are
`null`. This keeps stale/missing lock failures from writing fresh-looking
compile artifacts.

## Tests

Commands run:

```text
cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests
cd lang/igniter-compiler && cargo test --test package_workspace_tests
cd lang/igniter-compiler && cargo test --test project_mode_tests
```

Results:

- `package_lockfile_cli_tests`: 55 passed, including 5 new P2 compile-lock
  cases;
- `package_workspace_tests`: 50 passed;
- `project_mode_tests`: 9 passed.

New P2 tests:

- `cli_compile_locked_passes_when_lock_is_current`;
- `cli_compile_locked_fails_when_lock_missing_without_writing_output`;
- `cli_compile_locked_fails_when_lock_is_stale_without_writing_output`;
- `cli_compile_locked_reuses_strict_integrity_gate`;
- `cli_compile_without_locked_allows_missing_lock`.

## Remaining Gaps

- Compile locking is explicit, not default-on.
- The dependency resolver still needs canonicalize/containment hardening for
  symlink / `..` escape risk.
- Registry, semver solver, signing, remote execution, and package execution
  from admission remain outside this slice.
