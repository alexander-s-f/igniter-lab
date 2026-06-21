# LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14 — implement local transitive package graph

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-READINESS-P13`.

P2 currently folds only root-declared direct dependencies. A dependency's own `[dependencies]` are ignored,
which prevents reusable local packages from depending on other local packages. P14 implements the P13-selected
minimal transitive local graph.

## Goal

Implement local transitive dependency graph assembly while preserving P7/P10 boundaries:

- graph edges are explicit local path dependencies;
- root cannot accidentally import a transitive dependency unless P13 explicitly allows it;
- each package can import its own declared dependencies;
- phantom imports remain `OOF-IMP6`;
- non-exported module imports remain `OOF-IMP7`;
- lock/verify/frozen/strict use the same graph.

## Required implementation shape (unless P13 changes it)

1. Replace direct-only dependency folding with deterministic graph collection:
   - root package node;
   - recursively load local dependency manifests;
   - normalize dependency paths relative to the declaring package;
   - keep stable order for scanning and diagnostics.
2. Track package metadata per node:
   - package id / display name;
   - canonical root path;
   - direct dependency names/targets;
   - exports;
   - exports default policy.
3. Update `PackageId` / `ModuleIndex` / `package_in_scope` so import scope follows declared graph edges.
4. Update `dependency_digest` / `workspace_lock` if P13 chooses full graph locks.
5. Update `check_workspace_integrity` and `verify --strict` through the existing shared integrity path.
6. Add deterministic diagnostics for cycles or graph faults selected by P13.

## Required fixtures

Create focused fixtures under `lang/igniter-compiler/tests/fixtures/project_mode/`:

1. `workspace_transitive_ok`
   - `app -> mid -> leaf`.
   - `app` imports `Mid.Public`.
   - `Mid.Public` imports exported `Leaf.Public`.
   - resolves and compiles clean.
2. `workspace_transitive_root_phantom`
   - `app -> mid -> leaf`.
   - `app` imports `Leaf.Public` without declaring `leaf`.
   - expected diagnostic per P13 (likely `OOF-IMP6`).
3. `workspace_transitive_dep_phantom`
   - `app -> mid, leaf`.
   - `mid` imports `Leaf.Public` without declaring `leaf`.
   - remains `OOF-IMP6`.
4. `workspace_transitive_non_export`
   - `mid` declares `leaf`, but imports `Leaf.Private` not exported by leaf.
   - `OOF-IMP7`.
5. `workspace_transitive_cycle`
   - local path cycle.
   - deterministic graph diagnostic selected by P13.

## Required tests

In `package_workspace_tests.rs`:

- transitive dep import from declaring dependency allowed.
- root cannot import transitive dep unless declared directly (or P13-selected alternative).
- dependency cannot import sibling it did not declare.
- transitive non-exported import => `OOF-IMP7`.
- cycle diagnostic deterministic.
- existing direct fixtures still pass.
- P7/P10/P12 tests remain green.

In `package_lockfile_cli_tests.rs`:

- `igc verify --strict` catches transitive phantom/non-export.
- `igc lock --frozen` detects transitive dependency content drift if P13 chooses full graph lock.

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

- No registry/semver/solver.
- No remote dependencies.
- No version conflict resolution.
- No publishing/package cache.
- No `.ig` syntax changes.
- No server/web/machine/typechecker/VM changes.

## Required proof doc

`lab-docs/lang/lab-igniter-package-transitive-graph-p14-v0.md`

Must include:

- final graph identity/traversal model;
- import scope semantics;
- exports behavior across transitive edges;
- lock/provenance behavior;
- diagnostics and exact test counts;
- deferred work.

## Required acceptance

- [x] Local transitive dependencies are assembled deterministically.
- [x] Packages may import only their declared dependency edges.
- [x] Root direct-vs-transitive import policy from P13 enforced.
- [x] Exports enforced across transitive edges.
- [x] Cycle / graph fault diagnostic deterministic.
- [x] `verify --strict` uses the same graph/integrity implementation as compile.
- [x] Lock/frozen behavior matches P13.
- [x] Full `igniter-compiler` suite green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests):** `PackageId::Package(PathBuf canonical)` + `PackageNode`/
`PackageGraph`; `collect_package_graph` (recursive explicit-path closure, `normalize_abs` identity,
diamond-dedup, `visited`-bounded); `detect_cycle`/`cycle_dfs` (**OOF-IMP8**); `relative_to` (root-relative
lock paths). `build_module_index` scans every graph node; `index_integrity(&index)` runs OOF-IMP4 → IMP8 →
IMP6 (graph-edge scope: P imports Q iff P declares Q) → IMP7 (every consumer→provider edge); `workspace_lock`
walks the full graph, `verify_lock` matches by path. Removed `package_in_scope`. Proof doc:
`lab-docs/lang/lab-igniter-package-transitive-graph-p14-v0.md`.

**Per P13 decisions:** canonical-path identity; root imports direct-only (transitive direct → OOF-IMP6);
exports root-global closed-default; full-graph flat lock; OOF-IMP9 (missing-path) deferred.

**Live smoke:** transitive_ok compiles clean; cycle → `OOF-IMP8: dependency cycle in the local package graph:
a -> b -> a`; root-phantom → OOF-IMP6; `verify --strict` cycle → integrity OOF-IMP8 exit 1.

**Proof — all green:** `package_workspace_tests` **41** (34 + 7 P14), `package_lockfile_cli_tests` **17**
(15 + 2 P14), `project_mode` 9 + `project_overlay` 10 intact, full `igniter-compiler` suite green (0 failed),
`git diff --check` clean. 6 new fixtures. **Migration:** `direct_dependencies_only`→`transitive_dependency_is_assembled`
(`workspace_direct/mid` now declares+imports `deep`). All P7/P10/P12 tests stay green (scope/exports now
graph-aware). No `.ig`/server/web/machine change; no new crate.

**Deferred:** OOF-IMP9 missing-path; per-consumer closed-default; glob exports; **remote/registry/semver**
(next major wave). The **local** package model is feature-complete for v0.
