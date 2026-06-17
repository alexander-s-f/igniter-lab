# lab-jetbrains-diagnostic-quickfix-p3-v0

Proof doc for card `LAB-JETBRAINS-DIAGNOSTIC-QUICKFIX-P3` — one small, safe,
plugin-owned diagnostic quickfix.

**Status:** CLOSED. **Skill:** idd-agent-protocol. **Lane:** lang / JetBrains impl.

## What was built

- `quickfix/IgniterQuickFixPlanner` (pure, IntelliJ-free): `code -> IgniterQuickFix?`.
  Only plugin-owned, reversible fixes: `PLUGIN-001` → `CONFIGURE_COMPILER_PATH`.
  Compiler `OOF-*` (and everything else) → `null` — they need semantic judgement
  and must not become editor folklore.
- `quickfix/ConfigureCompilerPathQuickFix` (`IntentionAction` adapter): opens the
  existing `IgniterSettingsConfigurable` via `ShowSettingsUtil`. Non-destructive —
  `startInWriteAction = false`, `generatePreview = IntentionPreviewInfo.EMPTY`,
  never edits `.ig` source.
- `IgniterExternalAnnotator.apply` now builds one `AnnotationBuilder` per diagnostic
  and attaches the planner-approved fix via `AnnotationBuilder.withFix(...)`.

## API verification (no guessing — per card)

Platform: IntelliJ Community 2023.3. Verified against the SDK jars:

- `com.intellij.lang.annotation.AnnotationBuilder.withFix(IntentionAction): AnnotationBuilder` ✓
- `com.intellij.codeInsight.intention.IntentionAction` — `getText`, `getFamilyName`,
  `isAvailable(Project, Editor?, PsiFile?)`, `invoke(Project, Editor?, PsiFile?)`,
  `startInWriteAction`, default `generatePreview(Project, Editor, PsiFile)` ✓
- `com.intellij.openapi.options.ShowSettingsUtil.showSettingsDialog(Project, Class<T : Configurable>)` ✓

No EP registration needed: inline annotation fixes are attached programmatically by
the annotator, not declared in `plugin.xml`.

## Verification

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks   -> BUILD SUCCESSFUL, 23 tests, 0 failures, 0 skipped
```

- **Total tests: 23** (was 20 after P2; +3 `quickfix.IgniterQuickFixPlannerTest`).
- **Live compiler proof tests skipped? No** — `IgniterLiveCompilerProofTest` ran 2/2;
  P1/P2 tests (model, report, hints) all green (acceptance 6).
- **Proven headlessly:**
  - `planFor("PLUGIN-001") == CONFIGURE_COMPILER_PATH` (acceptance 1);
  - `planFor` of `OOF-P0`, `OOF-TY0`, `OOF-L3`, `PLUGIN-002`, `UNKNOWN`, `""` → `null` (acceptance 2);
  - display text `"Configure igniter_compiler path…"`, family name `"Igniter"`,
    `startInWriteAction == false` — read from a real `ConfigureCompilerPathQuickFix` instance;
  - annotator + adapter compile against the real 2023.3 `IntentionAction` /
    `AnnotationBuilder.withFix` / `ShowSettingsUtil` APIs (acceptance 3, 4).
- **Inlay/quickfix UI:** the annotator's `withFix` attachment and the dialog-opening
  `invoke` need the IntelliJ runtime; they are compile-proven (documented substitution).

## What remains for runIde

The quickfix actually appearing under a `PLUGIN-001` annotation and clicking it opening
*Settings > Languages & Frameworks > Igniter*. Candidate: `LAB-JETBRAINS-RUNIDE-SMOKE-P4`.

## Boundaries honoured

No source-editing quickfix for any OOF diagnostic; no `.ig` rewrite; no
compiler/parser/typechecker changes; no settings-UI redesign; no new diagnostic-unrelated
actions; no `runIde` required for closure. The only fix is plugin-owned and reversible.
