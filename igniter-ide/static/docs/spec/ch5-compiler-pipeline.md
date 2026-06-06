# Ch5: Compiler Pipeline

Source PROPs: PROP-018, PROP-019.1, PROP-027, PROP-028, PROP-038
Status: synced after `CompilerOrchestrator` switched to `emit_typed` (S3-R5-C4)
and after R84 accepted the PROP-038 internal-only strict-refusal foundation

Primary evidence:

- `docs/tracks/typed-emission-stage2-source-lowering-parity-v0.md`
- `docs/tracks/bihistory-source-fixture-parity-gate-v0.md`
- `docs/tracks/orchestrator-emit-typed-switch-v0.md`
- `experiments/production_compiler_cli/`
- `experiments/stage1_close_candidate/`
- `experiments/stage2_close_candidate/`
- `docs/gates/prop038-strict-refusal-live-implementation-acceptance-decision-v0.md`
- `docs/tracks/prop038-strict-refusal-live-implementation-v0.md`
- `experiments/prop038_strict_refusal_live_implementation_proof/`

---

## 5.1 Production Pipeline

Public compilation now routes through the typed SemanticIR emission path:

```text
source.ig
  ���
  ��� Stage 0: Parse
  ParsedProgram
  ���
  ��� Stage 1: Classify
  ClassifiedProgram
  ���
  ��� Stage 2: Typecheck
  TypedProgram
  ���
  ��� Stage 3: Emit
SemanticIREmitter.emit_typed(TypedProgram)
  ���
  ���
SemanticIRProgram            only on full success
CompilationReport            produced for decision/report evidence
  ���
  ������ PROP-038 internal strict terminal, if selected:
  ���    non-persisting CompilerResult refused | configuration_error
  ���    no sidecar, no report write, no .igapp, no assembler call
  ���
  ��� Stage 4: Assemble
.igapp/ directory
  ���
  ��� Stage 5: Load
  RuntimeMachine.load(path)
```

Key invariant:

```text
SemanticIRProgram is emitted only when CompilationReport.pass_result == "ok".
OOF contracts never appear in loadable SemanticIRProgram.
PROP-038 strict terminal paths keep report.pass_result == "ok" but skip
assembly because the internal orchestrator strict requirement decision path
selects a non-persisting terminal CompilerResult.
```

---

## 5.2 Stage Interfaces

| Stage | Production input | Output | Skips if |
|-------|------------------|--------|----------|
| Parse | source.ig | ParsedProgram | parse error -> OOF/error report |
| Classify | ParsedProgram | ClassifiedProgram | parse error |
| Typecheck | ClassifiedProgram | TypedProgram | classify OOF |
| Emit | TypedProgram | SemanticIRProgram + CompilationReport | typecheck OOF |
| Internal strict terminal | CompilationReport + nested `compiler_profile_contract_validation` evidence | non-persisting CompilerResult `refused` / `configuration_error` | absent internal strict requirement |
| Assemble | CompilationReport + SemanticIRProgram | `.igapp/` | `pass_result != "ok"` or PROP-038 strict terminal selected |
| Load | `.igapp/` | LoadResult / CompatibilityReport | invalid manifest/report/contract |

`SemanticIREmitter#emit_typed(typed_program)` is the production emitter entry.
It is the only Stage 2+ lowering path used by `CompilerOrchestrator`.

### 5.2.1 PROP-038 Internal Strict Refusal Boundary

R84 accepts a bounded internal-only strict-refusal foundation for PROP-038.

Accepted compiler authority model:

```text
internal strict requirement source
  -> orchestrator-level strict requirement decision path
  -> report-only compiler_profile_contract_validation evidence
  -> non-persisting strict terminal CompilerResult when selected
```

The strict source is an internal constructor/test seam only. It is not exposed
through the public Ruby API, CLI, environment, config, manifest, loader/report,
CompatibilityReport, RuntimeMachine, Gate 3, runtime, or production behavior.

The validator remains evidence, not authority:

```text
CompilerProfileContractValidator output != refusal authority
compile_refusal_authorized: false remains nested report-only evidence
```

Accepted strict terminal statuses:

```text
refused
configuration_error
```

Both terminal statuses expose the same accepted 13-key public result shape:

```text
kind
format_version
status
program_id
source_path
source_hash
grammar_version
stages
igapp_path
contracts
compilation_report_path
diagnostics
warnings
```

Strict terminal behavior is non-persisting:

```text
report.pass_result == "ok"
compilation_report_path == null
igapp_path == null
no sidecar
no report write
no .igapp
no assembler call
```

This is a compiler/orchestrator boundary only. It does not add new parser,
TypeChecker, SemanticIR, assembler, loader/report, CompatibilityReport,
RuntimeMachine, Gate 3, runtime, or production authority.

---

## 5.3 Legacy Parsed Emitter

`SemanticIREmitter#emit(parsed_program, sample_input:)` remains available as a
Stage 1 legacy/internal comparison path.

It is retained for:

- Stage 1 golden comparison;
- direct parsed-emitter regression fixtures;
- historical parity harness evidence.

It is not the production `CompilerOrchestrator` path for Stage 2+ language
surfaces.

The legacy parsed path may OOF or omit Stage 2 nodes that the typed path lowers
correctly. That mismatch is now recorded as legacy parity delta evidence, not
as a blocker for the production compiler path.

---

## 5.4 Public Behavior Delta From S3-R5-C4

Before the orchestrator switch, public compile used parsed emission:

```text
Parser -> Classifier -> TypeChecker -> emit(parsed) -> Assembler
```

After S3-R5-C4, public compile uses typed emission:

```text
Parser -> Classifier -> TypeChecker -> emit_typed(typed) -> Assembler
```

This intentionally changes public behavior for valid Stage 2 surfaces:

| Surface | Before parsed production path | After typed production path |
|---------|-------------------------------|-----------------------------|
| OLAPPoint access | could OOF or emit no SemanticIR | lowers to `olap_access_node` |
| stream fold | could OOF or emit no SemanticIR | lowers to `stream_input_node`, `window_decl_node`, `fold_stream_node` |
| History access | could OOF or emit no SemanticIR | lowers to `temporal_input_node`, `temporal_access_node` |
| BiHistory access | proof-local / not source-comparable until gate | source fixture lowers to temporal nodes |
| invariant severity | parsed path missed typed invariant surfaces | typed path lowers invariant nodes/surfaces |

This is a correction toward the Stage 2 language, not a relaxation of OOF
rules. Invalid sources still stop before loadable SemanticIR.

One known public diagnostic category delta:

```text
negative unresolved symbol:
  before switch: classifier_oof
  after switch:  typechecker_oof
```

The compile still fails; the owning diagnostic stage is later because the typed
pipeline carries more structure before rejection.

---

## 5.5 Operator Name Resolution

Generic stdlib names are pre-resolution names. Before SemanticIR emission, the
TypeChecker resolves them to monomorphic forms:

```text
stdlib.numeric.add + Integer args  -> stdlib.integer.add
stdlib.numeric.add + Float args    -> stdlib.float.add
stdlib.numeric.add + Decimal[N]    -> stdlib.decimal.add
```

Unresolved generic operator names must not survive into loadable SemanticIR.
They are OOF before assembly.

---

## 5.6 Accepted Source Surfaces

The production pipeline currently accepts and lowers:

```text
CORE contracts: input, compute, output
Decimal types with scale annotation
TypeDecl structural records
module + import declarations
Collection[T] stdlib surfaces
History[T] and BiHistory[T] typed temporal access
stream T with bounded fold_stream
OLAPPoint point access
invariant severity declarations
expression-level if_expr v0 (TypeChecker + typed SemanticIR lowering; else required)
.igapp/ assembly for CORE / STREAM / TEMPORAL artifact surfaces
```

Still not canon or not production-executable:

```text
parser coordinate syntax for temporal reads remains unsettled
TEMPORAL RuntimeMachine evaluate is guarded/refused without approved support
production RuntimeMachine temporal cache is not enabled
Ledger / live TBackend read-write binding is not authorized
```

### 5.6.1 Expression-Level if_expr v0 (R190)

R190 accepts expression-level `if_expr` as internal compiler support:

```text
stage ownership:    TypeChecker (OOF-IF1..OOF-IF4) + typed SemanticIR lowering
parser shape:       existing; no new parser syntax
else required:      missing else produces OOF-IF2, not a parse error
condition:          must resolve to canonical Bool {"name":"Bool","params":[]}
branch types:       then/else must exact-match; mismatch produces OOF-IF3
value-producing:    each branch must have a final expression; empty block produces OOF-IF4
nested if_expr:     same rules apply recursively at every nesting level
deps policy:        TypeChecker union of condition + then + else deps
SemanticIR shape:   flat condition/then_branch/else_branch (see Ch6 ��6.10)
runtime/evaluator:  not in scope ��� lazy branch execution is not claimed
```

`if_expr` internal compiler support is not release evidence mutation, not public
demo/stable/all-grammar support, not runtime/evaluator support, and not Spark
support. The accepted release evidence (alpha 0.1.0.alpha.1) excludes `if_expr`
and remains unchanged.

---

## 5.7 Conformance Cases

Minimum conformance cases:

```text
C-1  Pure CORE contract -> SemanticIR fragment_class "core"
C-2  Decimal type annotation -> Decimal[N] propagated correctly
C-3  OOF unresolved symbol -> CompilationReport pass_result "oof" or "error"
C-4  OLAPPoint source -> typed path emits olap_access_node
C-5  stream fold source -> typed path emits stream_input/window/fold nodes
C-6  History source -> typed path emits temporal_input_node + temporal_access_node
C-7  BiHistory source -> typed path emits bitemporal temporal nodes
C-8  invariant severity source -> typed path emits invariant lowering
C-9  Assembler refuses non-ok reports and writes no loadable `.igapp/`
C-10 TEMPORAL `.igapp/` loads for inspection but evaluate is guarded/refused
C-11 PROP-038 internal strict terminal -> non-persisting CompilerResult,
     report.pass_result "ok", no sidecar/report/.igapp/assembler call
C-12 if_expr with Bool condition and matching branches -> TypeChecker accepted,
     typed SemanticIR emitted with flat condition/then_branch/else_branch node;
     non-Bool condition -> OOF-IF1; missing else -> OOF-IF2;
     branch type mismatch -> OOF-IF3; empty branch -> OOF-IF4
```

---

## 5.8 Evidence Notes

S3-R5-C4 switched production orchestration:

```ruby
classified = @classifier.classify(parsed, sample_input: resolved_sample_input)
typed = @typechecker.typecheck(classified)
compilation = @emitter.emit_typed(typed)
```

The previous parsed production call:

```ruby
compilation = @emitter.emit(parsed, sample_input: resolved_sample_input)
```

is now legacy/comparison behavior.

Proofs recorded for the switch:

```text
production_compiler_cli_proof: PASS
stage1_close_candidate: PASS
stage2_close_candidate: PASS
release-gate: PASS, publish not attempted
prop038_strict_refusal_live_implementation_proof: PASS
```
