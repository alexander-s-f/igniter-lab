# LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10 — enforce dependency module exports

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-MODULE-EXPORTS-P10
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9`.

P7 enforces package-level scope: root can import declared dependencies, dependencies cannot phantom-import
siblings/root. But if root declares `lib`, it can still import any module inside `lib`. P10 implements the
v0 module export boundary chosen by P9.

## Goal

Implement module-level exports for local path dependencies, preserving the P7/P8 authority split:

- same-package imports are always allowed;
- root -> declared dependency is allowed only when the target dependency module is exported by that
  dependency;
- dependency -> sibling/root remains `OOF-IMP6`;
- in-scope package but non-exported module becomes a new diagnostic (`OOF-IMP7`, unless P9 chooses another).

## Required implementation shape (unless P9 changes it)

1. Extend `ProjectConfig` to parse dependency-owned exports from `igniter.toml`, likely:

   ```toml
   source_roots = ["src"]

   [exports]
   modules = ["Lib.Public"]
   ```

2. Keep parser deterministic and small, consistent with existing hand-rolled `igniter.toml` parsing.
3. Track exported modules per `PackageId::Dependency(name)` during index construction / integrity checks.
4. Extend shared integrity (`index_integrity`) so compile path and `verify --strict` enforce the exact same
   export rule.
5. Diagnostic must be deterministic and name:
   - importer module + package,
   - imported module + package,
   - non-exported target module,
   - importer source path.
6. Keep dangling imports as OOF-IMP2. Do not mask missing-module diagnostics.

## Required fixtures

Create small fixtures under `lang/igniter-compiler/tests/fixtures/project_mode/`:

1. `workspace_exports_ok`
   - `app` depends on `lib`.
   - `lib/igniter.toml` exports `Lib.Public`.
   - `app` imports `Lib.Public`.
   - Resolves and compiles clean.
2. `workspace_exports_private`
   - `app` depends on `lib`.
   - `lib/igniter.toml` exports `Lib.Public`.
   - `app` imports `Lib.Private`.
   - Fails with `OOF-IMP7`.
3. Same-package private import remains allowed:
   - `Lib.Public import Lib.Private` inside the same `lib` package.
   - Root imports only `Lib.Public`.
   - Resolves clean.
4. If P9 chooses default-open compatibility, add a fixture proving no-export dependency remains open and a
   note in the proof doc. If P9 chooses default-closed, update existing package fixtures with explicit
   exports and prove old behavior through updated fixtures.

## Required tests

In `package_workspace_tests.rs`:

- exported module import allowed.
- non-exported dependency module rejected as `OOF-IMP7`.
- same-package import of private module allowed.
- P7 phantom sibling remains `OOF-IMP6` (not accidentally reclassified).
- declared root->dependency import in existing fixture still works after explicit exports/default behavior.
- `check_workspace_integrity` reports `OOF-IMP7` entry-free.

In CLI tests:

- `igc verify --strict` catches `OOF-IMP7`.
- Plain `verify` remains drift-only unless P9 changes this.

Run:

```bash
cd lang/igniter-compiler
cargo test --test package_workspace_tests
cargo test --test package_lockfile_cli_tests
cargo test --test project_mode_tests
cargo test --test project_overlay_tests
cargo test
```

## Closed scope

- No transitive dependency graph.
- No registry/semver/solver.
- No module wildcard/glob exports unless P9 explicitly chooses them.
- No `.ig` syntax changes.
- No VM/typechecker/server/web changes.
- No lockfile format bump unless proven necessary. If export changes are already covered by dependency
  digest, document that instead.

## Required proof doc

`lab-docs/lang/lab-igniter-package-module-exports-p10-v0.md`

Must include:
- final export syntax/default behavior;
- OOF-IMP6 vs OOF-IMP7 taxonomy;
- fixtures and exact test counts;
- strict verify behavior;
- whether lock digest already covers export metadata;
- deferred work.

## Required acceptance

- [x] Exports parsed from dependency metadata (or P9-selected source).
- [x] Root cannot import non-exported dependency module.
- [x] Same-package imports remain unrestricted.
- [x] Phantom package edge remains `OOF-IMP6`.
- [x] Non-exported module edge is deterministic `OOF-IMP7`.
- [x] Compile path and `verify --strict` share one integrity implementation.
- [x] Full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests):** `ProjectConfig.exports: Option<Vec<String>>` + section-scoped
`parse_exports_toml` (mirrors `parse_dependencies_toml`; `None`=open, `Some`=allowlist, `Some([])`=sealed);
`ModuleIndex.dep_exports` (dep name → export set) populated in `build_module_index`; OOF-IMP7 pass in the
shared `index_integrity` after OOF-IMP6 (root→dependency edges only); **`dependency_digest` folds the
dependency `igniter.toml`** so exports changes are lock drift (P9 §7 gap closed, also covers latent
source_roots/deps changes). Proof doc: `lab-docs/lang/lab-igniter-package-module-exports-p10-v0.md`.

**Decisions (per P9):** manifest `[exports] modules`, exact paths, **opt-in closure**, OOF-IMP7 layered after
OOF-IMP6, enforced in shared integrity (compile + `--strict`).

**Live smoke:** `compile` non-exported import → `OOF-IMP7: non-exported import: module 'App.Main' imports
'Lib.Private' (package lib), which package 'lib' does not export`; `verify --strict` → `integrity.rule=OOF-IMP7`,
exit 1, while plain `verify` (drift-only) exits 0; editing `lib/igniter.toml` exports → `verify` `changed` drift.

**Proof — all green:** `package_workspace_tests` **30** (25 + 5 P10), `package_lockfile_cli_tests` **13**
(11 + 2 P10), `project_mode` 9 + `project_overlay` 10 intact (digest fold + integrity refactor preserved),
full `igniter-compiler` suite green (0 failed), `git diff --check` clean. Fixtures `workspace_exports_ok` /
`workspace_exports_private`. No `.ig` syntax / server / web / machine change; no new crate.

**Deferred:** closed-by-default (global opt-in, `…-EXPORTS-CLOSED-DEFAULT-P*`); glob exports; `.ig` `pub`;
transitive package graph; registry/semver. **Next:** closed-default opt-in OR transitive graph (user's sequencing).

