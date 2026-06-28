# LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` compiler only. No `igniter-lang` canon change, no parser
syntax change, no VM/SIR schema change, no effect-summary change.
Depends-On: `lab-docs/lang/lab-igniter-compiler-type-ir-enum-p5-v0.md`
Closes: audit-control-board row **A19** follow-up **B-U1** (user-`def` call
arity/parameter soundness). Record-literal non-inline field (B-U3) stays open.

## What this slice did

Validated the call signature of every `Expr::Call` to an app-local user `def`,
using the P5 `IgType` structural boundary. Before this slice the typechecker
resolved a user `def` call **by name alone** and trusted its `return_type`
without checking argument arity or argument types, so a `def` could be called
with the wrong number of arguments or wrong argument types and still typecheck
clean.

## Live before-state (verified)

`typechecker.rs` `infer_expr`, `Expr::Call` arm — user-function resolution:

```rust
// Check user-defined functions
for f in functions {
    if f.name == *fn_name {
        is_resolved = true;
        resolved_type =
            self.type_ir(&serde_json::to_value(&f.return_type).unwrap());
        break;                // <-- arity & param types never checked
    }
}
```

The argument expressions were *already* inferred into `typed_args`
(`typed_args[i].resolved_type`) immediately above this loop, but those inferred
types were discarded — only the call's name was used. (Q1, Q2.)

`Param` carries the needed expected type: `Param { name: String,
type_annotation: TypeRef }` (`parser.rs:433`).

The P5 typed boundary was already in place and `pub(crate)`:
`IgType::structurally_assignable` plus the delegating helpers
`self.type_ir`, `self.structurally_assignable`, `self.type_display`,
`self.unknown_or_unknown_bearing` (all over the public `{name, params}` JSON).

## Change

One new private method `check_user_fn_call_signature`, called at the resolution
site after `resolved_type` is set (return type still resolved first, so a
signature fault does not cascade into "unknown function"):

1. **Arity** — `args.len() != f.params.len()` → `OOF-TY0`
   `"Call to '<fn>': expected N argument(s), got M"`. Param-type checks are then
   skipped (positional checks would be meaningless).
2. **Parameter type** — for each param, compare the argument's inferred type
   (`typed_args[i].resolved_type`) against the declared
   `param.type_annotation` via `structurally_assignable`. A fault emits
   `OOF-TY0` `"Call to '<fn>': parameter '<p>' expects <T>, got <U>"`.

A parameter is checked **only when both** the declared and inferred types are
concrete (not Unknown-bearing). This mirrors the P5 variant-field path and the
typed-binding path `(c)`: the checker never faults on an inference gap, only on a
real concrete mismatch. (Q4: generic parameters are handled — `IgType` compares
params structurally, so `Collection[Integer]` ≠ `Collection[Text]` falls out for
free; no concrete-only restriction was needed.)

## Exact diagnostics added

| Fault | Rule | Message |
|---|---|---|
| wrong arity | `OOF-TY0` | `Call to 'add': expected 2 arguments, got 1` |
| wrong param type (named) | `OOF-TY0` | `Call to 'need_float': parameter 'a' expects Float, got Text` |
| wrong param type (generic) | `OOF-TY0` | `Call to 'take_text_col': parameter 'xs' expects Collection[Text], got Collection[Integer]` |

`OOF-TY0` is the established type-soundness code (binding/output boundaries use
it), so `pass_result` and existing CI keying are unchanged. (Q3.)

## Tests proving before/after behavior

New `tests/user_fn_signature_check_tests.rs` (6):

- `wrong_arity_too_many_args_is_oof_ty0` — 1-param def called with 2 args.
- `wrong_arity_too_few_args_is_oof_ty0` — 2-param def called with 1 arg.
- `wrong_named_param_type_is_oof_ty0` — `Text` into a `Float` param.
- `wrong_generic_param_type_is_oof_ty0` — `Collection[Integer]` into a
  `Collection[Text]` param (structural, via the P5 boundary).
- `valid_named_call_is_clean` — correct arity + types → no `OOF-TY0`.
- `valid_generic_call_is_clean` — matching `Collection[Text]` arg → no
  `OOF-TY0` (proves no over-tightening on generics).

Guards held green:

- `variant_field_generic_param_tests` (P5) — 2 passed.
- `effect_summary_interprocedural_tests` (P6 effect-summary) — 7 passed
  (the other call-graph slice is undisturbed).

## Intentionally deferred call surfaces

- **stdlib call signatures** — `infer_stdlib_call` keeps its own per-builtin
  argument handling; not retargeted here.
- **`call_contract("Name", …)`** literal-callee argument checking against the
  contract registry — separate surface, not in scope.
- **Sealed constructors** (`some/none/ok/err`) — handled before the user-fn path
  by `infer_sealed_construct`; unchanged.
- **`recur(...)`** — handled by the recursion arms; unchanged.
- **Return-type → use-site assignability beyond the existing binding/output
  checks** — unchanged.
- **Unknown-bearing arguments** — deliberately not faulted (inference-gap
  tolerance), consistent with P5 and the typed-binding path.
- **Record-literal non-inline field comparison (A19 / B-U3)** — the remaining
  half of the P5 follow-up; still open.

## Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test user_fn_signature_check_tests        # 6 passed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test variant_field_generic_param_tests    # 2 passed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test effect_summary_interprocedural_tests # 7 passed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml                                              # all suites ok, 0 failed
git diff --check                                                                                          # clean
```

## Answers to the card's questions

1. **Where does `Expr::Call` resolve user-`def` signatures today?**
   `typechecker.rs` `infer_expr`, the user-function loop (resolves
   `f.return_type` by name only). The new check is inserted there.
2. **Does it evaluate all argument types before trusting `return_type`?** Yes —
   `typed_args` is fully inferred just above the loop; the values were simply
   unused. The new check consumes them.
3. **Diagnostic code consistent with existing type errors?** `OOF-TY0`.
4. **Generic parameters structural enough, or concrete-named only?** Structural —
   `IgType::structurally_assignable` compares params, so generics are covered;
   checking is gated on both-sides-concrete to avoid Unknown false positives.
5. **What remains unvalidated?** stdlib-call args, `call_contract` literal-callee
   args, Unknown-bearing args (by design), and the record-literal non-inline
   field path (B-U3).
