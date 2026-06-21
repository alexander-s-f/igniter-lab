# lab-igniter-package-transitive-graph-p14-v0 — local transitive package graph

**Card:** `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14` · **Delegation:** `OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14`
**Status:** CLOSED (lab implementation-proof) — the direct-only limitation is lifted. A local package may
depend on another local package; the graph is assembled by **recursive explicit path edges**, with identity =
**canonical package root path**, **graph-edge-aware** import scope, **root direct-only** imports, exports on
**every** consumer→provider edge, a **cycle** diagnostic (`OOF-IMP8`), and a **full-graph** lock. **`project.rs`
+ tests only — no registry/semver/solver, no `.ig` syntax, no server/web/machine change, no new crate.**

## Model (from the P13 packet, implemented)

- **Identity** = canonical package root path (`normalize_abs`); display name = the smallest declaring edge
  name. A diamond (two parents → same path) resolves to **one** node.
- **Traversal** = recursive closure over each package's `[dependencies]`, each path relative to the declaring
  package, `visited`-bounded; deterministic (`BTreeMap`/`BTreeSet`).
- **Scope (OOF-IMP6, generalized):** a package P may import a module of package Q iff **P declares Q** (graph
  edge) or P == Q (same package). Reaching an undeclared sibling/transitive package — **or the root** — is a
  fault. **Root may import only its direct deps** (re-declare a transitive package to use it).
- **Exports (OOF-IMP7):** checked on **every** consumer→provider edge (not just root→dep), keyed by the
  provider's canonical path; same-package bypasses; closed-default = the **root's** `[package] exports` policy,
  global across the graph (P12).
- **Cycle (OOF-IMP8, new):** a cycle in the package graph is an assembly fault, detected by DFS back-edge.
- **Lock:** the **full reachable package set** (excluding the root), each entry `{name, root-relative
  canonical path, own-content digest}`, sorted by path. Per-package digest = manifest + `.ig` (P10); **no
  nested child digests** — a transitive change surfaces as that package's own entry changing. `verify` matches
  by **path** (names can collide across the graph).

## What changed (`project.rs`)

- `PackageId::Dependency(String)` → `PackageId::Package(PathBuf /*canonical*/)`; `+ PackageNode`/`PackageGraph`.
- `collect_package_graph` (recursive closure); `detect_cycle` + `cycle_dfs` (OOF-IMP8); `relative_to`
  (root-relative lock paths). `package_in_scope` removed.
- `build_module_index` scans **every graph node** (root → `Root`, others → `Package(canon)`), one scan per
  node (diamond dedup). `ModuleIndex` now carries the `graph` + the root `exports_default` (replaced
  `dep_exports`).
- `index_integrity(&index)` (was `(&index, &config)`): OOF-IMP4 → **OOF-IMP8 cycle** → OOF-IMP6 (graph edges)
  → OOF-IMP7 (every edge). Shared by compile + `verify --strict` (unchanged seam, P11 structured output).
- `workspace_lock` walks the full graph; `verify_lock` matches by path.

## Diagnostic taxonomy

| Code | Meaning |
|---|---|
| `OOF-IMP4` | duplicate module declaration (whole index) |
| `OOF-IMP6` | importer's package does not **declare** the provider's package (sibling / transitive / root) |
| `OOF-IMP7` | declared edge, module not exported by the provider (+ closed-default seal) |
| `OOF-IMP8` | **cycle** in the local package graph |

(`OOF-IMP9` for a missing declared dependency path was deferred — a missing dir folds nothing, so the import
falls to `compile_units` `OOF-IMP2`.)

## Live behavior (smoke)

```text
$ igc compile … workspace_transitive_ok/app          # app→mid→leaf, all declared, Leaf.Public exported
  → 0 error diagnostics (compiles clean)

$ igc compile … workspace_transitive_cycle/app
  → { "rule": "OOF-IMP8", "message": "dependency cycle in the local package graph: a -> b -> a" }

$ igc compile … workspace_transitive_root_phantom/app  # app imports Leaf.Public but declared only mid
  → { "rule": "OOF-IMP6" }

$ igc verify --strict … workspace_transitive_cycle/app → integrity.diagnostic.rule = OOF-IMP8, exit 1
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 41 passed (34 + 7 NEW P14)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 17 passed (15 + 2 NEW P14)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests            → 9 passed
$ cd lang/igniter-compiler && cargo test --test project_overlay_tests         → 10 passed
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P14 tests: API (7) — `transitive_declared_edge_resolves`, `root_cannot_import_transitive_dep` (OOF-IMP6),
`dependency_cannot_import_undeclared_sibling` (OOF-IMP6), `transitive_non_exported_import_is_oof_imp7`,
`package_graph_cycle_is_oof_imp8`, `diamond_same_package_dedups`, `lock_records_full_transitive_graph`. CLI
(2) — `cli_verify_strict_catches_cycle` (OOF-IMP8), `cli_transitive_content_drift_detected` (transitive leaf
edit → `changed` drift). 6 new fixtures (`workspace_transitive_{ok,root_phantom,dep_phantom,non_export,cycle,
diamond}`).

**Migration (per P13):** the old `direct_dependencies_only` test + `workspace_direct` fixture inverted under
transitive — `mid` now declares **and imports** `deep`, so `deep` is assembled. The test was rewritten as
`transitive_dependency_is_assembled` (asserts `d.ig` **is** in the closure through the declared `mid→deep`
edge). All P7/P10/P12 phantom/export/closed-default tests stay green (scope/exports now graph-aware).

## Acceptance — mapping

- [x] Local transitive dependencies assembled deterministically (recursive closure, canonical-path identity).
- [x] Packages may import only their declared dependency edges (OOF-IMP6 generalized).
- [x] Root direct-only import policy enforced (transitive direct import → OOF-IMP6).
- [x] Exports enforced across transitive edges (OOF-IMP7 on every consumer→provider edge).
- [x] Cycle diagnostic deterministic (`OOF-IMP8`).
- [x] `verify --strict` uses the same `index_integrity` as compile.
- [x] Lock = full reachable graph (path-keyed); transitive content drift detected.
- [x] Full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (PackageId/PackageNode/PackageGraph; `collect_package_graph`,
  `detect_cycle`/`cycle_dfs`, `relative_to`; `build_module_index`, `index_integrity`, `workspace_lock`,
  `verify_lock` rewrites; removed `package_in_scope`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+7 P14 tests; migrated `direct_dependencies_only`).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+2 P14 CLI tests).
- `tests/fixtures/project_mode/workspace_transitive_*` (6 new); `workspace_direct/mid` migrated.

## Deferred (explicit)

- `OOF-IMP9` (missing declared dependency path) — falls to OOF-IMP2 today.
- Per-consumer (non-root) closed-default policy; module glob exports.
- Registry/semver/solver, remote sources, version conflict resolution, publishing — far later.

## Next

The local package model is feature-complete for v0 (direct + transitive graph, content+toolchain lock,
scope, exports, closed-default, CI gate). The next frontier is **remote/registry** (semver, fetch, cache) —
a large separate wave — or DX polish (`OOF-IMP9`, `igc package` introspection). Per the user's sequencing.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 41 green, `package_lockfile_cli_tests`
17 green, `project_mode` 9 + `project_overlay` 10 intact, full `igniter-compiler` suite green, `git diff
--check` clean. A local package can now depend on another local package — recursive explicit-path graph,
canonical-path identity, graph-edge scope, per-edge exports, cycle = OOF-IMP8, full-graph lock.*
