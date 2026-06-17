# Card: LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1 — prove compiler-backed semantic navigation

> Evidence/proof card for the recently added JetBrains semantic navigation layer.
> The implementation exists; this card must prove it against real compiler artifacts
> and fixtures without widening IDE surface.

**Status:** CLOSED (2026-06-17). Proof: `lab-docs/lang/lab-jetbrains-semantic-nav-proof-p1-v0.md`.  
**Skill:** `idd-agent-protocol` (verify-first, evidence is not authority).  
**Lane:** proof/evidence with narrowly scoped test/support changes only.

## Why this card exists

The JetBrains plugin now has a compiler-backed semantic model and navigation surface:

```text
IgniterModelService
IgniterModel / SymbolNode
IgniterExternalAnnotator via shared analysis cache
IgniterGotoDeclarationHandler
IgniterGotoSymbolContributor
JumpToSemanticIRNodeAction
FindIgniterDependentsAction
```

The code builds, but current Gradle output says `test NO-SOURCE`. That means the
surface is not yet proof-anchored. This card closes that gap.

Goal:

```text
Prove the semantic navigation model on real .ig fixture(s) and real compiler
artifacts, without adding new IDE features.
```

## Verify-first inputs

Read these before changing anything:

- `igniter-jetbrains-plugin/build.gradle.kts`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/compiler/IgniterCompilerService.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModel.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/model/IgniterModelService.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/navigation/IgniterGotoDeclarationHandler.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/navigation/IgniterGotoSymbolContributor.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/actions/JumpToSemanticIRNodeAction.kt`
- `igniter-jetbrains-plugin/src/main/kotlin/com/igniter/plugin/actions/FindIgniterDependentsAction.kt`
- `igniter-jetbrains-plugin/src/main/resources/META-INF/plugin.xml`

Then run:

```bash
cd igniter-jetbrains-plugin
./gradlew test
```

Record the baseline. If it is still `NO-SOURCE`, that is the proof gap to close.

## Authority / boundaries

- JetBrains plugin is lab tooling, not language authority.
- Compiler artifacts (`compilation_report.json`, `sourcemap.json`,
  `semantic_ir_program.json`) decide the semantic model.
- Regex/index-only surfaces may support project-wide discovery, but semantic
  navigation must be compiler-backed where it claims to be.
- Do not change `igniter-compiler`, `.ig` language semantics, or plugin product scope.

## Deliverables

1. Add focused tests and/or proof fixtures under `igniter-jetbrains-plugin/src/test/...`.
2. Add a short proof doc:

   ```text
   lab-docs/lang/lab-jetbrains-semantic-nav-proof-p1-v0.md
   ```

3. Close/update this card with the exact verification commands and counts.

Optional only if useful: add a one-line README note that semantic nav has a proof
card. Do not rewrite plugin docs broadly.

## Preferred proof shape

Use the smallest reliable route. Preferred order:

1. **Plugin tests** using IntelliJ test framework if straightforward.
2. If full IntelliJ fixtures are too heavy, add proof-local Kotlin/JVM tests for
   the model/artifact parsing plus a documented Gradle build check.
3. If private methods block testing, extract tiny pure helpers rather than
   testing by reflection. Keep helpers internal and local to plugin model code.

Do not add production behavior just to make testing easy.

## Required fixture

Use one small `.ig` source that exercises:

```text
contract Add
input a
input b
compute sum = a + b
output result = sum
```

or the nearest syntax accepted by the live lab compiler. The fixture must compile
with the current `igniter_compiler` and produce:

- `compilation_report.json`;
- `sourcemap.json`;
- `semantic_ir_program.json`.

The proof may write outputs to a temp directory.

## Required checks

### A. Compiler service / artifact layout

- Resolves `igniter_compiler` through configured path, PATH, or env route used by the test.
- Invokes `igniter_compiler compile SOURCE --out OUT.igapp`.
- Finds report in both expected layouts where possible:
  - success: inside `.igapp`;
  - refusal: sibling `.compilation_report.json`.
- Parses diagnostics by `rule`, `severity`, `message`, and `span`/top-level line.

### B. Semantic model

- `IgniterModelService` / model parser yields symbols for contract, inputs,
  compute, and output.
- Symbols include:
  - `nodeId`;
  - `kind`;
  - `name`;
  - `contract`;
  - source line/col when sourcemap provides it;
  - type when semantic IR provides it;
  - deps for compute/output nodes where present.
- `resolveRef("a", "Add")` resolves to the input declaration, not a random symbol.
- `usagesOf("a", "Add")` returns the dependent compute/output node(s).
- Empty/failed compile degrades to `IgniterModel.EMPTY`, not guessed regex semantics.

### C. Navigation behavior

Prove as much as possible in tests; if one item is impossible in headless tests,
document why and prove the underlying pure function / model result instead.

- Go-to declaration uses cached semantic analysis and does not spawn compiler on EDT.
- Go-to declaration from a reference resolves to the declaration offset.
- Go-to symbol contributor lists qualified keys (`contract:Add`, etc.) from
  `IgniterSymbolIndex` and navigates to offsets.
- Jump-to-SIR locates the selected `node_id` in `semantic_ir_program.json`.
- Find dependents reports nodes whose semantic IR `deps` include the target name.

### D. Annotator behavior

- External annotator goes through `IgniterModelService` analysis, not a separate
  compiler path.
- It uses editor text / unsaved text where the test framework can prove it.
- Diagnostics map to annotations with the expected severity.

## Acceptance

- `./gradlew test` is no longer `NO-SOURCE`; it runs at least one focused test class.
- Tests/proof are based on real current compiler artifacts or a fixture generated
  by the live `igniter_compiler`, not hard-coded folklore.
- Semantic model checks cover symbols, deps, types, and source locations.
- Navigation checks cover go-to, SIR jump, dependents, and symbol index either
  directly or through documented underlying model/index assertions.
- Failure/empty-model path is fail-closed.
- No new IDE feature surface.
- No language/compiler changes.
- No broad README rewrite.

## Closed surfaces

- Do not add new actions.
- Do not build a visual UI.
- Do not change `.ig` syntax.
- Do not widen dynamic dispatch policy.
- Do not treat regex index results as semantic authority.
- Do not require a live external service or network.

## Expected final report

The closing response/card should include:

```text
./gradlew test -> BUILD SUCCESSFUL, N tests
fixture source path
generated artifact path or temp strategy
what was proven
what remains intentionally unproven
```

If IntelliJ fixture testing proves too costly, the card may close only if the
doc explicitly says what was substituted and why the substituted proof still
covers the semantic contract.

---

## Closing report (2026-06-17)

```text
cd igniter-jetbrains-plugin
./gradlew test --offline   -> BUILD SUCCESSFUL, 14 tests, 0 failures, 0 skipped
  (baseline before this card: `test NO-SOURCE`)
```

- **Test classes (3):** `model.IgniterModelParserTest` (8), `compiler.IgniterReportParserTest` (4),
  `IgniterLiveCompilerProofTest` (2 — live, Assume-skips if the binary is absent).
- **Fixture source:** `src/test/resources/fixtures/add.ig` (contract Add; inputs a,b: Integer;
  compute sum = a + b; output sum: Integer — live-compiler-accepted CORE).
- **Artifacts:** committed real `fixtures/add.igapp/{sourcemap,semantic_ir_program,compilation_report}.json`
  + refusal `fixtures/bad.compilation_report.json`; live test writes fresh artifacts to a temp dir.

**What was proven:** semantic model join (sourcemap × SIR by node_id → symbols with
kind/name/contract/type/line·col/deps), `resolveRef`/`usagesOf`/`enclosingContract`,
EMPTY fail-closed on no artifacts; diagnostics by `rule`/`severity`/top-level-line & span;
live success layout (report+sourcemap+SIR inside `.igapp`) and refusal sibling report.

**Substitution (allowed by card):** to make the join/parse testable without an IDE fixture,
the pure logic was extracted into `model/IgniterModelParser` and `compiler/IgniterReportParser`
(IntelliJ services now delegate; no behaviour change, no new feature surface).

**Intentionally unproven:** live IntelliJ UI gestures (Ctrl+Click goto, ChooseByName Go-to-Symbol
dialog, jump-to-SIR / find-dependents popups) — proven at the underlying pure-function/model level
+ `compileKotlin` EP wiring; full E2E needs `runIde` (GUI), out of this lane.
