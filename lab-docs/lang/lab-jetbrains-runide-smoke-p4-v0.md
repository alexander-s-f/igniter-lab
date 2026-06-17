# lab-jetbrains-runide-smoke-p4-v0

Proof doc for card `LAB-JETBRAINS-RUNIDE-SMOKE-P4` — a bounded `runIde` smoke that
moves the P1/P2/P3 surfaces from *compile/headless-proven* toward *proven in a live
JetBrains IDE sandbox*, and records exactly what the current environment could and
could not observe.

**Status:** CLOSED. **Skill:** idd-agent-protocol (observation-first; evidence is not authority).
**Lane:** lang / JetBrains smoke.

> This card creates evidence. It does not create new plugin authority, and it adds no
> language semantics or source-editing quickfixes (none were introduced — acceptance 7).

## TL;DR

- `./gradlew test --rerun-tasks` → **BUILD SUCCESSFUL, 23 tests, 0 failures, 0 skipped**
  (the 2 live-compiler-proof tests ran against the real release binary — not skipped).
- `./gradlew runIde` → **IDE sandbox started successfully**; the Igniter plugin
  **loaded and is active**; the P1 `igniter.symbols` index EP **registered and built
  at runtime**. All plugin extension points loaded with **zero plugin-class / EP errors**.
- **New GUI-only finding:** the plugin's bundled color-scheme XML
  (`IgniterLight.xml` / `IgniterDark.xml`) is **invalid** — `--` inside `<!-- … -->`
  comments — so IntelliJ fails to load the Igniter default syntax colors at startup
  (15 `SEVERE` lines). Non-fatal to boot; invisible to headless tests. Flagged as a
  separate fix card (out of scope here).
- The **interactive** surfaces (diagnostic annotation in-editor, `PLUGIN-001` quickfix
  invocation, inlay rendering, Ctrl+Click navigation) could **not** be exercised in this
  automated session: they require keyboard / modifier-click gestures that the agent
  environment cannot perform on a JetBrains IDE (see *Environment constraint*). They
  remain headless/compile-proven from P1–P3.

## Environment

| Item | Value |
|---|---|
| Platform | IntelliJ IDEA Community **2023.3**, Build `IC-233.11799.241` |
| Runtime | JBR `17.0.9` (OpenJDK 64-Bit Server VM, JetBrains s.r.o.) |
| OS | macOS 26.5 (Darwin 25.5.0), arm64 |
| Gradle / plugin | Gradle 8.5, `org.jetbrains.intellij` 1.17.4 |
| Compiler resolvable? | Yes — `runIde` launched with `IGNITER_COMPILER=…/igniter-compiler/target/release/igniter_compiler` (healthy config) |

## 1. Headless tests (acceptance 1)

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks
# -> BUILD SUCCESSFUL; :test executed
```

Exact counts read from `build/test-results/test/*.xml`:

| Class | Tests | Skipped | Fail/Err |
|---|---|---|---|
| `IgniterLiveCompilerProofTest` | 2 | 0 | 0 |
| `compiler.IgniterReportParserTest` | 4 | 0 | 0 |
| `hints.IgniterTypeHintPlannerTest` | 6 | 0 | 0 |
| `model.IgniterModelParserTest` | 8 | 0 | 0 |
| `quickfix.IgniterQuickFixPlannerTest` | 3 | 0 | 0 |
| **Total** | **23** | **0** | **0** |

The 2 live tests resolved `../igniter-compiler/target/release/igniter_compiler` (built;
present) and **ran** (skipped=0) — they compile the `add.ig` fixture with the real native
compiler and assert the success layout + a refused `OOF-*` sibling report.

## 2. `runIde` launch (acceptance 2)

```bash
cd igniter-jetbrains-plugin
IGNITER_COMPILER=…/igniter-compiler/target/release/igniter_compiler ./gradlew runIde
```

Result: **the IDE sandbox started**. Evidence from
`build/idea-sandbox/system/log/idea.log` (old log archived to `idea.log.pre-p4`
first, so all lines below are from this run, 2026-06-17 12:13):

```
[39]   INFO - #c.i.i.p.PluginManager - Loaded custom plugins: Igniter Language (0.1.0)
…JVM options include: -Didea.required.plugins.id=com.igniter.plugin
[780]  INFO - #c.i.u.i.FileBasedIndexImpl - Indices to be built: igniter.symbols(v = 2),FilenameIndex(v = 258)
[786]  INFO - #c.i.u.i.IndexDataInitializer - Index data initialization done … igniter.symbols …
```

The IDE was launched in the background, observed via its log, and then closed
(`runIde` task stopped, IDE JVM confirmed exited). No interactive window driving was
attempted (see constraint below).

## 3. What is now PROVEN IN GUI

These were observed in the live sandbox and are new over P1–P3:

1. **Sandbox IDE boots** — IntelliJ IDEA 2023.3 came up on JBR 17 / macOS.
2. **Plugin loads and is active** — `Loaded custom plugins: Igniter Language (0.1.0)`.
   The sandbox was launched with `-Didea.required.plugins.id=com.igniter.plugin` and the
   IDE proceeded past the required-plugin gate (a missing/broken plugin id aborts boot).
3. **All plugin extension points load cleanly** — a full grep of the run's log shows
   **no** error/exception/EP-failure referencing any `com.igniter.*` class. The
   declarative inlay provider, external annotator, navigation handlers, services,
   completion, references, file type, structure view, tool window and actions all
   registered without complaint.
4. **P1 semantic substrate is live** — the `igniter.symbols` file-based index
   (`v = 2`) appears in both *Indices to be built* and the initialized-index set. This
   is the project-wide symbol index behind Go-to-Symbol / Find-Dependents — confirmed
   instantiated by the platform at runtime, not just compiled.

## 4. GUI-surfaced DEFECT (new — not catchable headlessly)

The only `SEVERE` category in the entire run is `EditorColorsManagerImpl`
(15 lines = 3 load attempts × error + build/JDK/OS/last-action banner):

```
SEVERE - #c.i.o.e.c.i.EditorColorsManagerImpl - String '--' not allowed in comment (missing '>'?)
 at [row,col {unknown-source}]: [118,22]
  … EditorColorsManagerImplKt.loadAdditionalTextAttributesForScheme …
Caused by: com.fasterxml.aalto.WFCException: String '--' not allowed in comment (missing '>'?)
```

Root cause confirmed in the plugin's own resources: the bundled
`additionalTextAttributes` color schemes embed `--` **inside** XML comments, which is
illegal (`-->` is the only legal place `--` may appear):

- `src/main/resources/colorSchemes/IgniterLight.xml:118` → `<!-- #D9694A  --oof  · bad character -->` (matches the error's `[118,22]`)
- `src/main/resources/colorSchemes/IgniterDark.xml` lines 9 `--ignite`, 17 `--amber`,
  24 `--ember`, 55 `--grey-3`, 62 `--grey`, 117 `--oof`

Effect: IntelliJ **cannot load the Igniter bundled color scheme** at startup, so the
plugin's intended default syntax colors (Ember-on-Ink / Paper) do not apply. The IDE
boot itself is not aborted (it falls back to default attributes). Headless unit tests
never parse `additionalTextAttributes`, so this was invisible until `runIde` — exactly
the gap this smoke exists to close.

**Out of scope for this evidence card** (no source edits here). Flagged for a separate
small fix card: replace the `--xxx` tokens in the two color-scheme XML comments with a
legal form (e.g. `—xxx`, `· xxx`, or move outside the comment).

## 5. Still HEADLESS / COMPILE-PROVEN only (GUI gesture blocked)

### Environment constraint (the blocker, stated once)

This was an automated agent session with no human at the GUI. Driving a JetBrains IDE
via computer-use is restricted to the **"click" tier**: left-click + screenshot only —
**no typing, no key presses, no modifier-clicks, no right-click**. Every remaining smoke
case needs at least one forbidden gesture:

| Case | Gesture required to observe | Blocked by |
|---|---|---|
| 2. Compiler diagnostic annotation in editor | open a `.ig` file + edit to trigger `ExternalAnnotator` | open-file / typing |
| 3. `PLUGIN-001` quickfix appears + opens Settings | `Alt+Enter` on the annotation | key press |
| 4. Inlay type hints render | open a `.ig` file with a warm cache | open-file |
| 5. Ctrl+Click / Go-to-Declaration | modifier-click on an identifier | modifier-click |

A welcome-screen screenshot was deliberately **not** taken: with no `.ig` file open it
would show none of the four surfaces, while the log already proves boot + plugin-load
more rigorously.

### What stands in for each (from P1–P3, unchanged and still green)

- **Diagnostics (case 2):** `IgniterReportParserTest` (4) + `IgniterLiveCompilerProofTest`
  (2, live binary) + `IgniterModelParserTest` (8); annotator compiles against the 2023.3
  `ExternalAnnotator` / `AnnotationBuilder` API. *(live compiler, plugin-fallback
  `PLUGIN-001` both exercised at the unit level.)*
- **`PLUGIN-001` quickfix (case 3):** `IgniterQuickFixPlannerTest` (3) —
  `planFor("PLUGIN-001") == CONFIGURE_COMPILER_PATH`, all `OOF-*`/others → `null`;
  display text `"Configure igniter_compiler path…"`, `startInWriteAction == false`;
  adapter compiles against `IntentionAction` / `AnnotationBuilder.withFix` /
  `ShowSettingsUtil`.
- **Inlay hints (case 4):** `IgniterTypeHintPlannerTest` (6) + the
  `codeInsight.declarativeInlayProvider` EP **registered at runtime in this run** with no
  error (stronger than P2, which only had compile + EP-attribute verification).
- **Navigation (case 5):** `model.resolveRef` / `enclosingContract` / `usagesOf` tested;
  and the `igniter.symbols` index that backs project-wide navigation is **GUI-confirmed
  registered + built** (section 3.4).

## Acceptance ledger

| # | Requirement | Outcome |
|---|---|---|
| 1 | tests pass; report counts | ✅ 23 tests, 0 skipped, 0 failures (2 live ran) |
| 2 | `runIde` starts or blocker classified | ✅ started; evidence from idea.log |
| 3 | `.ig` opens with plugin active | ⚠️ plugin **active** ✅; file-open **blocked** (no-keyboard tier), documented |
| 4 | `PLUGIN-001` quickfix opens Settings OR exact GUI blocker | ✅ exact blocker documented (`Alt+Enter` not available) |
| 5 | inlays observed OR exact GUI blocker | ✅ exact blocker documented (open-file); EP registration GUI-confirmed |
| 6 | navigation observed OR exact GUI blocker | ✅ exact blocker documented (modifier-click); index EP GUI-confirmed |
| 7 | no source-editing quickfixes introduced | ✅ none |
| 8 | proof doc separates GUI-proven vs headless | ✅ sections 3–5 |

## Next smallest routes

1. **Color-scheme XML fix card** (small, plugin-owned, safe) — remove `--` from the two
   color-scheme comments so the bundled Igniter scheme loads. *(Flagged.)*
2. **Human-run `runIde` session** — a developer at the keyboard drives the four gestures
   (open `add.ig` / `bad.ig`, `Alt+Enter`, Ctrl+Click, toggle inlays) and attaches
   screenshots; this closes cases 2–5 as truly GUI-proven.
3. **Automated UI smoke** — `runIdeForUiTests` (robot-server) could drive the gestures
   programmatically in a future card, removing the human dependency.

## Boundaries honoured

No parser / compiler / language changes. No OOF source-editing quickfix. No settings or
product-UX redesign. No `.ig` app-source changes (smoke fixtures were disposable, under
`/tmp`). No external network (the Marketplace `INFO` errors in the log are the expected
offline-sandbox behaviour, unrelated to the plugin). Old Ruby framework surfaces were not
used as language authority.
