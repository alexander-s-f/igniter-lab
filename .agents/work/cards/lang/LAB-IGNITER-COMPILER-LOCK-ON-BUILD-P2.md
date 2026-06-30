# LAB-IGNITER-COMPILER-LOCK-ON-BUILD-P2

Status: DONE
Route: standard / main-audit / compiler / supply-chain integrity
Skill: idd-agent-protocol

## Goal

Close the audit gap "lockfile is computed/verified, but not enforced on build"
for project/package compilation.

The package system already has `igc lock --frozen` and `igc verify --strict`.
This card must decide and implement the smallest compile-path enforcement that
does not break single-file `.ig` workflows.

## Current Authority

Live package/compiler code wins.

Read first:

- `lab-docs/igniter-compiler-core-foundation-audit-p1.md` (B-I1)
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md` (T1.5)
- `.agents/work/cards/lang/LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8.md`
- `lab-docs/lang/lab-igniter-package-lockfile-frozen-ci-p8-v0.md`
- `lang/igniter-compiler/src/main.rs`
- `lang/igniter-compiler/src/project.rs`
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`
- `lang/igniter-compiler/tests/package_workspace_tests.rs`

Known live facts:

- `verify --strict` is the CI trust gate.
- `resolve_entry_with_overlays` already shares workspace integrity checks with
  `verify --strict`.
- The open question is build-time content drift: when compiling a project root
  with an `igniter.lock`, should compile require lock parity, warn, or expose a
  `--locked/--frozen` mode?

## Decision Boundary

Do not make single-file local experiments painful. The likely v0:

```text
single .ig compile                         -> unchanged
project compile with no lock               -> unchanged or warning only
project compile with lock + --locked flag  -> fail on drift/missing/stale
project compile in explicit CI mode        -> equivalent to lock --frozen + compile
```

But verify live CLI shape before choosing. If a stricter default is safer and
does not break tests, justify it.

## Scope

Allowed:

- Add a compile flag such as `--locked` / `--frozen` if it fits existing CLI
  style.
- Reuse `workspace_lock` / `verify_lock` / `check_workspace_integrity`.
- Add package CLI tests.
- Update docs/surface docs.

Closed:

- No lockfile format change unless unavoidable.
- No registry, semver, solver, signing, remote source, install hook, or package
  manager redesign.
- No VM/server/machine/frame-ui changes.
- No canon `igniter-lang` changes.

## Questions To Answer

1. What command shape best matches existing `lock --frozen` / `verify --strict`?
2. Should enforcement be default-on only when `igniter.lock` exists, or flag-only?
3. How should diagnostics distinguish missing lock, stale lock, and integrity
   failure?
4. Does compile use the exact same digest/integrity code as CI verify?

## Acceptance

- [x] A project compile can be run in lock-enforced mode.
- [x] Stale lock fails before emit/assemble writes misleading fresh artifacts.
- [x] Missing lock behavior is explicit and tested.
- [x] Clean lock succeeds.
- [x] Single-file compile behavior remains unchanged.
- [x] `verify --strict` behavior remains unchanged.
- [x] Audit/status docs updated to say what is now enforced and what remains
      CI-only.
- [x] `git diff --check` passes.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler
cargo test --test package_lockfile_cli_tests
cargo test --test package_workspace_tests
cargo test --test project_mode_tests
```

Then from repo root:

```bash
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-igniter-compiler-lock-on-build-p2-v0.md
```

Include chosen CLI shape, drift/missing behavior, tests, and the remaining
supply-chain gaps if any.

## Closing Report

Closed in:

```text
lab-docs/lang/lab-igniter-compiler-lock-on-build-p2-v0.md
```

Implemented `compile --project-root ... --locked` with `--frozen` alias. The
gate reads `igniter.lock`, reuses `verify_lock`, then reuses
`check_workspace_integrity` before project resolve/emit. Missing/stale lock
prints structured `compiler_result` diagnostics and writes no `.igapp`. Plain
project compile and single-file compile remain unchanged.
