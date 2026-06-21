# LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2 — local workspace path-dependency resolver

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-PACKAGE-MANAGER-READINESS-P1` validated the round-1 direction against live `project.rs` and
recommended the smallest v0 slice: a **local workspace resolver**. The key finding was that Igniter already
has the substrate (`igniter.toml source_roots`, logical-module-path imports, deterministic `compile_units`
source-hash, and an **existing duplicate-module-ownership check** `OOF-IMP4`), so the resolver is a small,
deterministic extension — **not** a registry, solver, lockfile, or install-hook system.

## Goal

Let a workspace `igniter.toml` declare **local path dependencies**, fold each dependency's source roots into
the **same** project module index, so cross-package `import Foo.Bar` resolves and duplicate module ownership
across packages is caught — reusing the existing `OOF-IMP4` machinery.

```toml
source_roots = ["src"]

[dependencies]
lib = { path = "../lib" }
```

## Closed scope

- No registry, no network, no version solver (MVS/SAT), no version ranges.
- No lockfile / provenance (separate `…-PACKAGE-LOCK-PROVENANCE-P3`).
- No install/build hooks or package-provided executables.
- No transitive **package** graph (direct dependencies only; a dep's own `[dependencies]` are not pulled in v0).
- No Cargo-style features.
- No `.igapp` in the package; no capability manifest (later).
- No `igniter-server`/`igniter-web`/`igniter-machine` change.
- No new dependency crate; no canon claim.

## Verify first

- `lang/igniter-compiler/src/project.rs` — `ProjectConfig::load`, `parse_source_roots_toml`,
  `build_module_index`, `resolve_entry(_with_overlays)`, the `OOF-IMP4` duplicate path.
- `lang/igniter-compiler/tests/project_mode_tests.rs`, `tests/fixtures/project_mode/{basic,dup_module,transitive}`.
- `lang/igniter-compiler/src/main.rs` `resolve_entry_with_overlays` call site.

Confirm: `ProjectConfig` is constructed only in `load` (safe to add a field); the duplicate check already
emits `OOF-IMP4`; transitive **import** closure already spans the whole index.

## Required implementation

In `project.rs` only:
1. `ProjectConfig` += `dependencies: Vec<PathBuf>` (relative paths to local dependency package roots).
2. `ProjectConfig::load` parses a `[dependencies]` table (`name = { path = "X" }` or `name = "X"`),
   hand-rolled (no toml crate), defaulting to empty.
3. `build_module_index`: after scanning the workspace's own `source_roots`, for each dependency load its
   own `ProjectConfig` and scan its source roots under the dependency path, adding those files to the same
   index. Direct dependencies only.

The existing duplicate check, missing-import (`OOF-IMP2`), entry resolution, deterministic ordering, and
overlay behavior are unchanged. A workspace with **no** `[dependencies]` is byte-identical to P1.

## Required tests (new fixtures under `tests/fixtures/project_mode/`)

1. **cross-package import resolves:** `workspace_app` (entry imports `Lib.Util`) + `workspace_lib` (declares
   `Lib.Util`); `resolve_entry` returns both files; the combined project compiles clean.
2. **duplicate module across packages → `OOF-IMP4`:** app and dependency both declare the same module.
3. **no-deps parity:** an `igniter.toml` without `[dependencies]` resolves byte-identically to P1.
4. **direct-only:** a dependency's own `[dependencies]` are NOT pulled in (documented v0 limit).

## Required acceptance

- [x] `ProjectConfig` carries `dependencies`; `[dependencies]` parsed (path table + bare string).
- [x] Cross-package `import` resolves through `resolve_entry`.
- [x] Duplicate module across packages → `OOF-IMP4` (reused, not new).
- [x] No-deps projects unchanged (P1 parity).
- [x] Direct-dependencies-only documented and tested.
- [x] `cargo test` for `igniter-compiler` green (existing project/overlay tests intact).
- [x] No server/web/machine change; no new crate dependency.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests only):** `ProjectConfig` += `dependencies: Vec<PathBuf>`;
`ProjectConfig::load` parses a section-aware `[dependencies]` table (`name = { path = "X" }` or `name = "X"`,
hand-rolled, no toml crate); `build_module_index` folds each **direct** dependency's source roots into the
**same** index. Proof doc: `lab-docs/lang/lab-igniter-package-workspace-resolver-p2-v0.md`.

**Key reuse (P1's finding proven):** cross-package collisions reuse the **existing `OOF-IMP4`** duplicate
check, and cross-package imports resolve via the **existing transitive-import closure** — the resolver only
**widens the scanned file set**. A no-`[dependencies]` project is byte-identical to P1.

**Proof — all green:** resolver slice in `package_workspace_tests` **6 passed** (incl. `cross_package_project_compiles_clean`
and `bare_string_dependency_path_resolves`);
— the dependency's `Widget` type links into the app contract and compiles clean through the **real multifile
compiler**); `project_mode_tests` 9 + `project_overlay_tests` 10 intact; full `igniter-compiler` suite green
(57 lib + all bins, 0 failed); `git diff --check` clean. No server/web/machine change, no new crate dep.

**v0 limits (explicit + tested):** direct dependencies only (a dep's own `[dependencies]` not traversed —
`direct_dependencies_only` test); no registry/solver/lock/hooks/`.igapp`/capabilities.

**Next:** `LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3` (blake3 per-workspace lock over each dep's deterministic
source set), then strict direct-dep-only import enforcement, then much later registry/solver.

## Required proof doc

`lab-docs/lang/lab-igniter-package-workspace-resolver-p2-v0.md` — change summary, why it reuses `OOF-IMP4`,
fixture shapes, exact tests/counts, v0 limits (direct-only, no lock/registry/hooks), next card
(`…-PACKAGE-LOCK-PROVENANCE-P3`).
