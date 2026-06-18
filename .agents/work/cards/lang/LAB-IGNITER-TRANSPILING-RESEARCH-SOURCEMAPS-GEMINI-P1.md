# Card: LAB-IGNITER-TRANSPILING-RESEARCH-SOURCEMAPS-GEMINI-P1 — Source maps, diagnostics, and debug traces for projection dialects

**Lane:** background / research  
**Status:** CLOSED 2026-06-18  
**Date opened:** 2026-06-18  
**Delegation-Code:** `GEMINI-20260618-TRANSPILING-B`  
**Research label:** `BACKGROUND-RESEARCH`  
**Authority:** Lab research only. No code. No canon.

## Why this card exists

Projection dialects are only useful if errors remain understandable. `.igweb` generates `.ig`; `.igv`
generates ViewArtifact JSON. If generated errors point at the generated artifact without a stable path
back to the source dialect, developer experience collapses. This background Gemini agent studies
source maps, diagnostics, and debug traces.

## Read first

- `.agents/work/cards/lang/LAB-IGNITER-PROJECTION-DIALECTS-P0.md`
- `lab-docs/lang/lab-igniter-projection-dialects-p0-v0.md`
- `igniter-ui-kit/src/igv.rs`
- `igniter-compiler/src/igweb.rs`
- `igniter-compiler/src/project.rs`
- any current source-map or multifile diagnostic proof docs found by `rg "source map|source_map|multifile|diagnostic" lab-docs/lang igniter-compiler`

## Goal

Produce one research packet that answers: **how should Igniter projection dialects preserve source
positions and explain generated artifacts without hiding the target?**

## Questions to research

1. What diagnostic shape exists today for `.igv` and `.igweb` lowerer errors?
2. What happens when the lowered target itself fails validation or compile?
3. What minimum source-map model is enough for v0: line map, span map, segment map, or full VLQ-style
   source map?
4. How should generated `.ig` diagnostics be remapped back to `.igweb` while keeping generated `.ig`
   inspectable?
5. How should ViewArtifact JSON errors map back to `.igv` lines and fields?
6. What should the debug artifact contain: dialect source hash, generated target hash, mapping table,
   lowerer version, target kind?
7. What does a good IDE/JB diagnostic handoff look like for projection dialects?
8. What tests prove diagnostics are stable and useful?

## Output contract

Write exactly one report:

`lab-docs/lang/lab-igniter-transpiling-research-sourcemaps-gemini-p1-v0.md`

Then update only this card with a closing report.

## Closed surfaces

- No implementation.
- No compiler or plugin edits.
- No `.igv`/`.igweb` edits.
- No canon promotion.
- Do not rewrite P0/P4/P1 docs; cite them only.

## Acceptance

- [x] Report identifies current diagnostic/source-map behavior.
- [x] Report proposes a minimal v0 source-map/debug artifact shape.
- [x] Report distinguishes lowerer parse errors from downstream target errors.
- [x] Report includes IDE/JB handoff implications.
- [x] Report includes test obligations for future implementation.
- [x] No code changed.

## Closing Report

**Research Summary:**
We surveyed the source mapping, diagnostic remapping, and overlay integration boundaries for Igniter's Projection Dialects (`.igv`, `.igweb`). The results have been documented in:
[lab-igniter-transpiling-research-sourcemaps-gemini-p1-v0.md](../../lab-docs/lang/lab-igniter-transpiling-research-sourcemaps-gemini-p1-v0.md)

**Key Recommendations:**
1. **Source Maps**: Use flat, line-to-line mappings (`.ig.map.json` sidecar) for text targets like `.ig`, and path-to-line mappings (`.json.map.json` sidecar) for structured targets like ViewArtifact JSON.
2. **Compiler Remapping**: Extend `igc` to automatically detect sidecar maps and enrich compiler diagnostics JSON (e.g. adding `original_line` and `source_path` pointing back to `.igweb`), while keeping generated files readable and inspectable.
3. **IDE Integration**: Utilize a two-stage overlay compilation wrapper for unsaved editor buffers.
4. **No Code Edits**: Zero files modified in compiler or plugins, adhering strictly to delegation scope.

