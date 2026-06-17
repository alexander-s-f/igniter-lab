# Card: LAB-JETBRAINS-INLAY-TYPE-HINTS-P2 — compiler-backed type inlay hints

Status: CLOSED (2026-06-17) — proof: `lab-docs/lang/lab-jetbrains-inlay-type-hints-p2-v0.md`
Skill: idd-agent-protocol
Lane: lang / JetBrains implementation
Owner: Opus

## Why this card exists

`LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1` closed the prior `test NO-SOURCE`
gap and proved the compiler-backed semantic model:

- `IgniterModelParser` joins `sourcemap.json` + `semantic_ir_program.json`.
- `SymbolNode.type` carries inferred compiler types.
- `IgniterModelService.cached(...)` exposes the latest model without compiling on
  the EDT.

P2 should turn that proven semantic model into visible developer DX:
lightweight inlay type hints in `.ig` files.

## Verify-first inputs

Read the live surface before editing:

- `igniter-jetbrains-plugin/build.gradle.kts`
- `igniter-jetbrains-plugin/src/main/resources/META-INF/plugin.xml`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModel.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModelService.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModelParser.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/compiler/IgniterExternalAnnotator.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/navigation/IgniterGotoDeclarationHandler.kt`
- `igniter-jetbrains-plugin/src/test/kotlin/com/igniter/plugin/model/IgniterModelParserTest.kt`
- `lab-docs/lang/lab-jetbrains-semantic-nav-proof-p1-v0.md`
- `.agents/work/cards/lang/LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1.md`

Then verify the exact IntelliJ Platform extension point/API for inlay hints under
the current Gradle platform version. Do not guess the EP name.

## Goal

Add compiler-backed type inlay hints for `.ig` symbols whose type is known from
the semantic model.

Example intent:

```text
compute sum = a + b      : Integer
output sum: Integer      (probably no hint; already explicit)
```

The exact visual placement must follow the current IntelliJ inlay API and be
kept modest. The goal is useful type visibility, not a broad UI feature.

## Required design rules

1. **Compiler-backed only.** Hints must read `SymbolNode.type` from
   `IgniterModelService.cached(...)` or another already-built analysis result.
   They must not infer types from regex/text.

2. **No compile on EDT.** If the cache is cold or stale, show no hints. The
   external annotator/model service can warm the cache; the hint provider must
   not spawn `igniter_compiler` in the render path.

3. **Small hint policy.** Start with inferred-type nodes where the source does
   not already show the type clearly. Recommended v0:
   - show hints for `compute` nodes with inferred type;
   - avoid duplicating explicit `input ...: Type` / `output ...: Type` unless
     tests prove the UX is useful and non-noisy.

4. **Fail closed.** Empty model, failed compile, missing type, unknown line/col,
   or missing document position => no hint, no exception.

5. **Lab tooling only.** JetBrains plugin remains lab evidence/tooling, not
   language authority. No compiler or `.ig` semantics changes.

## Suggested implementation shape

Keep as much logic pure/testable as possible:

```text
IgniterTypeHintPlanner
  input: IgniterModel + source text/document helper
  output: list of planned hints {node_id, line, col/offset, text}

IgniterTypeInlayProvider
  IntelliJ adapter: reads cached model, calls planner, renders hints
```

Names may vary, but the separation matters: planner tests should not need an IDE
fixture. The IntelliJ provider can have a minimal compile/wiring test through
`./gradlew test`.

## Acceptance

1. A pure planner returns a `: Integer` hint for `compute:Add.sum` in the P1
   fixture because `semantic_ir_program.json` says the type is `Integer`.
2. Planner does not emit hints for symbols with `type == null`.
3. Planner does not emit duplicate hints for explicit type declarations in the
   chosen v0 policy.
4. Planner is deterministic and stable for the committed `add.igapp` fixture.
5. IntelliJ provider reads only cached semantic analysis; no compiler process is
   spawned from the inlay render path.
6. Cold cache / `IgniterModel.EMPTY` yields no hints and no errors.
7. `plugin.xml` registers the provider through the correct current IntelliJ EP.
8. Existing semantic nav proof tests still pass.

## Tests

Add focused tests under `igniter-jetbrains-plugin/src/test/...`.

Required:

- planner test over `fixtures/add.igapp`;
- empty model test;
- no-duplicate-explicit-type policy test;
- provider/wiring test if feasible without `runIde`; otherwise document the
  substitution and prove the adapter compiles.

Do not use reflection to test private methods; extract a small internal helper
instead.

## Verification

Required:

```bash
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks
```

Report:

- total test count;
- whether any live compiler proof tests were skipped;
- whether the inlay provider test is headless or compile-only;
- what remains unproven without `runIde`.

## Deliverables

- Implementation files for planner/provider.
- Tests and/or documented headless substitution.
- Proof doc:
  `lab-docs/lang/lab-jetbrains-inlay-type-hints-p2-v0.md`
- Close this card with exact verification output.
- Optional README one-liner only if it helps route future agents.

## Closed surfaces

Do not do these in P2:

- No new language semantics.
- No compiler changes.
- No `.ig` syntax changes.
- No Marketplace/product-readiness claim.
- No new navigation actions.
- No broad settings UI.
- No noisy hints for every token.
- No regex-inferred type hints.
- No compile-on-EDT path.

## Next route after P2

If P2 closes cleanly, likely next cards:

- `LAB-JETBRAINS-DIAGNOSTIC-QUICKFIX-P3` — proof-local quick fixes for a small
  safe diagnostic class.
- `LAB-JETBRAINS-RUNIDE-SMOKE-P3` — optional GUI smoke for Ctrl+Click + inlays,
  if/when a runIde workflow is worth the cost.

Do not start either route here.

---

## Closing report (2026-06-17)

```text
cd igniter-jetbrains-plugin
./gradlew test --rerun-tasks  -> BUILD SUCCESSFUL, 20 tests, 0 failures, 0 skipped
```

- **Total tests:** 20 (was 14 after P1; +6 `hints.IgniterTypeHintPlannerTest`).
- **Live compiler proof tests skipped?** No — `IgniterLiveCompilerProofTest` ran 2/2 (binary
  resolved via relative path); P1 model/report/nav tests still green (acceptance 8).
- **Inlay provider test:** compile-only (documented substitution). The IntelliJ provider needs
  the runtime (PsiFile/editor/sink); proven by `compileKotlin` against the real declarative API +
  EP registration; policy fully covered by the pure planner tests.
- **Unproven without runIde:** actual on-screen inlay rendering / settings toggle / live refresh.

**Implementation:** `hints/IgniterTypeHintPlanner` (pure policy: compute-only, type from
`SymbolNode.type`, deterministic, fail-closed) + `hints/IgniterTypeInlayProvider` (declarative
`InlayHintsProvider`/`OwnBypassCollector`, cache-only — no compile on EDT). EP verified against
the 2023.3 SDK (name `codeInsight.declarativeInlayProvider`, attribute names match the platform
bean, `TYPES_GROUP` enum confirmed). Acceptance 1–8 met. No compiler/`.ig`/semantics changes; no
new actions; no regex-inferred hints.
