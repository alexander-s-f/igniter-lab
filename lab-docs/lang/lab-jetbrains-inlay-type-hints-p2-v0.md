# lab-jetbrains-inlay-type-hints-p2-v0

Proof doc for card `LAB-JETBRAINS-INLAY-TYPE-HINTS-P2` — turn the proven semantic
model into visible DX: compiler-backed type inlay hints in `.ig` files.

**Status:** CLOSED. **Skill:** idd-agent-protocol. **Lane:** lang / JetBrains impl.

## What was built

- `hints/IgniterTypeHintPlanner` (pure, IntelliJ-free): `IgniterModel -> List<PlannedHint{nodeId,line,text}>`.
  v0 policy = hint inferred types **only for `compute` nodes** (their type never
  appears in source `compute name = expr`); explicit `input/output ... : Type` are
  not hinted (no duplication). Deterministic (sorted by line, nodeId). Fail-closed
  on `type == null`, `line <= 0`, or `IgniterModel.EMPTY`.
- `hints/IgniterTypeInlayProvider` (declarative `InlayHintsProvider` + `OwnBypassCollector`):
  reads `IgniterModelService.cached(...)` only — **never compiles on the EDT/render
  path**; empty/cold cache or missing document => no hints. Renders each planned hint
  at the end-of-line offset via `InlineInlayPosition` + `sink.addPresentation { text(...) }`.

## EP verification (no guessing — per card)

Platform: IntelliJ Community 2023.3 (gradle-intellij-plugin 1.17.4). Verified against
the SDK jars:

- EP name: `com.intellij.codeInsight.declarativeInlayProvider`
  (beanClass `InlayHintsProviderExtensionBean`), the modern **declarative** inlay API.
- Bean `@Attribute` field names (authoritative): `language`, `implementationClass`,
  `isEnabledByDefault`, `providerId`, `group` (`InlayGroup` enum; `TYPES_GROUP` confirmed),
  `nameKey`, `descriptionKey`, `bundle`.
- API used: `InlayHintsProvider.createCollector(PsiFile, Editor)`,
  `OwnBypassCollector.collectHintsForFile(PsiFile, InlayTreeSink)`,
  `InlineInlayPosition(offset, relatedToPrevious, priority)`,
  `InlayTreeSink.addPresentation(pos, payloads, tooltip, hasBackground){ text(text, null) }`.

`plugin.xml` registration:

```xml
<codeInsight.declarativeInlayProvider language="Igniter"
    implementationClass="com.igniter.plugin.hints.IgniterTypeInlayProvider"
    isEnabledByDefault="true" group="TYPES_GROUP" providerId="igniter.types.inlay"
    nameKey="inlay.igniter.types.name" descriptionKey="inlay.igniter.types.description"
    bundle="messages.IgniterBundle"/>
```

## Verification

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks   -> BUILD SUCCESSFUL, 20 tests, 0 failures, 0 skipped
```

- **Total tests: 20** (was 14 after P1; +6 planner tests).
- **Live compiler proof tests skipped? No** — `IgniterLiveCompilerProofTest` ran (2/2),
  binary resolved via relative `../igniter-compiler/...`. P1 nav/model/report tests still green.
- **Inlay provider test: compile-only (documented substitution).** The provider needs the
  IntelliJ runtime (PsiFile/editor/sink), so it is proven by `compileKotlin` against the real
  declarative API + EP registration; its policy is fully covered by the pure planner tests.

### Planner tests (`hints.IgniterTypeHintPlannerTest`, 6)

| Test | Acceptance |
|---|---|
| `: Integer` hint for `compute:Add.sum` @ line 7 | 1 |
| no hint for input/output/contract | 3 |
| v0 policy hints only compute nodes (`[compute:Add.sum]`) | 3 |
| empty model + `IgniterModel.EMPTY` => no hints | 2, 6 |
| deterministic/stable for the fixture | 4 |
| `type == null` compute => no hint | 2 |

Fixture: the committed P1 `fixtures/add.igapp` (real `igniter_compiler` artifacts;
`semantic_ir_program.json` types `compute:Add.sum = Integer`).

## What remains unproven without runIde

Actual on-screen rendering of the inlay (caret-side placement, settings toggle under
*Editor > Inlay Hints > Types > Igniter inferred types*, live refresh as the annotator
warms the cache). Proven instead: the planner policy (headless) + the adapter compiles
against the real 2023.3 declarative API + EP attribute names match the platform bean.
A `runIde` smoke (candidate `LAB-JETBRAINS-RUNIDE-SMOKE-P3`) would close this.

## Boundaries honoured

No language/compiler/`.ig`-syntax changes; no new navigation actions; no broad settings
UI; no regex-inferred hints (types come only from `SymbolNode.type`); no compile-on-EDT
(cache-only render path); fail-closed throughout. Lab tooling only.
