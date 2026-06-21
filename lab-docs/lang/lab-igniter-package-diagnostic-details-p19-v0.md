# lab-igniter-package-diagnostic-details-p19-v0 — actionable details for OOF-IMP6/OOF-IMP7

**Card:** `LAB-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19` · **Delegation:** `OPUS-IGNITER-PACKAGE-DIAGNOSTIC-DETAILS-P19`
**Status:** CLOSED (lab implementation-proof) — denied import diagnostics are now machine-actionable. A
generic `details` block is added to `ProjectDiagnostic` and populated for `OOF-IMP6`/`OOF-IMP7` with the
importer/provider package + path, the declared-edge flag, the provider's export surface, the root policy, and
a static **fix** — so agents read fields instead of parsing the English `message`. **`project.rs` + tests —
evidence only (no auto-fix), no new CLI command, no rule/taxonomy change, no new crate.**

## What changed (`project.rs`)

1. **`ProjectDiagnostic.details: Option<Value>`** (+ `new` defaults `None`; `to_value` emits `"details"`
   only when present). This is a **generic** structured-payload escape hatch — *not* package-specific
   top-level fields — so it honors P11's "don't spread package metadata through the generic diagnostic".
2. **`OOF-IMP6`** (scope) populates `details`:
   ```jsonc
   { "kind": "import_scope",
     "importer": { "module": "Lib1.A", "package": "lib1", "path": "../lib1" },
     "provider": { "module": "Lib2.B", "package": "lib2", "path": "../lib2" },
     "declared_edge": false,
     "fix": "declare 'lib2' in the [dependencies] of package 'lib1' (e.g. lib2 = { path = \"../lib2\" })" }
   ```
   The fix path is computed **relative to the importer package** (where the `[dependencies]` entry would go).
3. **`OOF-IMP7`** (exports) populates `details`, distinguishing the two cases:
   ```jsonc
   // allowlist miss
   { "kind": "import_export", "importer": {…}, "provider": { "module": "Lib.Private", "package": "lib", … },
     "declared_edge": true, "exports_default": "open",
     "provider_exports": { "mode": "allowlist", "modules": ["Lib.Public"] },
     "fix": "add 'Lib.Private' to [exports] modules in package 'lib', or import a module that 'lib' already exports" }

   // closed-default seal (root [package] exports = "closed", provider declares no [exports])
   { …, "exports_default": "closed", "provider_exports": { "mode": "open" },
     "fix": "package 'lib' declares no [exports] and the root policy is [package] exports = \"closed\";
             add [exports] modules to 'lib' (exporting 'Lib.A'), or set the root [package] exports = \"open\"" }
   ```

All `details` data was already computed inside `index_integrity` (importer/provider `PackageId`, the graph's
`deps`/`exports`, `exports_default`) — enrichment only stops discarding it. The `fix` is a **static per-rule
template** (no search/ranking/auto-apply) → evidence, not a solver.

## Live behavior (smoke)

- `OOF-IMP6` (`workspace_transitive_root_phantom`): `details.fix` = "declare 'leaf' in the [dependencies] of
  package '<root>' (e.g. leaf = { path = "../leaf" })".
- `OOF-IMP7` allowlist (`workspace_exports_private`): `provider_exports.modules = ["Lib.Public"]`,
  `exports_default = "open"`.
- `OOF-IMP7` seal (`workspace_closed_default`): `exports_default = "closed"`, `provider_exports.mode = "open"`,
  seal-specific fix.
- `OOF-IMP8` cycle (`workspace_transitive_cycle`): **no** `details` key. ✓

## Surfaces automatically

`details` flows through both existing seams via `to_value()`:
- **compile** (`run_project_mode` → diagnostics array),
- **`verify --strict`** (`integrity.diagnostic` — P11 structured path).
No CLI change was needed.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests       → 50 passed (46 + 4 NEW P19)
$ cd lang/igniter-compiler && cargo test --test package_lockfile_cli_tests    → 31 passed (30 + 1 NEW P19)
$ cd lang/igniter-compiler && cargo test                                      → full suite green (0 failed)
$ git diff --check                                                            → clean
```

New P19 tests: API (4) — `oof_imp6_has_import_scope_details`, `oof_imp7_allowlist_has_import_export_details`,
`oof_imp7_closed_seal_details_distinguish_policy`, `non_package_diagnostic_has_no_details` (OOF-IMP8 → none).
CLI (1) — `cli_verify_strict_integrity_carries_details` (details under `integrity.diagnostic`).

## Acceptance — mapping

- [x] `OOF-IMP6` compile diagnostic includes `details.kind = "import_scope"`.
- [x] `OOF-IMP6` details include importer/provider module/package/path and `declared_edge: false`.
- [x] `OOF-IMP6` fix mentions adding `[dependencies]` to the importer package.
- [x] `OOF-IMP7` allowlist miss includes `details.kind = "import_export"` and `provider_exports.modules`.
- [x] `OOF-IMP7` closed-default seal includes `exports_default: "closed"` and a seal-specific fix.
- [x] Details surface through `verify --strict` under `integrity.diagnostic`.
- [x] `OOF-IMP4`/`OOF-IMP8`/`OOF-IMP9` and non-package diagnostics emit no `details`.
- [x] Existing P16/P17/P18 package tests green; full `igniter-compiler` suite green; `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/project.rs` (`ProjectDiagnostic.details` + `to_value`; `details` in the
  OOF-IMP6/OOF-IMP7 branches of `index_integrity`).
- `lang/igniter-compiler/tests/package_workspace_tests.rs` (+4 P19 tests).
- `lang/igniter-compiler/tests/package_lockfile_cli_tests.rs` (+1 P19 CLI test).

## Deferred (explicit)

- `igc package explain-import` (proactive / allowed / hypothetical queries) — separate optional card.
- `OOF-IMP2` (unresolved import) enrichment — no provider in the graph to describe; left to `compile_units`.
- `details` for `OOF-IMP4`/`OOF-IMP8`/`OOF-IMP9` — could be added later; intentionally absent now.

## Next

Optional `LAB-IGNITER-PACKAGE-EXPLAIN-IMPORT-CLI-P20` (only if the enriched diagnostic proves insufficient in
practice), OR the remote/registry wave. The denied-import explanation is now structured and actionable.

---

*Lab implementation-proof. Compiled 2026-06-21; `package_workspace_tests` 50 green, `package_lockfile_cli_tests`
31 green, full `igniter-compiler` suite green, `git diff --check` clean. `OOF-IMP6`/`OOF-IMP7` now carry a
generic `details` block (importer/provider/path/declared_edge/provider_exports/policy/fix); non-package
diagnostics are byte-unchanged.*
