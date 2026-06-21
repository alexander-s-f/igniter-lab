# lab-igniter-package-import-scoping-p7-v0 — strict direct-dependency import scoping

**Card:** `LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7` · **Delegation:** `OPUS-IGNITER-PACKAGE-IMPORT-SCOPING-P7`
**Status:** CLOSED (lab implementation-proof) — the flat workspace index no longer lets any file import any
module. Each file is tagged with its owning **package**, and a **phantom import** (a dependency reaching a
sibling dependency it never declared) is rejected at assembly time as **`OOF-IMP6`**. **`project.rs` + tests
only — no compile/server/web/machine change, no new crate dependency.**

## The risk (why this matters now)

Provenance (P3–P6) answered *what was locked*. The remaining practical risk is *whether a package may import
a module at all*. P2 folds every direct dependency's source roots into ONE flat index, so today **any file
imports any module** present in the workspace. Concretely, with `app → lib1` and `app → lib2` both declared
by the app, all three are folded together — and `lib1` can `import Lib2.B` even though `lib1` never declared
`lib2`. It "works" only because the app happened to fold `lib2` in; reused in a workspace without `lib2`,
`lib1` breaks. That edge is a **phantom import** and must be rejected.

## Scope rule (package-level)

A file owned by package **P** may import a module owned by package **Q** iff:
- **Q == P** — intra-package imports across files are always fine; or
- **P is the workspace root and Q is a directly-declared dependency** of the root.

A dependency may import only its **own** modules: its own `[dependencies]` are not folded in v0 (direct-only,
P2), so nothing else is legitimately in its scope — it must not reach a sibling it never declared, nor the
root application. This is **package-level** scope; module-level visibility/exports are a separate, later
concern (there is no `pub`/export system yet).

## What changed (`project.rs` only)

1. **`PackageId { Root, Dependency(name) }`** + `ScannedFile.package`. `build_module_index` now collects
   files **per package** (root source roots → `Root`; each declared dependency's source roots →
   `Dependency(name)`), dedup by path, and tags each `ScannedFile`.
2. After the OOF-IMP4 duplicate check, a scope pass validates **every resolved import**: for each file, each
   non-stdlib import that **resolves** in the index is checked with `package_in_scope`. The first violation
   (deterministic — sorted) is returned as **`OOF-IMP6`**, naming importer module + package, imported module
   + package, and the importer's source path. **Dangling imports are untouched** — a non-resolving import is
   left to `compile_units` (OOF-IMP2), so scoping never masks a missing-module error.

`OOF-IMP5` is already used (a file without a `module` declaration), so the new code is **`OOF-IMP6`**.

## Live behavior (CLI smoke)

```text
$ igc compile --project-root <ws>/workspace_phantom/app --entry App.Main --out /tmp/x.igapp
  diagnostics: [{
    "rule": "OOF-IMP6",
    "message": "out-of-scope import: module 'Lib1.A' (package lib1) imports 'Lib2.B' (package lib2),
                which it does not declare as a dependency"
  }]
```

## Default-on is safe (no existing fixture breaks)

Every existing workspace fixture imports only in-scope modules (`app → lib`, a declared root→dependency
edge). So enabling scoping by default leaves the P2–P6 resolver/lock/compile tests green; verified.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 23 passed (20 + 3 NEW P7)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests            → 9 passed  (core path intact after restructure)
$ cd lang/igniter-compiler && cargo test --test project_overlay_tests         → 10 passed (overlay intact)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 6 passed
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P7 tests (3) over two new fixtures:
- `phantom_sibling_import_is_oof_imp6` — `workspace_phantom` (`app→lib1,lib2`; `lib1` imports `Lib2.B`) →
  `OOF-IMP6`, importer `Lib1.A`, message names both packages, one source path.
- `intra_package_import_is_allowed` — `workspace_intra` (`Lib.A import Lib.B`, both package `lib`) resolves
  clean (closure = `main.ig` + `a.ig` + `b.ig`).
- `declared_cross_package_import_is_allowed` — the P2 `workspace` (`app` imports `Lib.Util`, lib declared)
  resolves with no scope diagnostic.

## Acceptance — mapping

- [x] `PackageId` tags each scanned file; scope enforced via `package_in_scope`.
- [x] Phantom import (dependency → undeclared sibling) → `OOF-IMP6` with importer/imported + package labels.
- [x] Intra-package and declared root→dependency imports are allowed.
- [x] Dangling imports still surface as `compile_units` OOF-IMP2 (scope checks resolved imports only).
- [x] New rule code `OOF-IMP6` (OOF-IMP5 already taken); deterministic first violation.
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`PackageId`, `ScannedFile.package`, per-package tagging in
  `build_module_index`, scope pass + `package_in_scope`, `OOF-IMP6`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+3 P7 tests).
- `tests/fixtures/project_mode/{workspace_phantom,workspace_intra}/…` (new).

## Deferred (explicit)

- **Module-level visibility / export lists** (`pub` modules) — today a declared dependency exposes ALL its
  modules; restricting which are importable is a separate slice.
- **Transitive package graph** (a dependency declaring its own deps that the root transitively trusts) —
  still out of scope (direct-only, P2).
- Allowing a dependency to import its own declared deps *within* a workspace (would require folding the
  dependency's deps and tracking per-package scope edges) — deferred with the transitive graph.

## Next

`LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8` — `igc lock --frozen` / `igc verify --strict` for CI gating
(fail the build on any drift, including the now-complete content + toolchain + scope guarantees). Registry /
semver remain far later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 23 green, `project_mode` 9 +
`project_overlay` 10 intact, full `igniter-compiler` suite green, `git diff --check` clean. A dependency can
no longer phantom-import a sibling it never declared — package-level import scope, enforced at assembly time
as OOF-IMP6.*
