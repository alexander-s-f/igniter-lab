# Card: LAB-JETBRAINS-PROJECT-MODE-DELEGATION-P7

**Title:** Delegate JetBrains import-aware compile to compiler project mode + overlay
**Skill:** idd-agent-protocol
**Lane:** standard / JetBrains DX cleanup
**Status:** ✅ CLOSED — 2026-06-17
**Authority:** igniter-lab only; no canon impact; no production impact
**Prerequisite:** LAB-COMPILER-PROJECT-OVERLAY-P2 (CLOSED)
**Proof:** `lab-docs/lang/lab-jetbrains-project-mode-delegation-p7-v0.md`

---

## Card Statement

Replace the P6 plugin-side import-graph scanner (`IgniterImportCompilePlanner`) with the
canonical compiler project mode + overlay. The compiler becomes the single source of
truth for project assembly; the plugin only supplies project root, current module name,
and the unsaved editor buffer as an overlay:

```
igniter_compiler compile --project-root <root> --entry <current-module> \
  --overlay <on-disk-current.ig>=<temp-editor-buffer.ig> --out <out.igapp>
```

## Authority boundary (named before coding)

- **Decides behavior:** the live `igniter_compiler` (project mode + overlay, P1/P2).
- **Evidence only:** this card, the proof doc, test output.
- **Authorized to change:** the JetBrains plugin (Kotlin) + its tests.
- **Closed surfaces:** Rust compiler semantics, diagnostic suppression, language canon,
  the Gradle/Makefile build model.

## What landed (plugin)

- **New** `IgniterProjectModePlanner` (pure): text helpers + `entryModuleForProjectMode`
  + `buildCompileArgs` (exact CLI argv, unit-tested).
- **Deleted** `IgniterImportCompilePlanner` (+ test): plugin no longer builds an import
  graph (`scanProject`/`resolve`/`ModuleEntry` gone).
- `IgniterCompilerService`: added `compileProject(...)`; removed unused `extraSources`
  from `compile()`; shared `runCompile`; `locateReportFile(base)` handles all 3 report
  layouts (success bundle / refusal sibling / project-resolve sibling).
- `IgniterModelService`: diagnostics via `projectModeDiagnostics(...)` (project mode +
  overlay using the editor-text temp file as the buffer); standalone fallback when
  project mode does not apply. Editor **model** still standalone (editor coordinates).
- `CompileIgniterFileAction`: `compileFile(...)` uses the same project-mode path.

## Acceptance — all 8 met

1. Plugin calls project-mode CLI with `--project-root`/`--entry`/`--overlay` ✅
2. Unsaved editor buffer used via overlay ✅
3. `webhook.ig` importing `CallRouterTypes` → no false `OOF-P1` ✅
4. Missing-only non-stdlib import → compiler `OOF-IMP*` even when nothing resolves ✅ (closes the P6 gap)
5. No-import single-file path unchanged (project mode gated on module + non-stdlib import) ✅
6. `CompileIgniterFileAction` uses the same project-mode path ✅
7. `./gradlew test --rerun-tasks` → **35 passed, 0 failed, 0 skipped** ✅
8. `./gradlew clean buildPlugin` → `build/distributions/igniter-jetbrains-plugin-0.1.0.zip` ✅

## Verification

```
cd igniter-jetbrains-plugin
export IGNITER_COMPILER=…/igniter-compiler/target/debug/igniter_compiler
./gradlew test --rerun-tasks --console=plain   # BUILD SUCCESSFUL — 35 passed / 0 failed / 0 skipped
./gradlew clean buildPlugin --console=plain     # BUILD SUCCESSFUL — fresh zip
```

Live binary cross-check: project-mode webhook → ok (no OOF-P1); single-file webhook →
7×OOF-P1 (the false positive); missing-only import → OOF-IMP2; overlay bad-field buffer →
OOF-P1 (overlay text wins over valid disk).

## Hard boundaries respected

No Rust compiler changes; no diagnostic suppression; plugin-owned import resolution
removed; Gradle/Makefile not made canonical.

## Next / deferred

- Use P2 source evidence to map per-file diagnostics into editor coordinates (imported
  modules currently inherit P6 merged-coordinate behavior).
- Detect custom `igniter.toml` source roots plugin-side (today: default `["."]`
  guaranteed to contain the current file; otherwise standalone fallback).
