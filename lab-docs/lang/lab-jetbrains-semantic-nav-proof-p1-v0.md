# lab-jetbrains-semantic-nav-proof-p1-v0

Proof doc for card `LAB-JETBRAINS-SEMANTIC-NAV-PROOF-P1` — prove the JetBrains
plugin's compiler-backed semantic navigation against real `igniter_compiler`
artifacts, without widening IDE surface.

**Status:** CLOSED. **Skill:** idd-agent-protocol (verify-first; evidence is not authority).

## What was proven

The plugin's semantic layer (model + navigation) is now anchored by focused JVM
tests that run against REAL compiler artifacts — closing the prior `test NO-SOURCE`
gap. The semantic join and diagnostic parsing were extracted into pure,
IntelliJ-free helpers so they are testable without an IDE fixture:

- `model/IgniterModelParser` — joins `sourcemap.json` (position + sir_path) with
  `semantic_ir_program.json` (type + deps) by `node_id` into `IgniterModel`.
- `compiler/IgniterReportParser` — parses `compilation_report.json` diagnostics.

The IntelliJ services (`IgniterModelService`, `IgniterCompilerService`) now delegate
to these helpers; behaviour is unchanged.

## Verification

```bash
cd igniter-jetbrains-plugin
./gradlew test --offline        # was NO-SOURCE; now runs 3 classes
# -> BUILD SUCCESSFUL, 14 tests, 0 failures, 0 skipped
```

`IGNITER_LAB_HOME` (or a built sibling `../igniter-compiler/target/{release,debug}/igniter_compiler`)
lets the live class run; without it those 2 tests Assume-skip and the other 12 still pass.

### Test classes / counts

| Class | Tests | Covers (card check) |
|---|---|---|
| `model.IgniterModelParserTest` | 8 | B — symbols (contract/input/compute/output), nodeId/kind/name/contract, type, line/col, deps; `resolveRef`; `usagesOf`; `enclosingContract`; EMPTY on no artifacts |
| `compiler.IgniterReportParserTest` | 4 | A — diagnostics by `rule`/`severity`, top-level `line` (Rust) and nested `span` (Ruby/typecheck); success=empty; malformed→empty |
| `IgniterLiveCompilerProofTest` | 2 | A live + layouts — live compile success (report+sourcemap+SIR inside `.igapp`, model non-empty, `compute:Add.sum` deps `[a,b]` type `Integer`) and refusal (sibling `*.compilation_report.json` with parseable `OOF-*`) |

### Fixture

`src/test/resources/fixtures/add.ig`, compiled by the live `igniter_compiler`:

```
module Lang.Examples.Add
contract Add {
  input  a: Integer
  input  b: Integer
  compute sum = a + b
  output sum: Integer
}
```

Committed artifacts: `fixtures/add.igapp/{sourcemap,semantic_ir_program,compilation_report}.json`
and a refusal report `fixtures/bad.compilation_report.json`. Real symbol model:
`contract:Add @3:10`, `input:Add.a @4:3` Integer, `input:Add.b @5:3` Integer,
`compute:Add.sum @7:3` Integer deps `[a,b]`, `output:Add.sum @9:3`.

## What remains intentionally unproven (substituted)

Headless JVM tests cannot exercise live IntelliJ UI gestures. These are proven at
the underlying pure-function / model level instead, and by `compileKotlin` for the
EP wiring:

- **Go-to-declaration** (`IgniterGotoDeclarationHandler`): the resolution core
  (`resolveRef` + `enclosingContract`) is tested; the Ctrl+Click EP and EDT
  cache-only contract are proven by construction (uses `cached(...)`, never compiles
  on EDT) + compile.
- **Go to Symbol** (`IgniterGotoSymbolContributor`): index-backed; the IntelliJ
  `ChooseByName` dialog is not driven in tests.
- **Jump-to-SIR** / **Find dependents** actions: the underlying locate (`node_id` in
  SIR) and `usagesOf` are tested; the action/popup UI is not.

These need `runIde` (GUI) to verify end-to-end and are out of this proof card's lane.

## Boundaries honoured

No new IDE feature surface; no `igniter-compiler` / `.ig` semantics changes; no broad
doc rewrite; no network/live service. Regex index used only for cross-file discovery,
never as semantic authority (semantic model is compiler-backed). Empty/failed compile
degrades to `IgniterModel.EMPTY` (fail-closed), asserted by test.
