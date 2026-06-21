# lab-igniter-package-module-exports-p10-v0 — enforce dependency module exports

**Card:** `LAB-IGNITER-PACKAGE-MODULE-EXPORTS-P10` · **Delegation:** `OPUS-IGNITER-PACKAGE-MODULE-EXPORTS-P10`
**Status:** CLOSED (lab implementation-proof) — a dependency can now declare its **export surface**
(`[exports] modules` in `igniter.toml`); the root may import only **exported** dependency modules. An
in-scope but non-exported import is **`OOF-IMP7`**, layered after P7's package-scope `OOF-IMP6`, enforced in
the shared `index_integrity` (compile path + `verify --strict`). **`project.rs` + tests only — implements the
P9 packet; no `.ig` syntax, no registry/solver, no server/web/machine change, no new crate.**

## Final shape (from P9, confirmed)

```toml
# dependency igniter.toml
source_roots = ["src"]

[exports]
modules = ["Lib.Public"]      # exact module paths only — no globs
```

- **Opt-in closure** (default behavior): **no `[exports]` block ⇒ open** (every module importable,
  backward-compatible); `[exports]` present ⇒ cross-package imports restricted to the allowlist;
  `modules = []` (or `[exports]` with no `modules` key) ⇒ a **sealed** package.
- **Only dependencies** are export-gated. Same-package imports are unrestricted; a root's own modules are
  never gated; a root `[exports]` block is ignored (nothing imports the root — P7).

## Diagnostic taxonomy & composition (P7 → P10)

`index_integrity` runs three checks, coarse→fine, first violation wins (deterministic):

1. **`OOF-IMP4`** — duplicate module declaration.
2. **`OOF-IMP6`** — out-of-scope **package** edge (P7 phantom: may package P reach package Q?).
3. **`OOF-IMP7`** *(new)* — in-scope **package** edge, but the target **module** is not exported by Q.

Only **root → dependency** edges reach the OOF-IMP7 check: dependency→sibling/root already fell to OOF-IMP6,
same-package bypasses, root→root is never gated. Dangling imports remain `compile_units` `OOF-IMP2`.

OOF-IMP7 message:
`non-exported import: module 'App.Main' imports 'Lib.Private' (package lib), which package 'lib' does not export`
(`module_path` = importer, `source_paths` = [importer file], `node` = `export:App.Main->Lib.Private`).

## What changed (`project.rs` only)

1. `ProjectConfig` += `exports: Option<Vec<String>>`; `parse_exports_toml` (section-scoped, hand-rolled,
   mirrors `parse_dependencies_toml`): `None` if no `[exports]`, `Some(list)` if present (empty = sealed).
2. `ModuleIndex` += `dep_exports: BTreeMap<String, Option<BTreeSet<String>>>` (dependency name → export set),
   populated in `build_module_index` from each dependency's own `ProjectConfig`.
3. `index_integrity` gains the OOF-IMP7 pass after OOF-IMP6 — shared by the compile path and
   `verify --strict` (one implementation, P8).
4. **`dependency_digest` folds in the dependency's `igniter.toml`** (P9 §7): the manifest is hashed alongside
   the sorted `.ig` files, so an `[exports]` change (also `source_roots`/`[dependencies]`) moves the digest.

## Lock digest covers exports (the P9 §7 gap, closed)

Before P10 the digest hashed only `.ig` files, so an exports change was invisible to `verify`/`--frozen`.
Now the dependency's `igniter.toml` is part of its digest → an exports edit is a **`changed` drift**. This
also closes the latent gap where a dependency's own `source_roots`/`[dependencies]` changes escaped the
digest. No separate lock field; provenance covers exports for free. Determinism is preserved (manifest
participates in the same sorted (rel-path + content) hash).

## Live behavior (smoke)

```text
$ igc compile --project-root <ws>/workspace_exports_private/app --entry App.Main --out /tmp/x.igapp
  diagnostics: [{ "rule": "OOF-IMP7",
    "message": "non-exported import: module 'App.Main' imports 'Lib.Private' (package lib),
                which package 'lib' does not export" }]

$ igc verify --project-root <ws>/workspace_exports_private/app --strict
  { "ok": false, "drift": [],
    "integrity": { "ok": false, "diagnostic": { "rule": "OOF-IMP7", … } } }          # exit 1
# plain `igc verify` (drift-only) → exit 0
```

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 30 passed (25 + 5 NEW P10)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 13 passed (11 + 2 NEW P10)
$ cd lang/igniter-compiler && cargo test --test project_mode_tests            → 9 passed (digest fold + integrity intact)
$ cd lang/igniter-compiler && cargo test --test project_overlay_tests         → 10 passed
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P10 tests (7) over two new fixtures (`workspace_exports_ok`, `workspace_exports_private`):
- API: `exported_module_import_is_allowed` (+ intra-package private import allowed), `non_exported_module_import_is_oof_imp7`,
  `no_exports_block_is_open`, `phantom_sibling_still_oof_imp6_after_exports` (not reclassified),
  `check_workspace_integrity_flags_non_export`.
- CLI: `cli_verify_strict_catches_non_export` (plain verify passes, strict fails OOF-IMP7),
  `cli_export_change_is_lock_drift` (edit `lib/igniter.toml` exports → `verify` reports `changed` drift —
  proves the manifest fold).

## Acceptance — mapping

- [x] Exports parsed from dependency metadata (`[exports] modules`, opt-in closure).
- [x] Root cannot import a non-exported dependency module (`OOF-IMP7`).
- [x] Same-package imports remain unrestricted (intra-package private import proven).
- [x] Phantom package edge remains `OOF-IMP6` (not reclassified).
- [x] Non-exported module edge is deterministic `OOF-IMP7`.
- [x] Compile path and `verify --strict` share one integrity implementation (`index_integrity`).
- [x] Full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`ProjectConfig.exports` + `parse_exports_toml`;
  `ModuleIndex.dep_exports`; OOF-IMP7 in `index_integrity`; manifest fold in `dependency_digest`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+5 P10 tests).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+2 P10 CLI tests).
- `tests/fixtures/project_mode/{workspace_exports_ok,workspace_exports_private}/…` (new).

## Deferred (explicit)

- **Closed-by-default** exports (global opt-in via a future `[package] edition`) —
  `LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P*`.
- Glob/prefix export patterns; module-level `pub`/`export` in `.ig` (manifest chosen); transitive package
  graph; registry/semver/solver.

## Next

`LAB-IGNITER-PACKAGE-EXPORTS-CLOSED-DEFAULT-P*` (opt-in to closed-by-default) OR the transitive package graph
— per the user's sequencing. Registry/semver remain far later.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 30 green, `package_lockfile_cli_tests`
13 green, `project_mode` 9 + `project_overlay` 10 intact, full `igniter-compiler` suite green, `git diff
--check` clean. A dependency now controls its importable surface (`[exports]`, opt-in closure, OOF-IMP7), and
the lock digest covers the export metadata via the folded manifest.*
