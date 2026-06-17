# lab-jetbrains-project-mode-delegation-p7-v0

Proof doc for card `LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7` — retire the
plugin-side import-graph scanner from P6 and delegate import-aware compilation to
the canonical compiler **project mode + overlay** (cards
`LAB-COMPILER-PROJECT-MODE-COMPILE-P1` / `LAB-COMPILER-PROJECT-OVERLAY-P2`).

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; the live compiler
is authority). **Lane:** standard / JetBrains DX cleanup. **Prerequisite:**
`LAB-COMPILER-PROJECT-OVERLAY-P2` CLOSED.

> JetBrains plugin only. No Rust compiler changes; no diagnostic suppression;
> plugin no longer owns import resolution; Gradle/Makefile not made the canonical
> project model.

## Verify-first findings (live plugin surfaces)

- `IgniterModelService.build` — compiled the current file alone for the editor
  **model** (editor coordinates) and used the P6 `IgniterImportCompilePlanner`
  (`scanProject` + `resolve`) to gather imported files for a multi-file
  **diagnostics** compile.
- `CompileIgniterFileAction` — same P6 resolve, then `compile(file, out, imported)`.
- `IgniterCompilerService.compile(sourceFile, outRoot, extraSources)` — issued
  `compile <current> <extra…> --out`.
- P6 gap (confirmed live): the multi-file diagnostics path only ran when at least one
  import **resolved on disk**; a file whose only non-stdlib import was missing fell
  back to single-file compile, which does not validate imports → the missing import
  was silently dropped.

## Exact CLI shape now issued by the plugin

```
igniter_compiler compile \
  --project-root <project-root> \
  --entry <current-module> \
  --overlay <on-disk-current.ig>=<temp-editor-buffer.ig> \
  --out <out.igapp>
```

Built by `IgniterProjectModePlanner.buildCompileArgs(...)` (pure, unit-tested) and run
by `IgniterCompilerService.compileProject(...)`. The compiler owns scanning, the module
index, and the import closure; the plugin supplies only the project root, the current
module name (the entry), and the overlay buffer.

## What changed (plugin)

- **New** `IgniterProjectModePlanner` (pure): `moduleNameOf`, `importedModules`,
  `isStdlib`, `entryModuleForProjectMode` (project mode applies iff the file declares a
  module AND has ≥1 non-stdlib import), `buildCompileArgs` (exact argv).
- **Deleted** `IgniterImportCompilePlanner` (+ its test): `scanProject` / `resolve` /
  `ModuleEntry` — the plugin no longer builds an import graph.
- `IgniterCompilerService`: added `compileProject(projectRoot, entryModule,
  overlayOriginal, overlayBuffer, outRoot, outBaseName)`; removed the now-unused
  `extraSources` from `compile()`; factored a shared `runCompile`; `locateReportFile`
  takes a base name (handles success bundle, refusal sibling, and project-resolve
  sibling layouts).
- `IgniterModelService`: diagnostics go through `projectModeDiagnostics(...)` — project
  mode + overlay with the already-written editor-text temp file as the overlay buffer.
  Returns null (→ unchanged standalone diagnostics) when project mode does not apply.
- `CompileIgniterFileAction`: `compileFile(...)` uses the same project-mode path (the
  saved file is its own overlay buffer); single-file otherwise.

## Editor coordinates / model safety (boundary honored)

The editor **model** (navigation, inlays, structure) is still derived from compiling the
current file alone, so its line/col stay in editor coordinates — unchanged from before
this card. Project-mode **diagnostics** come from the compiler's merged-program
coordinates exactly as the P6 multi-file path did (compiler merges units before
typecheck). P7 preserves that behavior rather than adopting P2 source evidence for
editor coordinates (explicitly out of scope per the card boundary). For the current
file, the overlay buffer *is* the editor text, so its diagnostics line up.

## Acceptance matrix — all 8 met

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Plugin calls project-mode CLI with `--project-root`/`--entry`/`--overlay` | ✅ `buildCompileArgs` + `compileProject`; unit test asserts exact argv |
| 2 | Unsaved editor buffer used via overlay | ✅ `IgniterModelService` passes the editor-text temp file as overlay buffer; live test `overlay buffer text wins…` |
| 3 | `webhook.ig` importing `CallRouterTypes` → no false `OOF-P1` | ✅ live proof `project mode plus overlay compiles without false OOF-P1` |
| 4 | Missing-only non-stdlib import → compiler `OOF-IMP*` even when nothing resolves | ✅ live proof `missing-only … yields OOF-IMP` (the P6 gap, now closed) |
| 5 | No-import single-file path unchanged or justified | ✅ `entryModuleForProjectMode` returns null → standalone `compile()`; model always standalone |
| 6 | `CompileIgniterFileAction` uses the same project-mode path | ✅ `compileFile(...)` → `compileProject(...)` |
| 7 | `./gradlew test --rerun-tasks` passes; exact count | ✅ **35 passed, 0 failed, 0 skipped** |
| 8 | `./gradlew clean buildPlugin` produces fresh zip; record path | ✅ `build/distributions/igniter-jetbrains-plugin-0.1.0.zip` |

## Proof commands & exact results

```
cd igniter-jetbrains-plugin
export IGNITER_COMPILER=…/igniter-compiler/target/debug/igniter_compiler   # so live proofs run, not skip
./gradlew test --rerun-tasks --console=plain      # BUILD SUCCESSFUL
./gradlew clean buildPlugin --console=plain        # BUILD SUCCESSFUL
```

Per-class test counts (`build/test-results/test/TEST-*.xml`):

| Test class | tests | failures | errors | skipped |
|------------|------:|---------:|-------:|--------:|
| IgniterImportAwareCompileProofTest (rewritten, live) | 5 | 0 | 0 | 0 |
| IgniterProjectModePlannerTest (new, pure) | 7 | 0 | 0 | 0 |
| IgniterLiveCompilerProofTest | 2 | 0 | 0 | 0 |
| IgniterReportParserTest | 4 | 0 | 0 | 0 |
| IgniterTypeHintPlannerTest | 6 | 0 | 0 | 0 |
| IgniterModelParserTest | 8 | 0 | 0 | 0 |
| IgniterQuickFixPlannerTest | 3 | 0 | 0 | 0 |
| **TOTAL** | **35** | **0** | **0** | **0** |

Live binary cross-check (debug `igniter_compiler`, before Gradle):

```
project mode  webhook   → status ok,  no OOF-P1
single-file   webhook   → status oof, 7×OOF-P1 (the documented false positive)
missing-only  import    → status oof, OOF-IMP2
overlay bad-field buffer → status oof, OOF-P1 (overlay text wins over valid disk)
```

Plugin zip: `igniter-jetbrains-plugin/build/distributions/igniter-jetbrains-plugin-0.1.0.zip`.

## Authority boundary

igniter-lab only. No Rust compiler semantics changed; no canon impact; no production
impact. The compiler is the single source of truth for project assembly; the plugin is a
consumer. The live compiler remains authority; this doc is evidence.

## Intentionally deferred

- Adopt P2 source evidence to map per-file diagnostics into editor coordinates (would
  let imported-module diagnostics annotate their own files instead of the merged
  coordinates carried over from P6).
- Filter project-mode diagnostics to the current file (parity with P6: none filtered).
- A custom `igniter.toml` that narrows source roots could place the current file outside
  them; the plugin then falls back to standalone (only the default `["."]` is guaranteed
  to contain the file). Detecting configured roots plugin-side is deferred.
