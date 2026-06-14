# LAB-NESTED-RECORD-LITERAL-TYPING-P1

**Status:** CLOSED — PROVED 60/60 — DIRECT RUBY TC FIX  
**Route:** LANG / Ruby TypeChecker / record literal inference  
**Date:** 2026-06-14  
**Authority:** compiler correctness proof; implementation only if bounded by proof

## Goal

Prove and route the Ruby TC nested record literal typing bug discovered during `LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1`.

Suspected root cause:

```ruby
fields.transform_values { |v| infer_expr(v, symbol_types, type_errors, node_name) }
```

`infer_record_literal` passes the outer `node_name` into field-value expressions. If the outer compute/output has a type hint, nested record literals can be validated against the outer type instead of their own structural candidate.

Observed app symptom:

- `vector_math` `Mat3` output expected fields `r0/r1/r2`.
- Inner Vec3 row literals use fields `x/y/z`.
- Ruby reported `missing required field: r0/r1/r2` and `unexpected field: x/y/z` on inner literals.
- App workaround: extract inner rows into annotated computes.

## Gate

Start after:

- `LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1` CLOSED.
- `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` and P5 are available as background context.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-vector-math-field-alignment-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vector_math_field_alignment_p1.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_math/mat3.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/record_literal_inference_proof/verify_record_literal_inference_p3.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/record_literal_inference_proof/verify_record_literal_inference_p4.rb`

## Questions

1. Can a minimal inline fixture reproduce the outer-hint leakage without app source complexity?
2. Does the bug only affect Ruby, or is there Rust parity risk?
3. Which call path passes the outer `node_name` into nested field-value record literals?
4. Should nested field-value expressions receive `nil` node context, a field-specific context, or an expected type context?
5. Does a fix preserve same-name output hints and annotated compute hints?
6. Does the fix preserve P3 structural matching and P5 empty-array field wildcard behavior?
7. Can `vector_math` return to direct nested literals after the fix, or should app workaround remain canonical?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/nested_record_literal_typing_proof/verify_nested_record_literal_typing_p1.rb`, target at least 45 checks.
- Lab/proposal doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/proposals/LAB-NESTED-RECORD-LITERAL-TYPING-P1-nested-record-hint-leakage-v0.md`.
- Optional narrow implementation in `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb` only if the proof isolates a safe one-file patch.
- Update this card with closure summary.
- Proposals README and portfolio updates after closure if implementation/proposal lands.

## Acceptance

- The proof distinguishes nested record hint leakage from ordinary missing-field errors.
- Any fix is one-file and does not relax output assignability.
- Existing record inference proofs still pass after any implementation.
- `vector_math` direct nested record fixture compiles cleanly if implementation is included.
- Closed surfaces remain closed.

## Closed Surfaces

- No optional-field semantics.
- No broad record-literal redesign.
- No Rust implementation unless a parity bug is proven.
- No app source migration in this card.
- No relaxation of `structurally_assignable?` at output boundaries.

## Findings

Root cause confirmed: `infer_record_literal` inferred field-value expressions
under the outer `node_name`. In a same-name output pattern (`compute result =
...`, `output result : Mat3`), inner Vec3 row literals inherited
`@output_type_hints["result"] = Mat3` and were validated as Mat3.

Minimal inline fixture reproduced the false diagnostics without app complexity:
direct nested Mat3 rows emitted false `missing required field: r0/r1/r2` and
`unexpected field: x/y/z` before the patch.

The safe fix was not `nil` context. A nil/silent structural fallback can hide
nested field mismatches by returning `Unknown`, which the outer hint path treats
as permissive. The accepted design is expected field context under a synthetic
field-node name such as `result.r0`.

## Implementation

One-file Ruby TypeChecker patch:

- Added `record_literal_field_node_name(node_name, field_name)`.
- Captured the outer hint before field-value inference.
- For nested record literal fields with known expected record type, temporarily
  installed `@output_type_hints[field_node_name] = expected_field_type`.
- Restored/deleted the temporary nested hint with `ensure`.
- Kept outer hint validation and output-boundary `structurally_assignable?`
  unchanged.

No parser, emitter, Rust, VM, app source, optional-field, or public-surface
changes.

## Answers

1. Yes: minimal inline direct Mat3 fixture reproduced the bug.
2. Ruby-specific implementation fix for this card. Rust keeps record literal
   validation in a separate compute-context path; no Rust patch was needed.
3. The leaking path was field-value inference inside `infer_record_literal`.
4. Nested field-value record literals now receive expected field type under a
   synthetic field-node context (`result.r0`), not nil and not a bare field name.
5. Same-name output hints and annotated compute hints are preserved.
6. P3 structural matching and P5 empty-array field wildcard behavior are
   preserved.
7. A direct nested `vector_math` Mat3 fixture now compiles cleanly. The app
   workaround may remain as source hygiene but is no longer required by Ruby TC
   for this shape.

## Deliverables

| Artefact | Path | Status |
| --- | --- | --- |
| Implementation | `igniter-lang/lib/igniter_lang/typechecker.rb` | one-file patch |
| Proof runner | `igniter-lang/experiments/nested_record_literal_typing_proof/verify_nested_record_literal_typing_p1.rb` | 60/60 PASS |
| Proposal packet | `igniter-lang/.agents/work/proposals/LAB-NESTED-RECORD-LITERAL-TYPING-P1-nested-record-hint-leakage-v0.md` | written |
| Proposals index | `igniter-lang/.agents/work/proposals/README.md` | updated |
| Portfolio checkpoint | `igniter-gov/portfolio/governance/2026-06-14-lang-nested-record-literal-typing-p1-v0.md` | written |
| This card | `igniter-lab/.agents/work/cards/lang/LAB-NESTED-RECORD-LITERAL-TYPING-P1.md` | closed |

## Proof Results

- `ruby experiments/nested_record_literal_typing_proof/verify_nested_record_literal_typing_p1.rb` — 60/60 PASS
- `ruby experiments/record_literal_inference_proof/verify_record_literal_inference_p3.rb` — 76/76 PASS
- `ruby experiments/record_literal_inference_proof/verify_record_literal_inference_p4.rb` — 29/29 PASS

## Acceptance Closure

- The proof distinguishes nested hint leakage from ordinary missing-field
  errors.
- The fix is one file and does not relax output assignability.
- Existing record inference proofs still pass.
- Direct nested vector_math-style Mat3 fixtures compile cleanly.
- Closed surfaces remain closed.
