# lab-igniter-package-module-exports-readiness-p9-v0 — module-level visibility / export boundary

**Card:** `LAB-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9` · **Delegation:** `OPUS-IGNITER-PACKAGE-MODULE-EXPORTS-READINESS-P9`
**Status:** READINESS / DESIGN (v0) — chooses the v0 export model and fully specifies the P10 implementation
card. **No code.** Authority: lab readiness, grounded in live `project.rs` (P2/P7/P8).

---

## 1. Executive summary

A dependency should be able to declare **which of its modules other packages may import**, while
same-package imports stay unrestricted. The recommendation is **manifest-owned exports** in the dependency's
`igniter.toml` (`[exports] modules = [...]`), **exact module paths only**, with **opt-in closure**: a
dependency with **no** `[exports]` block stays fully open (backward-compatible); a dependency that declares
`[exports]` is restricted to exactly that allowlist. Importing an in-scope but non-exported module is a new
diagnostic **`OOF-IMP7`**, layered *after* P7's package-scope `OOF-IMP6`, and enforced in the **shared
`index_integrity`** so the compile path and `igc verify --strict` use one implementation.

**Critical verify-first finding:** the dependency digest does **not** currently cover `igniter.toml`, so an
`[exports]` change would be invisible to the lock. **P10 must fold the dependency manifest into its digest.**

Recommended next card: **`LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10`** (§8).

## 2. Verify-first findings (live `project.rs`)

| Fact | Evidence | Consequence for exports |
|---|---|---|
| Dependency digest hashes **only `.ig` files** under the dep's source roots | `dependency_digest` → `collect_ig_files`; `collect_ig_files` keeps `extension == "ig"` only (`project.rs:702`) | **`igniter.toml` is NOT in the digest** → an `[exports]` change (also `source_roots` / `[dependencies]` changes) does not move the digest → invisible to `verify`/`--frozen`. **P10 must fix this.** |
| `[dependencies]` parser is section-scoped (`in_deps = line == "[dependencies]"`) | `parse_dependencies_toml` | Adding a parallel `parse_exports_toml` (gated on `[exports]`) is additive & safe; an `[exports]` section is silently ignored by today's parsers, so old binaries tolerate new manifests. |
| `parse_source_roots_toml` scans any `source_roots` line (not section-scoped) | `parse_source_roots_toml` | No collision: `[exports]` has no `source_roots` key. |
| Package identity already exists | `PackageId { Root, Dependency(name) }`, `ScannedFile.package`, `package_in_scope`, `index_integrity` (P7/P8) | Export check slots into `index_integrity` right after the scope check; it needs per-dependency export sets keyed by `PackageId::Dependency(name)`. |
| Diagnostics in use: `OOF-IMP1..6` | `rg OOF-IMP[0-9] src` | **`OOF-IMP7` is free** for "import of a non-exported module". |
| `index_integrity` is shared by compile + `verify --strict` (P8) | `check_workspace_integrity` | The export rule auto-applies to both with no second implementation (answers Q7). |
| Overlays are root-owned IDE buffers; no dependency-manifest overlay concept | `ProjectOverlay`, `validate_overlays` | Exports read the dep's on-disk `igniter.toml`; overlays don't touch dep manifests → orthogonal (answers Q9). |

## 3. Decision matrix — where exports live

| Alternative | Pros | Cons | Verdict |
|---|---|---|---|
| **A. `[exports]` in dependency `igniter.toml`** | package surface = package metadata; checked at assembly before typecheck; next to `source_roots`/`[dependencies]`; reuses the hand-rolled parser; no language change | not enforced by the type system; manifest not yet in the digest (fixable, §2) | **SELECTED** |
| B. Inline `.ig` `export module Foo` / `pub module` | co-located with code; type-system-adjacent | changes language semantics (the card's closed scope forbids without explicit rejection); spreads the package boundary across files; harder to audit as one surface | rejected (v0) |
| C. Root-side import allowlist (root says which dep modules it may use) | root controls its own coupling | puts the boundary on the consumer, not the owner — the dependency can't protect its internals; every consumer re-declares | rejected |
| D. Separate package manifest (`package.ig` / `.igpkg`) | clean separation from project config | a second manifest format + loader; premature pre-registry | deferred (revisit with a registry) |
| E. Convention (`*.Public.*` is public) | zero declaration | magic, non-auditable, violates explicit-graph philosophy (P2/P7) | rejected |

## 4. Decision matrix — default behavior (no `[exports]` declared)

| Alternative | Behavior | Breaks existing fixtures? | Verdict |
|---|---|---|---|
| Open-by-default | no decl ⇒ all modules importable | no | partial — but no boundary ever unless opted in |
| Closed-by-default | no decl ⇒ nothing importable | **yes** (every existing dep with no `[exports]`, e.g. `workspace/lib`, breaks) | rejected for v0 (needs a global opt-in / edition first) |
| **Opt-in closure** | no `[exports]` ⇒ fully open; `[exports]` present ⇒ restricted to the allowlist | no | **SELECTED** |
| Strict-only closed | open normally, closed only under `--strict` | no, but splits semantics between modes | rejected (mode-dependent meaning is a footgun) |

**Why opt-in closure:** it matches the established design language of this wave — *absence of a claim = no
restriction* (exactly how P5/P6 treat an unpinned `toolchain` field, and how P7 treats a dependency's own
undeclared deps). A dependency that wants an API boundary declares one; legacy/leaf packages keep working.
Closed-by-default remains the eventual target but belongs to a later card once a `[package] edition`-style
global opt-in exists — named `LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P*`.

## 5. Selected v0 shape

```toml
# dependency igniter.toml
source_roots = ["src"]

[exports]
modules = ["Lib.Public"]      # exact module paths only — no globs/prefixes (auditable)
```

- **Exact paths only** (Q3). Globs/prefixes deferred — they erode auditability of the boundary.
- **Only dependencies declare exports** (Q4). The root application never needs `[exports]`: nothing imports
  the root (P7 already forbids `dependency → root`). A root `[exports]` block is ignored (documented).
- **Same-package imports bypass exports** entirely — `Lib.Public` importing `Lib.Internal` (both package
  `lib`) is fine; exports only gate *cross-package* edges.
- **Empty `[exports] modules = []`** = a deliberately sealed package (exports nothing) — distinct from *no*
  `[exports]` block (open). This gives an explicit "private package" state.

## 6. Diagnostic taxonomy & composition with P7/P8

Layered, coarse→fine, evaluated in `index_integrity` in this order (first violation wins, deterministic):

1. **`OOF-IMP4`** — duplicate module declaration (assembly ambiguity).
2. **`OOF-IMP6`** — out-of-scope **package** edge: may package P even reach package Q? (P7)
3. **`OOF-IMP7`** *(new)* — in-scope package edge, but module M is **not exported** by Q.

So an edge is checked for *package* scope first (OOF-IMP6); only a package-allowed edge is then checked for
*module* export (OOF-IMP7). Same-package and root→declared-dep-but-exported edges pass. Dangling imports
remain `compile_units` `OOF-IMP2` (export checks resolved imports only — same rule as P7).

`OOF-IMP7` message shape (mirrors OOF-IMP6):
`out-of-scope import: module 'App.Main' imports 'Lib.Internal' (package lib), which 'lib' does not export`
with `module_path = importer`, `source_paths = [importer file]`, `node = export:{importer}->{imported}`.

## 7. Lock provenance — the digest gap (Q8, decided)

Today `dependency_digest` hashes only `.ig` files, so **exports changes are invisible to the lock**. P10
**must fold each dependency's `igniter.toml` into its digest** (hash the manifest content under a stable
relative key, e.g. `"igniter.toml"`, alongside the sorted `.ig` files). Benefits:
- exports changes move the digest → `verify` / `lock --frozen` / provenance cover exports **for free**, no
  separate lock field;
- also closes a **latent gap**: today a dependency changing its own `source_roots` / `[dependencies]`
  escapes the digest too.

**Migration note for P10:** this changes existing dependency digests. The P3/P5/P6 tests compare digests
**dynamically** (determinism / content-addressing / drift), not against hard-coded hex, so folding the
manifest is safe — but P10 must re-run and confirm `package_workspace_tests` + `package_lockfile_cli_tests`
stay green, and update any doc that quotes a literal digest.

## 8. Strict-mode behavior (Q7, decided)

No new gate. The export check lives in the shared **`index_integrity`**, so it is enforced identically by:
- `igc compile --project-root …` (assembly fault → diagnostic), and
- `igc verify --strict` (via `check_workspace_integrity` → `integrity` block, `rule: OOF-IMP7`).

Like OOF-IMP6, exports are an **assembly invariant** (always enforced), not a strict-only extra; `--strict`
simply surfaces assembly faults in the verify JSON. Plain `verify` stays drift-only.

## 9. All card questions — explicit answers

1. **Where:** dependency `igniter.toml [exports]` (Alt A).
2. **Default:** **opt-in closure** — no block = open; block = allowlist; `modules = []` = sealed.
3. **Pattern:** exact module paths only (no globs).
4. **Root exports?** No — only dependencies; a root `[exports]` is ignored.
5. **Diagnostic:** `OOF-IMP7` (OOF-IMP6 is package-scope/phantom).
6. **Compose with P7:** OOF-IMP6 (package edge) first, then OOF-IMP7 (module export); same-package bypasses.
7. **`verify --strict`:** shared `index_integrity`; one implementation; always-on like OOF-IMP6.
8. **Lock provenance:** fold the dependency `igniter.toml` into its digest (covers exports + a latent
   source_roots/deps gap); no separate lock field.
9. **Overlays:** orthogonal — overlays are root buffers; dependency-manifest overlays are out of scope.
10. **Min fixture:** `workspace_exports` (§10).

## 10. Exact P10 acceptance tests (write P10 from this without rediscovery)

New fixture `tests/fixtures/project_mode/workspace_exports/`:
```
app/igniter.toml         source_roots=["src"]; [dependencies] lib = { path = "../lib" }
app/src/main.ig          module App.Main; import Lib.Public        (positive)
lib/igniter.toml         source_roots=["src"]; [exports] modules = ["Lib.Public"]
lib/src/public.ig        module Lib.Public; import Lib.Internal     (intra-package, allowed)
lib/src/internal.ig      module Lib.Internal
```
Plus `workspace_exports_violation/` where `app/src/main.ig` does `import Lib.Internal` (non-exported).

P10 tests:
1. `exported_module_import_is_allowed` — resolve `workspace_exports/app` → Ok (closure has main/public/internal).
2. `non_exported_module_import_is_oof_imp7` — resolve `workspace_exports_violation/app` → `OOF-IMP7`,
   importer `App.Main`, message names `Lib.Internal` + package `lib`, one source path.
3. `intra_package_import_ignores_exports` — `Lib.Public import Lib.Internal` (same package `lib`) → no
   OOF-IMP7 (proven by test 1 resolving clean).
4. `no_exports_block_is_open` — existing `workspace` (lib has no `[exports]`) still resolves (open default;
   P2–P8 tests unchanged).
5. `empty_exports_seals_package` — a `lib` with `[exports] modules = []` → any cross-package import of its
   modules → `OOF-IMP7`.
6. `check_workspace_integrity_flags_non_export` — entry-free integrity returns `OOF-IMP7` for the violation
   fixture (so `verify --strict` catches it).
7. `dependency_digest_covers_manifest` — changing `lib/igniter.toml` (`[exports]`) changes the dependency
   digest (proves §7 fold); and `verify` reports `Changed` drift after an exports edit.
8. CLI: `cli_verify_strict_catches_non_export` — `verify --strict` on the violation fixture → exit 1,
   `integrity.diagnostic.rule == "OOF-IMP7"`; plain `verify` (post-fold) reports drift only if the manifest
   changed.
9. Full `igniter-compiler` suite green; `git diff --check` clean.

## 11. Closed scope (honored)

No registry/semver/solver/transitive graph; no `.ig` `pub`/`export` keyword (manifest chosen); no source-map/
typechecker/VM/web/server work; no new crate; **no code in P9**; P10 not implemented here.

---

*Lab readiness packet. Grounded in live `project.rs` (digest scope, toml parsers, `index_integrity`,
diagnostics). Selected v0: manifest `[exports]`, exact paths, opt-in closure, `OOF-IMP7` layered after
`OOF-IMP6`, enforced in shared integrity, with the dependency manifest folded into its digest so the lock
covers exports. P10 acceptance tests fully enumerated.*
