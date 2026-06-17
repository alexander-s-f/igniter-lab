# lab-jetbrains-project-mode-diagnostic-mapping-p9-v0

Proof doc for card `LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-P9` — the plugin
consumes the compiler's `source_line_map` + per-diagnostic origin enrichment
(card `LAB-COMPILER-MULTIFILE-SOURCE-MAP-P3`) to attribute project-mode diagnostics
to the file currently in the editor and remap them to original (per-file) lines,
instead of the P7 merged-coordinate behavior.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler
is authority). **Lane:** standard / JetBrains DX. **Builds on:** P3 (source map),
P7 (project-mode delegation), P8 (runIde smoke).

> JetBrains plugin only. No compiler/language changes; no diagnostic suppression;
> no source-editing quickfixes.

## Verify-first findings (live surfaces)

- `IgniterReportParser.parseReport` produced `OofDiagnostic(code, message, line,
  col, severity)` only — no per-file origin; `line:null` was coerced to 1.
- `IgniterModelService.projectModeDiagnostics` returned the project-mode compile's
  diagnostics verbatim and the annotator applied them to the current editor at their
  (merged) line — so an imported-file error could land on the wrong file/line (the
  P7-acknowledged gap).
- P3 report shape (confirmed): typecheck `OOF-P1` carries `line:null` (unmappable);
  parse errors carry a numeric merged `line` and are enriched with `source_path` /
  `module_path` / `original_line`; the report also has a top-level `source_line_map`.

## What changed (plugin)

- `OofDiagnostic` gains `sourcePath` / `originalLine` / `mergedLine` (nullable;
  default null → existing call sites unaffected).
- `IgniterReportParser`: populates those per diagnostic; adds
  `parseSourceLineMap(json)` → `List<SourceLineMapEntry>`.
- `SourceLineMapEntry` (public) + `IgniterDiagnosticMapper` (pure): `remapForCurrentFile`.
- `CompilationResult` carries `sourceLineMap` (filled by `runCompile` from the report;
  empty for single-file).
- `IgniterModelService.projectModeDiagnostics` runs the mapper with the current file's
  origin paths = { overlay buffer path, on-disk path }.

## Mapping rule (`IgniterDiagnosticMapper.remapForCurrentFile`)

For each diagnostic, resolve its origin `(source_path, original_line)`:
1. per-diagnostic enrichment (`sourcePath` + `originalLine`) if present, else
2. `source_line_map[mergedLine]` lookup, else
3. unknown.

Then:
- **origin == current file** → keep, `line = original_line` (remapped; `col` unchanged).
- **origin == a different file** → drop (it annotates that file when it is the active editor).
- **origin unknown** (e.g. `line:null` typecheck) → keep unchanged — never silently dropped.

Paths compared by canonical path. The current file's unit is read from the overlay
buffer in project mode, so its origin path is the buffer path — both buffer and
on-disk paths are treated as "current".

## What can / cannot be mapped today (honest)

| Diagnostic class | origin resolvable? | behavior |
|------------------|--------------------|----------|
| Parse error in current file | yes (enriched) | remapped to its original line |
| Parse error in an imported file | yes (enriched) | dropped from the current editor |
| Typecheck `OOF-P1` (`line:null`) | **no** | kept on the current editor unchanged (P7 behavior; no regression) |

Typecheck cross-file attribution is still blocked by `line:null` at the compiler
(same root cause documented in P3). When the compiler gains typecheck spans, those
diagnostics flow through the same mapper with no plugin change.

## Acceptance / proof

- **Unit (`IgniterDiagnosticMapperTest`, 10):** enriched current-file → remapped;
  enriched other-file → dropped; merged-line-only via `source_line_map` → remapped /
  dropped; `line:null` unknown → kept unchanged; empty → empty; `parseSourceLineMap`
  reads entries; `parseReport` extracts enrichment; `line:null` leaves origin null;
  single-file report has no map.
- **Live end-to-end (`IgniterProjectModeDiagnosticMappingProofTest`, 2):** against the
  real `igniter_compiler` —
  - current-file parse error → attributed to the current file and **remapped to original
    line 5** (not the merged universe line);
  - imported-file parse error → **dropped** from the current editor.

## Exact test counts

```
cd igniter-jetbrains-plugin
export IGNITER_COMPILER=…/igniter-compiler/target/debug/igniter_compiler
./gradlew test --rerun-tasks --console=plain    # BUILD SUCCESSFUL
```

| Test class | tests | fail | skip |
|------------|------:|-----:|-----:|
| IgniterDiagnosticMapperTest (new) | 10 | 0 | 0 |
| IgniterProjectModeDiagnosticMappingProofTest (new, live) | 2 | 0 | 0 |
| IgniterImportAwareCompileProofTest | 5 | 0 | 0 |
| IgniterProjectModePlannerTest | 7 | 0 | 0 |
| IgniterLiveCompilerProofTest | 2 | 0 | 0 |
| IgniterReportParserTest | 4 | 0 | 0 |
| IgniterTypeHintPlannerTest | 6 | 0 | 0 |
| IgniterModelParserTest | 8 | 0 | 0 |
| IgniterQuickFixPlannerTest | 3 | 0 | 0 |
| **TOTAL** | **47** | **0** | **0** (0 skipped — live proofs ran) |

`./gradlew clean buildPlugin` → `build/distributions/igniter-jetbrains-plugin-0.1.0.zip` (191627 B).

## Authority boundary

igniter-lab only. No compiler/language change; the plugin is a consumer of P3 evidence.
The live compiler is authority; this doc is evidence.

## Next route

`LAB-JETBRAINS-PROJECT-MODE-DIAGNOSTIC-MAPPING-RUNIDE-SMOKE-P10` — a runIde GUI smoke
(as P8 was for P7): confirm in a real editor that an imported-file error does not
annotate the current file and that a current-file parse error highlights its true
line. Deferred until then: typecheck-span attribution (needs a compiler card), and
`original_col` precision.
