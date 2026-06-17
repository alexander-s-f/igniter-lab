# Card: LAB-JETBRAINS-DIAGNOSTIC-QUICKFIX-P3 — safe quickfix for compiler configuration

Status: CLOSED (2026-06-17) — proof: `lab-docs/lang/lab-jetbrains-diagnostic-quickfix-p3-v0.md`
Skill: idd-agent-protocol
Lane: lang / JetBrains implementation
Owner: Opus

## Why this card exists

P1 proved compiler-backed diagnostics/model parsing. P2 added compiler-backed
type inlay hints. The next useful DX layer is a small, safe diagnostic quickfix.

Do **not** start with language-changing OOF quickfixes. Most OOF diagnostics
need semantic judgement and must not become editor folklore. Start with the
plugin-owned diagnostic that is safe and reversible:

```text
PLUGIN-001 = igniter_compiler binary not found
```

Quickfix: open the Igniter settings configurable so the developer can set the
compiler path.

## Verify-first inputs

Read these live files before editing:

- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/compiler/IgniterCompilerService.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/compiler/IgniterExternalAnnotator.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/settings/IgniterSettings.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/settings/IgniterSettingsConfigurable.kt`
- `igniter-jetbrains-plugin/src/main/resources/META-INF/plugin.xml`
- `igniter-jetbrains-plugin/src/main/resources/messages/IgniterBundle.properties`
- `igniter-jetbrains-plugin/src/test/kotlin/com/igniter/plugin/compiler/IgniterReportParserTest.kt`
- `lab-docs/lang/lab-jetbrains-semantic-nav-proof-p1-v0.md`
- `lab-docs/lang/lab-jetbrains-inlay-type-hints-p2-v0.md`

Then verify the current IntelliJ API for registering a quickfix/intention on an
annotation under this platform version. Do not guess method names.

## Goal

When the annotator reports `PLUGIN-001`, attach one safe quickfix:

```text
Configure igniter_compiler path...
```

Invoking it should open the existing Igniter settings/configurable. It must not
modify source code, compiler output, or `.ig` semantics.

## Required implementation shape

Keep policy pure and adapter thin.

Suggested shape:

```text
IgniterQuickFixPlanner
  input: OofDiagnostic
  output: QuickFixSpec?  // e.g. ConfigureCompilerPath

ConfigureCompilerPathQuickFix
  IntelliJ adapter: opens IgniterSettingsConfigurable

IgniterExternalAnnotator
  attaches the quickfix only for planner-approved diagnostics
```

The pure planner must be unit-tested without IntelliJ fixtures.

## Acceptance

1. `PLUGIN-001` diagnostics get exactly one quickfix spec:
   `ConfigureCompilerPath`.
2. Ordinary compiler diagnostics (`OOF-*`) get no quickfix in this card.
3. The annotation builder attaches the quickfix for `PLUGIN-001`.
4. The quickfix opens the existing Igniter configurable/settings path, or if
   direct UI invocation is too hard in headless tests, the adapter compiles and
   the proof doc explains the substitution.
5. The fix never edits `.ig` source.
6. Existing P1/P2 tests remain green.
7. No new compiler/language semantics.

## Suggested tests

Add tests under `igniter-jetbrains-plugin/src/test/...`.

Required:

- pure planner: `PLUGIN-001` -> configure-compiler-path spec;
- pure planner: `OOF-P0`, `OOF-TY0`, unknown code -> no spec;
- display text test for the quickfix name if feasible without IDE runtime;
- compile/wiring test via `./gradlew test --rerun-tasks`.

Avoid reflection. If IntelliJ UI invocation cannot be tested headlessly, document
that the UI action is compile-proven and leave `runIde` smoke as a separate card.

## Verification

Required:

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks
```

Report:

- total test count;
- whether live compiler proof tests skipped;
- what was proven headlessly;
- what remains for `runIde`.

## Deliverables

- Quickfix planner/adapter implementation.
- Focused tests.
- Proof doc:
  `lab-docs/lang/lab-jetbrains-diagnostic-quickfix-p3-v0.md`
- Close this card with exact verification output.

## Closed surfaces

Do not do these in P3:

- No source-editing quickfixes for OOF diagnostics.
- No automatic rewrite of `.ig`.
- No compiler/parser/typechecker changes.
- No broad settings UI redesign.
- No new actions unrelated to diagnostics.
- No `runIde` requirement for closure.

## Next route after P3

If P3 closes cleanly, likely next cards:

- `LAB-JETBRAINS-RUNIDE-SMOKE-P4` — GUI smoke for Ctrl+Click, inlays, and the
  compiler-path quickfix.
- `LAB-JETBRAINS-OOF-QUICKFIX-READINESS-P4` — design/readiness for safe
  source-editing quickfix classes, if any.

Do not start either route here.

---

## Closing report (2026-06-17)

```text
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks  -> BUILD SUCCESSFUL, 23 tests, 0 failures, 0 skipped
```

- **Total tests:** 23 (was 20 after P2; +3 `quickfix.IgniterQuickFixPlannerTest`).
- **Live compiler proof tests skipped?** No — `IgniterLiveCompilerProofTest` 2/2; P1/P2 green (acceptance 6).
- **Proven headlessly:** `PLUGIN-001 → CONFIGURE_COMPILER_PATH`; `OOF-P0/OOF-TY0/OOF-L3/PLUGIN-002/UNKNOWN/"" → null`;
  display text "Configure igniter_compiler path…", family "Igniter", `startInWriteAction=false` from a real
  `ConfigureCompilerPathQuickFix` instance; annotator + adapter compile against real 2023.3
  `IntentionAction` / `AnnotationBuilder.withFix` / `ShowSettingsUtil` APIs.
- **Remaining for runIde:** the fix appearing under a PLUGIN-001 annotation and opening the configurable on click.

**Implementation:** `quickfix/IgniterQuickFixPlanner` (pure: PLUGIN-001 only, OOF-* none) +
`quickfix/ConfigureCompilerPathQuickFix` (`IntentionAction`, opens `IgniterSettingsConfigurable` via
`ShowSettingsUtil`, never edits source, empty preview) + `IgniterExternalAnnotator.apply` attaches via
`withFix`. Acceptance 1–7 met. No OOF source-editing fixes, no compiler/`.ig` changes, no EP needed (inline fix).
