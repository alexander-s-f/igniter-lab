# Lab Contract Invocation Forms Type-Directed Dispatch Proof v0

Date: 2026-06-05
Card: S3-R252-C2-I
Track: contract-invocation-forms-type-directed-dispatch-proof-v0
Status: complete
Result: PASS

Lab-local frontier evidence only. This proof does not claim canonical syntax,
stable grammar, mainline parser/TypeChecker/SemanticIR support, runtime support,
VM linker support, public API, production readiness, release evidence,
performance evidence, certification, portability, or lab behavior as canon.

---

## Done

Implemented proof-local type-directed dispatch in the lab compiler sidecar
resolver:

- `FormResolver` now reads typed contract symbols and reconstructs local
  expression operand facts for sidecar resolution.
- Form trace events now include `typed_operands`, optional `typed_result`,
  `filter_status`, and `refused_candidates`.
- Registered candidates are filtered against typed operand facts before
  selection.
- If a trigger exists but no typed candidate survives, the resolver emits
  `E-FORM-UNRESOLVED` plus trace kind `unresolved_form_error`.
- Ambiguity still refuses after filtering with `E-FORM-AMBIG` and no winner.
- `no_form` remains fail-closed before typed candidate selection.
- Explicit calls remain trace-visible and bypass form resolution.
- `++` has a lab-local type fact so it can be proven as separate from `+`.

No SemanticIR lowering was added. Form evidence remains sidecar-only.

---

## Changed Files

- `igniter-lab/igniter-compiler/src/form_resolver.rs`
- `igniter-lab/igniter-compiler/src/typechecker.rs`
- `igniter-lab/igniter-compiler/fixtures/forms/type_dispatch/*.ig`
- `igniter-lab/igniter-compiler/proofs/contract_invocation_forms_type_directed_dispatch_proof.rb`
- `igniter-lab/igniter-compiler/out/contract_invocation_forms_type_directed_dispatch_proof/**`
- `igniter-lab/lab-docs/lab-contract-invocation-forms-type-directed-dispatch-proof-v0.md`
- `igniter-lang/docs/tracks/contract-invocation-forms-type-directed-dispatch-proof-v0.md`

---

## Command Matrix

| Command | Result |
| --- | --- |
| `cargo test` | PASS; 0 tests, compile ok, existing warnings only |
| `cargo run -- compile fixtures/forms/type_dispatch/positive.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/positive.igapp` | PASS; status `ok` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/non_additive_plus.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/non_additive_plus.igapp` | PASS; expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/concat_separate.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/concat_separate.igapp` | PASS; status `ok` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/ambiguity.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/ambiguity.igapp` | PASS; expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/declaration_order.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/declaration_order.igapp` | PASS; expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/missing_trigger.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/missing_trigger.igapp` | PASS; status `ok` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/no_form.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/no_form.igapp` | PASS; expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/type_dispatch/generic_additive.ig --out out/contract_invocation_forms_type_directed_dispatch_proof/generic_additive.igapp` | PASS; status `ok` |
| `ruby proofs/contract_invocation_forms_type_directed_dispatch_proof.rb` | PASS; summary generated |

Summary:

- `igniter-lab/igniter-compiler/out/contract_invocation_forms_type_directed_dispatch_proof/summary.json`

---

## FTD Matrix

| ID | Result | Evidence |
| --- | --- | --- |
| FTD-1 | PASS | `UseIntegerAdd::total` trace exposes `typed_operands: [Integer, Integer]`. |
| FTD-2 | PASS | Integer `+` resolves to `AddInteger`. |
| FTD-3 | PASS | String `+` records `unresolved_form_error` with refused `AddInteger`. |
| FTD-4 | PASS | `++` resolves to `ConcatString` and remains distinct from `+`. |
| FTD-5 | PASS | Equal surviving candidates emit `E-FORM-AMBIG`, no resolved form. |
| FTD-6 | PASS | Declaration-order fixture emits `E-FORM-AMBIG`; first declaration is not selected. |
| FTD-7 | PASS | Known primitive `-` with no form remains `primitive_pass_through`. |
| FTD-8 | PASS | Registered `+` with no surviving typed candidate emits `E-FORM-UNRESOLVED` and trace kind `unresolved_form_error`. |
| FTD-9 | PASS | `no_form` remains `blocked_no_form` after type facts are available. |
| FTD-10 | PASS | `length(...)` emits `explicit_call_bypass`. |
| FTD-11 | PASS | Sidecars record selected, missed/pass-through, refused, and blocked candidates. |
| FTD-12 | PASS | SemanticIR contains no `ContractInvocation` / `contract_invocation` lowering. |

---

## Status Notes

| Topic | Status |
| --- | --- |
| Typed-expression source | Proof-local lab source: `TypedContract.symbols` plus local expression reconstruction inside `FormResolver`. |
| Trait/generic filtering | PASS: `Add[T: Additive]` specializes to `Add[Integer]`; no `Additive[String]` authority is claimed. |
| Ambiguity | `E-FORM-AMBIG` remains hard error after type filtering. |
| Declaration order | Never selects winner. Equal typed candidates refuse. |
| Primitive pass-through | Known primitives without form registration remain pass-through by policy. |
| `unresolved_form_error` | Implemented proof-local with `E-FORM-UNRESOLVED` and refused candidate evidence. |
| Import hiding/overriding | Held gap. Lab parses this surface but this proof does not wire scope filtering. |
| Sidecar artifacts | Evidence only: `form_table.json` and `form_resolution_trace.json`. |
| SemanticIR/runtime | Closed. No lowering, VM linker, runtime dispatch, `.igapp` execution, or `.igbin` execution authority. |

---

## Recommendation

Accept this as proof-local lab-frontier evidence for type-directed form
dispatch. Keep mainline implementation and runtime authority closed. Next route
may pressure-review whether this evidence is sufficient to open a later bounded
SemanticIR-lowering design/review, with import hiding/overriding still recorded
as a held gap.
