# Lab Contract Invocation Forms SemanticIR Lowering Proof v0

Card: `S3-R254-C2-I`
Track: `contract-invocation-forms-semanticir-lowering-proof-v0`
Status: `done / proof-local-lab-only`
Date: 2026-06-05

## Authority Notice

This lab packet is proof-local frontier evidence only. It does not authorize
mainline parser, TypeChecker, SemanticIR, runtime, VM linker, API, CLI, package,
stable grammar, public API, `.igapp` execution, `.igbin` execution, compiler
passport emission, RuntimeSmoke productization, public runtime, Reference
Runtime, production, Spark, release, public demo, public performance,
official/reference, certification, portability, or lab-canon claims.

## Implementation Summary

Implemented inside `igniter-lab/igniter-compiler/**` only:

- resolved form sidecar entries now expose `lowering_target`;
- the emitter applies proof-local lowering after form resolution and before
  assembly;
- accepted resolved form expressions lower to the existing explicit `call`
  shape with `lowered_from_form` metadata;
- `runtime_dispatch_required=false`, `vm_linker_required=false`, and
  `stable_semanticir_node=false` are recorded on lowered nodes;
- ambiguous, unresolved, and `no_form` cases remain `oof` and do not produce
  accepted `.igapp` output;
- explicit calls and primitive pass-through remain separate from form lowering.

Lowering target is intentionally not canonical vocabulary. The proof uses the
existing `call` expression shape plus metadata:

```json
{
  "kind": "call",
  "fn": "AddInteger",
  "lowered_from_form": {
    "authority": "proof_local_lab_only",
    "trigger": "+",
    "runtime_dispatch_required": false,
    "vm_linker_required": false,
    "stable_semanticir_node": false
  }
}
```

## Result Packet

Summary JSON:

```text
igniter-lab/igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/summary.json
```

Status: `PASS`.

## Command Matrix

| Command | Result |
| --- | --- |
| `cargo test` | PASS |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/positive.ig --out out/contract_invocation_forms_semanticir_lowering_proof/positive.igapp` | PASS / `ok` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/concat_separate.ig --out out/contract_invocation_forms_semanticir_lowering_proof/concat_separate.igapp` | PASS / `ok` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/explicit_call.ig --out out/contract_invocation_forms_semanticir_lowering_proof/explicit_call.igapp` | PASS / `ok` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/ambiguity.ig --out out/contract_invocation_forms_semanticir_lowering_proof/ambiguity.igapp` | PASS / expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/declaration_order.ig --out out/contract_invocation_forms_semanticir_lowering_proof/declaration_order.igapp` | PASS / expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/unresolved.ig --out out/contract_invocation_forms_semanticir_lowering_proof/unresolved.igapp` | PASS / expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/no_form.ig --out out/contract_invocation_forms_semanticir_lowering_proof/no_form.igapp` | PASS / expected `oof` |
| `cargo run --quiet -- compile fixtures/forms/semanticir_lowering/primitive_pass_through.ig --out out/contract_invocation_forms_semanticir_lowering_proof/primitive_pass_through.igapp` | PASS / `ok` |
| `ruby proofs/contract_invocation_forms_type_directed_dispatch_proof.rb` | PASS / R252 regression |
| `ruby proofs/contract_invocation_forms_semanticir_lowering_proof.rb` | PASS / summary generated |

Cargo emitted existing warning noise; no command failed outside the expected
`oof` negative cases.

## FSL Matrix

| ID | Status | Evidence |
| --- | --- | --- |
| FSL-1 | PASS | Lowering target is documented as explicit `call` with proof-local metadata. |
| FSL-2 | PASS | R252 typed dispatch evidence is reused through sidecar `typed_operands`, `resolved_to`, `form_id`, and `lowering_target`. |
| FSL-3 | PASS | Resolved Integer `+` lowers to `fn: AddInteger`. |
| FSL-4 | PASS | Resolved `++` lowers to `fn: ConcatString`, separate from `+`. |
| FSL-5 | PASS | Explicit `length(...)` call bypasses form lowering. |
| FSL-6 | PASS | `E-FORM-AMBIG` remains hard error with no accepted lowered output. |
| FSL-7 | PASS | Declaration order remains ambiguous; no lowered winner is selected. |
| FSL-8 | PASS | `unresolved_form_error` emits `E-FORM-UNRESOLVED` and no lowered output. |
| FSL-9 | PASS | `no_form` remains fail-closed with no accepted lowered output. |
| FSL-10 | PASS | Primitive `-` remains `binary_op`, not form lowering. |
| FSL-11 | PASS | Sidecar trace links source form, selected candidate, and lowered target. |
| FSL-12 | PASS | Resolved form invocation nodes contain no generic `binary_op`. |
| FSL-13 | PASS | Lowered nodes do not require runtime form dispatch. |
| FSL-14 | PASS | VM linker and subroutine frames remain deferred. |
| FSL-15 | PASS | Import hiding/overriding remains held. |
| FSL-16 | PASS | Closed-surface scan recorded no mainline or forbidden lab widening. |

## Changed Files

- `igniter-lab/igniter-compiler/src/form_resolver.rs`
- `igniter-lab/igniter-compiler/src/emitter.rs`
- `igniter-lab/igniter-compiler/src/main.rs`
- `igniter-lab/igniter-compiler/fixtures/forms/semanticir_lowering/*.ig`
- `igniter-lab/igniter-compiler/proofs/contract_invocation_forms_semanticir_lowering_proof.rb`
- `igniter-lab/igniter-compiler/out/contract_invocation_forms_semanticir_lowering_proof/**`
- `igniter-lab/lab-docs/lab-contract-invocation-forms-semanticir-lowering-proof-v0.md`
- `igniter-lang/docs/tracks/contract-invocation-forms-semanticir-lowering-proof-v0.md`

## Held Gap

Import hiding/overriding remains held. It was not proven or wired by this
proof.

## Recommendation

Ready for pressure review / acceptance as proof-local lab-frontier evidence.
Keep live mainline implementation and runtime/public authority closed.
