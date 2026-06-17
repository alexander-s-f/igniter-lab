# Card: LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9

**Title:** Map project-mode diagnostics back to their originating file + line
**Skill:** idd-agent-protocol
**Lane:** standard / JetBrains DX
**Status:** ✅ CLOSED — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Builds on:** LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3, LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7, LAB-JETBRAINS-PROJECT-MODE-RUNIDE-SMOKE-P8
**Proof:** `lab-docs/lang/lab-jetbrains-project-mode-diagnostic-mapping-p9-v0.md`

---

## Card Statement

The plugin reads the compiler's `source_line_map` + per-diagnostic origin enrichment
(P3) so project-mode diagnostics are attributed to the file currently in the editor
and remapped to original (per-file) lines, replacing the P7 merged-coordinate
behavior. Diagnostics belonging to imported files no longer annotate the current
editor.

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` (P3 emits the map + enrichment).
- **Evidence only:** this card, the proof doc, test output.
- **Authorized to change:** the JetBrains plugin (Kotlin) + tests.
- **Closed surfaces:** compiler/language semantics, diagnostic suppression,
  source-editing quickfixes.

## What landed (plugin)

- `OofDiagnostic` += `sourcePath` / `originalLine` / `mergedLine` (nullable).
- `IgniterReportParser`: per-diagnostic enrichment extraction + `parseSourceLineMap`.
- `SourceLineMapEntry` (public) + pure `IgniterDiagnosticMapper.remapForCurrentFile`.
- `CompilationResult.sourceLineMap` (filled in `runCompile`; empty for single-file).
- `IgniterModelService.projectModeDiagnostics` applies the mapper with the current
  file's origin paths = { overlay buffer path, on-disk path }.

## Mapping rule

Resolve origin via enrichment → else `source_line_map[mergedLine]` → else unknown.
Then: current file → remap to `original_line`; other file → drop; unknown
(`line:null` typecheck) → keep unchanged (no regression, never silently dropped).

## Honest limitation

Typecheck `OOF-P1` carries `line:null` at the compiler → unattributable → kept on the
current editor unchanged (same as P7). Needs a future compiler typecheck-span card;
it will then flow through this mapper unchanged.

## Acceptance — met

- Current-file parse error → attributed + remapped to original line (live proof: line 5) ✅
- Imported-file parse error → dropped from the current editor (live proof) ✅
- `line:null` typecheck → kept unchanged (no regression) ✅
- Merged-line-only diagnostics resolved via `source_line_map` ✅
- Single-file path unaffected (no map, default null fields) ✅

## Verification

```
cd igniter-jetbrains-plugin
export IGNITER_COMPILER=…/igniter-compiler/target/debug/igniter_compiler
./gradlew test --rerun-tasks --console=plain   # BUILD SUCCESSFUL — 47 passed / 0 failed / 0 skipped
./gradlew clean buildPlugin --console=plain     # fresh zip 191627 B
```

New tests: `IgniterDiagnosticMapperTest` (10), `IgniterProjectModeDiagnosticMappingProofTest` (2, live).

## Next / deferred

- **Next:** `LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-RUNIDE-SMOKE-P10` — runIde GUI
  smoke confirming cross-file attribution + current-file line accuracy in a real editor.
- Deferred: typecheck-span attribution (compiler card), `original_col` precision.
