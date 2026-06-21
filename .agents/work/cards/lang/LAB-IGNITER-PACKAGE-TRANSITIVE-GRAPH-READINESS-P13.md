# LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-READINESS-P13 — local transitive dependency graph

Status: CLOSED
Lane: standard / lab readiness
Type: design-readiness
Delegation code: OPUS-IGNITER-PACKAGE-TRANSITIVE-GRAPH-READINESS-P13
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Package-manager v0 now has a strong local-first spine:

- P2 direct local path dependencies folded into project assembly.
- P3–P6 lock provenance: dependency content digest + compiler + stdlib surface.
- P7 package-level import scoping (`OOF-IMP6`).
- P8 CI trust gate (`lock --frozen`, `verify --strict`).
- P9–P12 module exports (`OOF-IMP7`) + structured strict diagnostics + opt-in closed default.

The largest remaining practical package limitation is **direct dependencies only**. A reusable local package
cannot depend on another local package and have that graph assembled transitively. This card designs the
minimal local transitive graph without opening registry/semver/solver.

## Goal

Produce a readiness packet that chooses the v0 transitive graph model and prepares P14 implementation.
The design must preserve the authority boundaries already proven:

- explicit local path edges only;
- no registry, version solver, semver, network;
- package-level scope must follow declared graph edges, not accidental index presence;
- module exports must be enforced for every consumer -> provider edge;
- strict CI must check the same graph/integrity as compile.

## Verify first

- `lang/igniter-compiler/src/project.rs`
  - `ProjectConfig::load`, `Dependency`, `ExportsDefault`, `ProjectConfig.exports`.
  - `build_module_index`, `PackageId`, `ModuleIndex.dep_exports`, `package_in_scope`, `index_integrity`.
  - `dependency_digest`, `workspace_lock`, `verify_lock`, `check_workspace_integrity`.
- `lang/igniter-compiler/tests/package_workspace_tests.rs`.
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs`.
- Existing fixtures: `workspace_direct`, `workspace_phantom`, `workspace_exports_*`, `workspace_closed_*`.
- P2/P7/P10/P12/P8 proof docs.

## Questions to answer

1. What is a package identity in v0?
   - manifest dependency name at the parent edge;
   - canonical path;
   - module namespace;
   - combination of name + canonical path.
2. How are transitive edges collected?
   - breadth/depth order;
   - deterministic ordering;
   - path normalization relative to each package root.
3. How to handle duplicate package names from different parents?
4. How to handle the same physical package reached through two paths/names?
5. What diagnostics for graph faults?
   - cycle;
   - duplicate package identity;
   - missing dependency path;
   - duplicate module still `OOF-IMP4`.
6. How should `OOF-IMP6` change?
   - dependency package P may import package Q iff P declares Q as a dependency;
   - root may import direct deps only or any reachable transitive dep?
7. Should root be allowed to import transitive dependencies directly?
   - likely **no**: if root wants it, root must declare it directly. This matches dependency hygiene.
8. How do exports compose transitively?
   - every consumer -> provider edge checks provider's exports;
   - same-package imports bypass exports;
   - closed-default policy: root-only or each consumer package's own policy?
9. Does the lock include only direct dependencies or full graph?
10. Does `dependency_digest` for a package include its manifest only, its own `.ig` files, or also transitive
    dependency digests?
11. How does `verify --strict` report graph/integrity faults structurally?
12. What is the smallest fixture matrix that proves graph behavior without registry complexity?

## Bias / initial hypothesis

Prefer **explicit local path graph closure**:

- recursively read `[dependencies]` from each local package;
- package node identity = canonical package root path, with a display name from the edge;
- lock records the full reachable package set, sorted by canonical path or stable display path;
- root may import only direct dependencies; a dependency may import its own direct dependencies; no package
  may import an undeclared sibling/transitive dependency;
- exports are checked on every declared consumer -> provider edge;
- no diamond version solving: if two paths resolve to the same canonical package, treat as one node; if the
  same module is provided twice, existing `OOF-IMP4` catches module ambiguity.

Treat closed-default carefully. The P12 policy is root consumer policy. For transitive edges, a dependency's
own `[package] exports = "closed"` may be the natural consumer policy for its outgoing edges, but this must
be decided explicitly.

## Closed scope

- No registry, semver, solver, lockfile package versions, remote sources, publishing.
- No module wildcard exports.
- No `.ig` syntax.
- No server/web/machine/typechecker/VM changes.
- No global Cargo workspace restructuring.
- Do not implement P14 in this card.

## Required deliverable

`lab-docs/lang/lab-igniter-package-transitive-graph-readiness-p13-v0.md`

Must include:

- live verify-first findings;
- decision matrix for identity/traversal/root-transitive-import/default-export policy;
- diagnostic taxonomy;
- lockfile/provenance decision;
- exact P14 implementation acceptance tests.

## Required acceptance

- [x] All questions answered explicitly.
- [x] Package identity/traversal chosen.
- [x] Root direct-vs-transitive import policy chosen.
- [x] Exports policy across transitive edges chosen.
- [x] Lock/provenance behavior chosen.
- [x] P14 implementation card can proceed without rediscovery.
- [x] No code changes.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-transitive-graph-readiness-p13-v0.md` — readiness packet,
no code (`git diff --check` clean).

**Verify-first (live `project.rs`):** `PackageId::Dependency(name)` uses the root-edge name (not graph-unique
→ identity must become canonical path); `package_in_scope` is direct-only (`Dependency→false` → must become
per-package edge); `build_module_index` folds only `config.dependencies` (→ recursive closure); `dep_exports`
keyed by name (→ re-key by canonical path); `workspace_lock` records direct only (→ full reachable set);
`dependency_digest` = own content (keep, no nesting); `normalize_abs` available; OOF-IMP1..7 used →
**OOF-IMP8/9 free**. **Migration flagged:** `workspace_direct` + `direct_dependencies_only` invert under
transitive (P14 rewrites them).

**Decisions:** identity = **canonical package root path** (display name from edge; diamonds dedup by path);
traversal = recursive explicit-path `[dependencies]` closure (paths relative to each package root, sorted,
`visited`-bounded); `OOF-IMP6` generalized to **per-package declared edges**; **root may import only direct
deps** (no transitive direct import; re-declare to use); exports checked on **every** consumer→provider edge,
closed-default = **root-global** (per-consumer deferred); **cycle = OOF-IMP8**, missing-path = OOF-IMP9
(recommended); lock = **full reachable set** (root-relative canonical path, flat per-package digest);
`verify --strict` reuses shared `index_integrity` with P11 structured diagnostics.

**P14 enumerated:** 6 fixtures (tgraph_ok / root_undeclared / phantom / cycle / diamond / exports) + 10
acceptance tests incl. the `direct_dependencies_only`→`transitive_dependencies_are_pulled` migration and a
full-graph lock test. **Next:** `LAB-IGNITER-PACKAGE-TRANSITIVE-GRAPH-P14` (implement). Registry/semver far later.
