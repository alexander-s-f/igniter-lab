# LAB-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9 — module-level visibility / export boundary

Status: CLOSED
Lane: standard / lab readiness
Type: design-readiness
Delegation code: OPUS-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

P2 introduced local path dependencies by folding direct dependency source roots into one project module
index. P7 added **package-level import scoping** (`OOF-IMP6`): a dependency can no longer phantom-import a
sibling dependency it never declared. P8 made the resulting trust model CI-enforceable with
`lock --frozen` and `verify --strict`.

The next package-manager pressure is **module-level visibility**: once a root package declares dependency
`lib`, it can currently import **any** module inside `lib`. That is too broad for a package boundary. We need
an export surface: a dependency should explicitly declare which modules are importable by other packages,
while keeping same-package imports unrestricted.

## Goal

Produce a readiness packet that chooses the v0 export model and prepares an implementation card. Treat this
as architecture-boundary work, not syntax bikeshedding.

## Verify first

- `lang/igniter-compiler/src/project.rs`
  - `ProjectConfig::load` / hand-rolled `igniter.toml` parser.
  - `Dependency`, `PackageId`, `ScannedFile`, `package_in_scope`, `index_integrity`.
  - Existing diagnostics: `OOF-IMP2`, `OOF-IMP4`, `OOF-IMP5`, `OOF-IMP6`.
- `lang/igniter-compiler/tests/package_workspace_tests.rs`.
- Fixtures under `tests/fixtures/project_mode/workspace*`.
- P2/P7/P8 docs/cards for direct-dep scope and strict CI.

## Questions to answer

1. Where should exports live in v0?
   - dependency `igniter.toml` (`[exports] modules = [...]`)
   - root `igniter.toml` import allowlist
   - inline `.ig` syntax (`export module Foo`)
   - future package manifest separate from project config
2. Default behavior: if a dependency has no export declaration, is it open, closed, or compatibility-open
   only outside `--strict`?
3. Should exports be exact module paths only, or prefix/glob patterns too?
4. Should the root application need exports? Or only dependencies consumed by other packages?
5. What diagnostic code should be used for importing a non-exported module? (`OOF-IMP7` likely, because
   `OOF-IMP6` is package-scope / phantom import.)
6. How does this compose with P7?
   - out-of-scope package edge => `OOF-IMP6`
   - in-scope package edge but non-exported module => `OOF-IMP7`
7. How should `igc verify --strict` behave? It already calls shared integrity; export checks should share
   the same path, not become a second implementation.
8. Does lock provenance need to include exports separately? Or does dependency digest already cover
   `igniter.toml` / export changes? Verify live digest behavior.
9. How should overlays interact with exports? Root overlays are root-owned; dependency overlays are not
   currently a concept.
10. What is the minimum app-pressure fixture that proves the design?

## Bias / initial hypothesis

Prefer **manifest-owned exports** in the dependency `igniter.toml`, not inline language syntax:

```toml
source_roots = ["src"]

[exports]
modules = ["Lib.Public"]
```

Rationale: package surface is package metadata, not language semantics; it is checked at project assembly,
before typechecking, next to dependencies/source roots. v0 should use **exact module paths only** (no globs)
to keep the boundary auditable.

Open question to decide carefully: **default closed vs compatibility-open**. Since Igniter is pre-v1 and the
package model is lab, closed-by-default may be the cleaner target. But it will require updating existing
package fixtures. If the packet chooses compatibility-open, it must explain how/when closed mode becomes the
default.

## Closed scope

- No registry, semver, solver, transitive package graph.
- No module-level `pub` keyword in `.ig` unless the readiness packet explicitly rejects manifest exports.
- No source-map/typechecker/VM/web/server work.
- No new crate.
- Do not implement P10 in this card.

## Required deliverable

`lab-docs/lang/lab-igniter-package-module-exports-readiness-p9-v0.md`

It must include:
- verify-first findings from live `project.rs`;
- decision matrix (at least 4 alternatives);
- selected v0 shape;
- diagnostic taxonomy (`OOF-IMP6` vs proposed `OOF-IMP7`);
- strict-mode behavior;
- exact P10 acceptance tests.

## Required acceptance

- [x] All questions answered explicitly.
- [x] Default export behavior chosen and justified.
- [x] Export declaration syntax chosen and bounded.
- [x] Composition with P7/P8 specified.
- [x] P10 implementation card can be written from the packet without rediscovery.
- [x] No code changes.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Deliverable:** `lab-docs/lang/lab-igniter-package-module-exports-readiness-p9-v0.md` — readiness packet,
no code (`git diff --check` clean).

**Verify-first findings (live `project.rs`):** (1) **critical** — `dependency_digest` hashes only `.ig`
files (`collect_ig_files` keeps `extension=="ig"`), so `igniter.toml`/`[exports]` is **not** in the digest →
an exports change is invisible to the lock today (also a latent gap for `source_roots`/`[dependencies]`
changes). (2) `[dependencies]` parser is section-scoped → a parallel `[exports]` parser is additive/safe;
old binaries ignore the new section. (3) `OOF-IMP1..6` in use → **`OOF-IMP7` free**. (4) `index_integrity`
already shared by compile + `verify --strict` (P8) → export check needs no second implementation.

**Decisions:** manifest-owned `[exports] modules = [...]` in the dependency `igniter.toml` (Alt A over inline
`pub`, root allowlist, separate manifest, convention); **exact paths only**; **opt-in closure** (no block =
open; block = allowlist; `modules=[]` = sealed) — matches the wave's "absence = no claim" language and breaks
no fixtures; only dependencies declare exports (root never imported, per P7); **`OOF-IMP7`** layered after
`OOF-IMP6` (package edge → module export), same-package bypasses; enforced in shared `index_integrity`
(compile + `--strict`); **P10 must fold the dependency `igniter.toml` into its digest** so the lock covers
exports (no separate lock field). Overlays orthogonal.

**P10 enumerated:** `workspace_exports` + `workspace_exports_violation` fixtures + 9 acceptance tests
(exported-ok, non-exported→OOF-IMP7, intra-package-ignores-exports, no-block-open, empty-seals,
integrity-flags, digest-covers-manifest, CLI strict catches, suite green). **Next:**
`LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10` (implement); later `…-EXPORTS-CLOSED-DEFAULT-P*` (global opt-in).

