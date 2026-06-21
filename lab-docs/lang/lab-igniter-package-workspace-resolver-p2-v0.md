# lab-igniter-package-workspace-resolver-p2-v0 — local workspace path-dependency resolver

**Card:** `LAB-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2` · **Delegation:** `OPUS-IGNITER-PACKAGE-WORKSPACE-RESOLVER-P2`
**Status:** CLOSED (lab implementation-proof) — a workspace `igniter.toml` can declare **local path
dependencies**; each dependency's source roots are folded into the **same** project module index, so
cross-package `import Foo.Bar` resolves and duplicate module ownership across packages is caught by the
**existing `OOF-IMP4`** check. **Direct dependencies only; no registry, no version solver, no lockfile, no
install hooks. `project.rs` + tests only — no server/web/machine change, no new crate dependency.**

## Why this is tiny (the P1 finding, proven)

P1's validation said the substrate already exists. Confirmed in `project.rs`:
- `ProjectConfig::load` already reads `igniter.toml` `source_roots`;
- `build_module_index` already scans source roots and **already accumulates duplicate module declarations**;
- `resolve_entry_with_overlays` already emits **`OOF-IMP4`** for any duplicate and walks the transitive
  **import** closure over the whole index.

So the resolver is: **widen the scanned file set to include declared dependency packages.** Cross-package
imports then resolve through the existing closure, and cross-package module collisions are caught by the
existing `OOF-IMP4` — **reused, not re-implemented.**

## What changed (`project.rs` only)

1. **`ProjectConfig` += `dependencies: Vec<PathBuf>`** — relative paths to local dependency package roots.
2. **`ProjectConfig::load`** parses a `[dependencies]` table (section-aware, hand-rolled, no toml crate):
   ```toml
   source_roots = ["src"]
   [dependencies]
   lib = { path = "../lib" }     # canonical (future-proof for version/git)
   other = "../other"            # bare-string shorthand also accepted
   ```
   Defaults to empty; a project with no `[dependencies]` is **byte-identical to P1**.
3. **`build_module_index`** — after scanning the workspace's own `source_roots`, for each dependency it
   loads the dependency's **own** `ProjectConfig` and scans **its** source roots under the dependency path,
   adding those files to the same index. **Direct dependencies only** — a dependency's own `[dependencies]`
   are **not** traversed (no transitive package graph in v0).

The duplicate check, missing-import (`OOF-IMP2`), entry resolution (`OOF-PROJ-ENTRY`), deterministic
ordering, and IDE-overlay behavior are **unchanged**.

## v0 semantics (explicit)

- **Cross-package import** resolves via the existing transitive-import closure over the combined index.
- **Duplicate module across packages → `OOF-IMP4`** (the existing diagnostic; reports both source paths).
- **Direct dependencies only:** `app → mid` works; `mid → deep` is *not* pulled into `app`'s index. A module
  reachable only through a dependency's dependency surfaces as a missing import (`OOF-IMP2`), not a silent
  pull. This keeps the package graph **explicit** (no hidden transitive trust) — matching the P1 anti-
  phantom philosophy.
- **No registry / version range / solver / lockfile / install hooks / `.igapp` / capability manifest** —
  all deferred.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests   → 6 passed; 0 failed (resolver-only at P2 close; 12 after P3 lock tests)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests        → 9 passed (P1 path intact)
$ cd lang/igniter-compiler && cargo test --test project_overlay_tests     → 10 passed (overlay intact)
$ cd lang/igniter-compiler && cargo test                                  → full suite green (57 lib + all bins, 0 failed)
$ git diff --check                                                        → clean
```

New resolver tests (6) over new fixtures under `tests/fixtures/project_mode/`:
- `cross_package_import_resolves` — `workspace/app` (entry `App.Main` imports `Lib.Util`) + `workspace/lib`
  (`Lib.Util`): the resolved closure contains **both** files.
- `cross_package_project_compiles_clean` — the combined project **compiles clean through the real multifile
  compiler** (the dependency's `Widget` type links into the app contract; **no error diagnostics**).
- `bare_string_dependency_path_resolves` — shorthand `lib = "../pathlib"` resolves, including quoted paths
  that contain the substring `"path"` (parser regression guard).
- `duplicate_module_across_packages_is_oof_imp4` — app and dependency both declare `App.Main` → `OOF-IMP4`
  with both source paths.
- `direct_dependencies_only` — `workspace_direct`: `app→mid` resolves (`main.ig`+`x.ig`); `mid→deep` is
  **not** pulled (`d.ig` absent).
- `no_dependencies_parity` — the existing `transitive` fixture (no `[dependencies]`) resolves unchanged.

## Acceptance — mapping

- [x] `ProjectConfig` carries `dependencies`; `[dependencies]` parsed (path table + bare string).
- [x] Cross-package `import` resolves through `resolve_entry`.
- [x] Duplicate module across packages → `OOF-IMP4` (reused, not new).
- [x] No-deps projects unchanged (P1 parity; project_mode/overlay tests green).
- [x] Direct-dependencies-only documented + tested.
- [x] `igniter-compiler` full suite green; no server/web/machine change; no new crate dependency.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (config field + `[dependencies]` parser + dep scan in
  `build_module_index`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (new, 6 resolver tests; later P3 extends it).
- `lang/igniter-compiler/tests/fixtures/project_mode/{workspace,workspace_dup,workspace_direct}/…` (new).

## Closed scope (honored)

No registry, network, version solver/ranges, lockfile, install/build hooks, transitive **package** graph,
Cargo-style features, `.igapp` packaging, capability manifest, `igniter-server`/`igniter-web`/
`igniter-machine` change, new crate dependency, or canon claim.

## Next

1. `LAB-IGNITER-PACKAGE-LOCK-PROVENANCE-P3` — a **blake3 per-workspace lockfile** over each dependency's
   deterministic source set (reuse the existing `compile_units` source-hash + the blake3 helper).
2. Later: strict **direct-dep-only import enforcement** (per-package import scoping to reject phantom
   transitive imports), dialect-lowerer/compiler-version lock fields, then — much later — a registry/solver.

---

*Lab implementation-proof. Compiled 2026-06-21; resolver slice in `package_workspace_tests` 6 green (incl. real cross-package
compile), `project_mode`/`project_overlay` intact, full `igniter-compiler` suite green, `git diff --check`
clean. A workspace declares local path dependencies; cross-package imports resolve and cross-package
collisions reuse `OOF-IMP4` — the smallest deterministic resolver, no registry/solver/lock/hooks.*
