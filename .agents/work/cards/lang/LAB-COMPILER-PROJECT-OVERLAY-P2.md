# Card: LAB-COMPILER-PROJECT-OVERLAY-P2

**Title:** IDE overlay support for project-root compile mode
**Skill:** idd-agent-protocol
**Lane:** standard / compiler DX foundation
**Status:** ✅ CLOSED — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Builds on:** LAB-COMPILER-PROJECT-MODE-COMPILE-P1
**Proof:** `lab-docs/lang/lab-compiler-project-overlay-p2-v0.md`

---

## Card Statement

Add a minimal overlay mechanism to project mode so an IDE can compile the current
unsaved editor buffer while resolving imports from the project graph:

```
igniter_compiler compile --project-root ROOT --entry Module.Path \
  --overlay <project-source-path>=<overlay-source-path> --out OUT.igapp
```

During scanning + compilation, the overlay buffer is read in place of the on-disk file.

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` (P1 `project.rs` + `compile_units`).
- **Evidence only:** this card, the proof doc, test output.
- **Authorized to change:** `igniter-compiler` CLI + `project.rs`; add tests/fixtures.
- **Closed surfaces:** language import semantics, `OOF-IMP*`/`OOF-P1` behavior, JetBrains
  plugin, package/dependency management.

## What landed

- `src/project.rs` — `ProjectOverlay { original_path, overlay_path }` (public);
  `resolve_entry_with_overlays(root, entry, &[ProjectOverlay])`; `resolve_entry` now
  delegates with an empty slice (P1 unchanged). `validate_overlays` (deterministic,
  sorted) with refusals `OOF-PROJ-OVERLAY-OUTSIDE` / `OOF-PROJ-OVERLAY-MISSING`;
  `normalize_abs` lexical path helper; `build_module_index` substitutes buffer content
  for matched files and injects overlay-only (new unsaved) files; `ProjectDiagnostic`
  gains `original_path` / `overlay_path`.
- `src/main.rs` — parse repeated `--overlay a=b`; call `resolve_entry_with_overlays`;
  diagnostics render via the existing P1 `emit_project_diagnostic` (no panics).
- `tests/project_overlay_tests.rs` — 10 tests; fixtures under
  `tests/fixtures/project_overlay/` (`base/` disk project + `buffers/` editor buffers).

## Source-path evidence (honest)

The buffer path flows to `compile_units`, so overlaid units carry the **overlay (buffer)
path** in `source_units`; non-overlaid units keep disk paths. Aliasing the buffer back to
the original project path is deferred polish (does not affect resolution/diagnostics).

## Acceptance — all 10 met

1. No overlay → P1 unchanged ✅
2. Overlay content wins for mapped file ✅
3. Overlay adds import → closure includes new module (`Over.Extra`) ✅
4. Overlay removes import → stale disk import dropped (`Over.Types`) ✅
5. Overlay body change → diagnostics reflect overlay (`OOF-P1`) ✅
6. Missing overlay file → `OOF-PROJ-OVERLAY-MISSING`, no panic ✅
7. Original outside source roots → `OOF-PROJ-OVERLAY-OUTSIDE` ✅
8. Multiple overlays deterministic (identical source_hash on repeat) ✅
9. Duplicate module from overlay content → `OOF-IMP4`, both paths ✅
10. Tests include exact CLI + pass count ✅

Bonus: `overlay_injects_new_unsaved_file` covers new-file injection.

## Verification

```
cd igniter-compiler
cargo test --test project_overlay_tests --quiet   # 10 passed; 0 failed
cargo test --test project_mode_tests   --quiet    #  9 passed; 0 failed  (P1 rerun, intact)
cargo test --no-fail-fast --quiet
#   effect_name_parity_tests: 4 passed
#   loop_conformance_tests:  10 passed; 4 failed   (PRE-EXISTING; unrelated — see P1 proof)
#   project_mode_tests:       9 passed
#   project_overlay_tests:   10 passed
```

## Next / deferred

- **JetBrains follow-up (separate card):** plugin calls project mode + `--overlay
  <currentFile>=<tempBuffer>` instead of owning the import graph; delete plugin-side
  scanner; map the active editor document to a temp buffer file. This closes P1's
  unsaved-buffer seam.
- Deferred: source-path alias (report original path), same-original overlay policy,
  stdin/in-memory buffers, and all P1 deferrals.
