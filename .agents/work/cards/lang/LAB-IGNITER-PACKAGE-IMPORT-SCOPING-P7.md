# LAB-IGNITER-PACKAGE-IMPORT-SCOPING-P7 — strict direct-dependency import scoping

Status: CLOSED
Lane: standard / lab implementation
Type: implementation-proof
Delegation code: OPUS-IGNITER-PACKAGE-IMPORT-SCOPING-P7
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P2 folds each direct dependency's source roots into ONE flat module index, so today **any file can import any
module** present in the workspace. With provenance complete (P3–P6 lock content + compiler + stdlib), the next
practical risk is not *what was locked* but *whether a package is allowed to import a module at all*. This
card enforces **package-level import scope**: reject **phantom imports** — a dependency reaching a sibling
dependency (or the root app) that it never declared, present only because the root happened to fold it in.

## The phantom case

Workspace: `app → lib1`, `app → lib2` (both declared by app). All three are folded into one index. If
`lib1` does `import Lib2.B`, it resolves today — but `lib1` never declared `lib2`. Reused in another
workspace without `lib2`, `lib1` breaks. That edge must be rejected at assembly time.

## Scope rule (package-level; no module visibility/export system yet)

A file owned by package P may import a module owned by package Q iff:
- **Q == P** (same package — intra-package imports across files are always fine), or
- **P is the workspace root and Q is a directly-declared dependency of the root**.

A dependency may import only its **own** modules (its own `[dependencies]` are not folded in v0, so nothing
else is legitimately in its scope; it must not reach a sibling it never declared, nor the root app).

## Verify-first

- `src/project.rs` — `build_module_index` (flat index, no package tag), `resolve_entry_with_overlays`
  (OOF-IMP4 duplicate path), `ScannedFile`, `scan_file`.
- **`OOF-IMP5` is already used** (file without a `module` decl, `build_module_index` comment) → use a NEW
  code **`OOF-IMP6`** for out-of-scope imports.
- Existing fixtures have no phantom imports (`app→lib` is in scope), so default-on scoping breaks nothing.

## Required implementation (`project.rs` only)

1. `PackageId { Root, Dependency(name) }`; `ScannedFile` gains `package`. `build_module_index` tags each file
   by the package it was scanned from (root vs dependency name); dedup by path.
2. After the OOF-IMP4 check, validate every RESOLVED import against `package_in_scope`; the first violation
   (deterministic) → `OOF-IMP6` diagnostic naming importer module/package + imported module/package +
   importer source path. Dangling imports are left to `compile_units` (OOF-IMP2).

## Required tests (new fixtures)

1. **phantom rejected** — `workspace_phantom` (`app→lib1,lib2`; `lib1` imports `Lib2.B`) → `OOF-IMP6`.
2. **intra-package allowed** — `workspace_intra` (`lib` has `Lib.A import Lib.B`, both package `lib`) →
   resolves clean (no OOF-IMP6).
3. **declared cross-package still allowed** — `workspace` (`app→lib`, app imports `Lib.Util`) → no OOF-IMP6
   (existing resolver/compile tests stay green).
4. P2–P6 tests + full `igniter-compiler` suite stay green.

## Required acceptance

- [x] `PackageId` tags each scanned file; scope enforced via `package_in_scope`.
- [x] Phantom import (dependency → undeclared sibling) → `OOF-IMP6` with importer/imported + package labels.
- [x] Intra-package and declared root→dependency imports are allowed.
- [x] Dangling imports still surface as `compile_units` OOF-IMP2 (scope checks resolved imports only).
- [x] New rule code `OOF-IMP6` (OOF-IMP5 already taken); deterministic first violation.
- [x] Full `igniter-compiler` suite green; no compile/server/web/machine change; no new crate.
- [x] `git diff --check` clean.

## Required proof doc

`lab-docs/lang/lab-igniter-package-import-scoping-p7-v0.md` — the phantom risk, the package-level scope rule,
why OOF-IMP6 (OOF-IMP5 taken), fixtures, tests/counts, deferred (module-level export/visibility, transitive
graph), next card (`…-LOCKFILE-FROZEN-CI-P8`).

---

## Closing Report (2026-06-21)

**Implementation (`project.rs` + tests):** `PackageId{Root, Dependency(name)}` + `ScannedFile.package`;
`build_module_index` collects files **per package** (root vs dependency-name) and tags each; after OOF-IMP4,
a scope pass validates every **resolved** import via `package_in_scope` and returns the first (deterministic)
violation as **`OOF-IMP6`** (OOF-IMP5 was already taken). Dangling imports stay with `compile_units`
(OOF-IMP2). Proof doc: `lab-docs/lang/lab-igniter-package-import-scoping-p7-v0.md`.

**Scope rule:** same-package always allowed; root→declared-dependency allowed; a dependency may import only
its own modules (its deps aren't folded). Phantom (dependency→undeclared sibling, or →root app) rejected.

**Live smoke:** `igc compile --project-root workspace_phantom/app` → `OOF-IMP6: out-of-scope import: module
'Lib1.A' (package lib1) imports 'Lib2.B' (package lib2), which it does not declare as a dependency`.

**Proof — all green:** `package_workspace_tests` **23** (20 + 3 P7: phantom→OOF-IMP6, intra allowed, declared
allowed), `project_mode` 9 + `project_overlay` 10 intact after the core-path restructure, `package_lockfile_cli_tests`
6, full `igniter-compiler` suite green (0 failed), `git diff --check` clean. Default-on safe (no existing
fixture has a phantom import). No compile/server/web/machine change; no new crate.

**Deferred:** module-level visibility/export lists (a declared dep exposes ALL its modules today); transitive
package graph; allowing a dependency to import its own declared deps within a workspace. **Next:**
`LAB-IGNITER-PACKAGE-LOCKFILE-FROZEN-CI-P8` (`--frozen`/`--strict` CI gating over content + toolchain + scope).
