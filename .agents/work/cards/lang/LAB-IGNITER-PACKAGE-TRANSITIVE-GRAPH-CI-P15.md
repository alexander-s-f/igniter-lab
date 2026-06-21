# LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15 — graph lock/strict hardening

Status: CLOSED
Lane: standard / lab readiness
Type: readiness / follow-up
Delegation code: OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-CI-P15
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on P13/P14.

Once transitive local graph assembly exists, P8/P11 CI trust must be rechecked against graph reality:

- Does `igniter.lock` pin the full reachable graph?
- Does `lock --frozen` catch a leaf package edit?
- Does `verify --strict` report graph faults structurally enough for agents?
- Does `dependency_digest` double-count or miss manifest changes?

P15 is the hardening pass after P14, not a broad feature expansion.

## Goal

Review P14's live behavior and decide whether a small hardening patch is needed. If yes, implement only the
smallest CI/provenance fix. If P14 is already sufficient, close as no-code readiness with evidence.

## Verify first

- P14 implementation and proof doc.
- `workspace_lock`, `verify_lock`, `dependency_digest`.
- `run_lock --frozen`, `run_verify --strict`.
- New transitive fixtures.
- Existing P8/P11 CLI tests.

## Questions to answer

1. Does lock JSON include every reachable package or only root-direct dependencies?
2. If a leaf package `.ig` file changes, does `verify` report drift?
3. If a leaf package `igniter.toml` changes, does `verify` report drift?
4. Does `lock --frozen` catch leaf drift without writing?
5. Does `verify --strict` catch transitive `OOF-IMP6` / `OOF-IMP7` with structured diagnostics?
6. Are graph-cycle diagnostics represented structurally enough for CI?
7. Should lock entries include parent/path provenance for transitive packages?
8. Is there any duplicate canonical path / duplicate name ambiguity that needs a P15 fix rather than a later
   solver/identity card?

## Bias

Prefer full reachable graph lock entries if P14 did not already do that. A CI trust gate is only honest if
changes to leaf dependencies move the lock or fail frozen mode. But do not open version solving or registry
semantics.

## Closed scope

- No registry/semver/solver.
- No remote sources.
- No package publish format.
- No full edition system.
- No `.ig` syntax.
- No server/web/machine/typechecker/VM work.

## Required deliverable

Either:

1. readiness-only packet:
   `lab-docs/lang/lab-igniter-package-transitive-graph-ci-p15-v0.md`

or, if hardening is needed:

2. implementation proof doc at the same path plus tests.

## Required acceptance

- [x] P14 lock/frozen/strict behavior verified live.
- [x] Leaf `.ig` and leaf manifest drift behavior proven.
- [x] Decision made: no-code vs small hardening.
- [x] If code changes: P14/P8/P11 tests + full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Decision: test-only hardening** — no production code. Live verify-first showed P14 already covers the CI
trust gate for the transitive graph; P15 regression-locks the gaps P14 only proved live.

**Live evidence (all ✓):** lock pins full graph (mid+leaf); leaf `.ig` drift → `changed`; **leaf manifest**
(`igniter.toml`) edit → `changed` drift (P10 fold applies per-node); `lock --frozen` → `out-of-date` +
lockfile byte-unchanged; `verify --strict` transitive `OOF-IMP6` → structured (`module_path`/`node`/
`source_paths`); cycle `OOF-IMP8` structured. **Q7** (lock parent provenance) = NO (path suffices). **Q8**
(canonical/name ambiguity) = NO fix (path identity dedups; verify matches by path).

**Tests:** +4 CLI regression tests over existing P14 fixtures (`cli_leaf_manifest_change_is_drift`,
`cli_frozen_catches_leaf_drift`, `cli_verify_strict_catches_transitive_phantom`,
`cli_verify_strict_catches_transitive_non_export`). `package_lockfile_cli_tests` **21** (17 + 4),
`package_workspace_tests` 41 intact, full suite green (0 failed), `git diff --check` clean. Proof doc:
`lab-docs/lang/lab-igniter-package-transitive-graph-ci-p15-v0.md`.

**Deferred:** lock parent provenance; OOF-IMP9; per-consumer closed-default; remote/registry/semver. The
LOCAL package model is feature-complete + regression-locked for v0. **Next:** remote/registry wave OR DX polish.
