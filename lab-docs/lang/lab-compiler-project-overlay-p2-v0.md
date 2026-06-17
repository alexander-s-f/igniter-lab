# lab-compiler-project-overlay-p2-v0

Proof doc for card `LAB-COMPILER-PROJECT-OVERLAY-P2` — add an IDE **overlay**
mechanism to P1 project mode so the compiler can resolve imports from the project
graph while compiling the current **unsaved editor buffer** in place of the on-disk
file.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler
is authority, not this card). **Lane:** standard / compiler DX foundation.
**Builds on:** `LAB-COMPILER-PROJECT-MODE-COMPILE-P1`.

> Compiler/CLI only. No language import-semantics change; no JetBrains integration;
> no package/dependency management. The P1 surface is unchanged when no overlay is
> passed.

## Exact overlay CLI shape

```
igniter_compiler compile \
  --project-root <ROOT> \
  --entry <Module.Path> \
  --overlay <PROJECT_SOURCE_PATH>=<OVERLAY_BUFFER_PATH> \
  [--overlay ... ]* \
  --out <OUT.igapp>
```

- `--overlay` is repeatable; each maps one project source file to a buffer file.
- `<PROJECT_SOURCE_PATH>` is the file being edited (must be inside a source root).
- `<OVERLAY_BUFFER_PATH>` is the temporary editor-buffer file; it may live anywhere.
- With **zero** `--overlay` flags, behavior is byte-for-byte P1 (`resolve_entry`
  delegates to `resolve_entry_with_overlays(.., &[])`).

## How source-path evidence is represented (honest answer)

The overlay buffer path is what flows to `multifile::compile_units`. Therefore, in
`source_units`, an **overlaid unit carries the overlay (buffer) path** as its
`source_path`, while non-overlaid units keep their disk paths. Example (acceptance 2):

```
source_units = [
  ("Over.Extra", ".../base/extra.ig"),                  # disk
  ("Over.Main",  ".../buffers/main_add_extra.ig"),      # overlay buffer — content won
  ("Over.Types", ".../base/types.ig"),                  # disk
]
```

This is intentional and documented per the card: P2 does not yet alias the buffer
path back to the original project path. A richer source-path alias (report the
original path while reading buffer bytes) is left as later polish — it does not change
resolution or diagnostics, only evidence cosmetics.

## Implementation (in `igniter-compiler`)

- `src/project.rs`
  - `ProjectOverlay { original_path, overlay_path }` (public).
  - `resolve_entry_with_overlays(root, entry, &[ProjectOverlay])` — new public entry;
    `resolve_entry` now delegates with an empty slice.
  - `validate_overlays` — deterministic (sorted by original). Two refusals:
    - `OOF-PROJ-OVERLAY-OUTSIDE` — original not inside any configured source root.
    - `OOF-PROJ-OVERLAY-MISSING` — buffer file unreadable.
  - `normalize_abs` — lexical absolutize + collapse `.`/`..` (no filesystem touch, so
    it works for not-yet-saved originals); used only for overlay matching/containment.
  - `build_module_index` now takes resolved overlays: when scanning a file whose
    normalized path matches an overlay original, it reads the **buffer** instead of disk
    and uses the buffer path as the effective source path. Overlay originals not present
    on disk are **injected** as new source units (the IDE "new unsaved file" case).
  - `ProjectDiagnostic` gains optional `original_path` / `overlay_path` fields.
- `src/main.rs` — parse repeated `--overlay a=b` (split on first `=`); call
  `resolve_entry_with_overlays`. Project-resolution diagnostics render through the same
  `emit_project_diagnostic` path as P1 (no panics).

All import validation (`OOF-IMP*`, duplicate type/contract, cycles) is still inherited
from `compile_units` — overlays only change which bytes that pipeline sees.

## Acceptance matrix — all 10 met

| # | Requirement | Result |
|---|-------------|--------|
| 1 | No overlay → P1 unchanged | ✅ `no_overlay_matches_p1`: `resolve_entry == resolve_entry_with_overlays(.., &[])`; disk paths only |
| 2 | Overlay content wins for mapped file | ✅ `overlay_content_wins`: `Over.Main` source_path = buffer path |
| 3 | Overlay adds import → closure includes new module | ✅ `overlay_adds_import_extends_closure`: closure gains `Over.Extra` |
| 4 | Overlay removes import → stale disk import dropped | ✅ `overlay_removes_import_shrinks_closure`: `Over.Types` not in closure |
| 5 | Overlay body change → diagnostics reflect overlay | ✅ `overlay_body_change_reflected_in_diagnostics`: `OOF-P1` from buffer text |
| 6 | Missing overlay file → deterministic diagnostic, no panic | ✅ `missing_overlay_file_is_diagnostic`: `OOF-PROJ-OVERLAY-MISSING` |
| 7 | Original outside source roots refused | ✅ `overlay_original_outside_roots_refused`: `OOF-PROJ-OVERLAY-OUTSIDE` |
| 8 | Multiple overlays deterministic | ✅ `multiple_overlays_are_deterministic`: identical `source_hash` + `source_units` on repeat |
| 9 | Duplicate module from overlay content detected | ✅ `duplicate_module_from_overlay_detected`: `OOF-IMP4`, both paths |
| 10 | Tests include exact CLI + pass count | ✅ this doc + `project_overlay_tests.rs` (10 passed) |

Bonus (exercises injection code): `overlay_injects_new_unsaved_file` — an entry file
not on disk, supplied entirely by overlay, resolves and compiles.

## New diagnostics (lab-only, project-assembly layer)

- `OOF-PROJ-OVERLAY-OUTSIDE` — overlay original path not inside any source root.
- `OOF-PROJ-OVERLAY-MISSING` — overlay buffer file unreadable.

Both are distinct from the language `OOF-IMP*` family and carry no canon impact.

## Which P1 tests were rerun

`igniter-compiler/tests/project_mode_tests.rs` — all **9 passed** after the P2 changes
(regression check; P1 surface intact).

## Proof commands & exact results

```
cd igniter-compiler
cargo test --test project_overlay_tests --quiet   # 10 passed; 0 failed
cargo test --test project_mode_tests   --quiet   #  9 passed; 0 failed  (P1 regression)
cargo test --no-fail-fast --quiet
#   effect_name_parity_tests: 4 passed
#   loop_conformance_tests:  10 passed / 4 failed   (PRE-EXISTING; see P1 proof doc)
#   project_mode_tests:       9 passed
#   project_overlay_tests:   10 passed
```

The 4 `loop_conformance_tests` failures are the same pre-existing SemanticIR `loop_node`
assertions documented in `lab-compiler-project-mode-compile-p1-v0.md` (proven unrelated
by git stash). P2 touches none of that path.

Fixtures (committed under `igniter-compiler/tests/fixtures/project_overlay/`):
`base/` (disk project: `types.ig`, `main.ig` importing Types, `extra.ig`) and `buffers/`
(editor buffers: `main_add_extra.ig`, `main_no_import.ig`, `main_bad_field.ig`,
`main_as_types_dup.ig`, `extra_variant.ig`, `new_module.ig`).

## Authority boundary

igniter-lab only. No canon language change, no production impact. Import semantics
untouched; `stdlib.*` still inventory-resolved and forbidden in user files. The live
compiler remains authority; this doc is evidence.

## What remains for JetBrains

The plugin can now call project mode **with** overlay instead of owning an import graph
and instead of losing the unsaved buffer:

```
igniter_compiler compile --project-root <projectRoot> --entry <currentModule> \
  --overlay <currentFileOnDisk>=<tempBufferWithEditorText> --out <temp.igapp>
```

This closes the unsaved-buffer seam flagged in P1's closing report. Remaining plugin
work (separate card): map the active editor document to a temp buffer file, pass the
overlay, and delete the plugin-side scanner now that the compiler owns assembly.

## Intentionally deferred

- Source-path alias: report the original project path in `source_units` while reading
  buffer bytes (P2 honestly reports the buffer path).
- Multiple overlays for the *same* original (last-wins / refusal policy) — not exercised;
  current behavior applies the first match deterministically after sort.
- stdin/in-memory buffers (P2 takes a buffer file path; an IDE writes a temp file).
- Everything deferred by P1 (richer `igniter.toml`, Makefile wrapper, qualified
  namespaces, package/dependency management).
