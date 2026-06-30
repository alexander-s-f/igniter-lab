# LAB-IGNITER-COMPILER-ARRAY-LITERAL-ELEMENT-TYPING-P9 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` Rust compiler only. No `igniter-lang` canon change, no
parser syntax change, no SIR schema change, no Ruby/canon code, no VM/runtime
or collection stdlib semantic change.
Depends-On: `lab-igniter-compiler-type-ir-enum-p5-v0.md`,
`lab-igniter-compiler-user-fn-signature-check-p6-v0.md`,
`lab-igniter-compiler-record-literal-noninline-field-typing-p7-v0.md`,
`lab-igniter-compiler-call-contract-arg-typing-p8-v0.md`

## What this slice did

Closed the remaining A19 collection-element typing tail in
`lang/igniter-compiler/src/typechecker.rs`:
`check_array_literal_shape` now validates non-record array literal elements via
the existing P5 `IgType` structural assignability boundary.

Before this slice, non-record elements used a string-name compare:

```rust
if actual_type != elem_type_name && actual_type != "Unknown" { ... }
```

After this slice, the same v0 `Ref` / `Literal` element scope is retained, but
the inferred element type is full type IR and the comparison is structural:

```rust
if !unknown_or_unknown_bearing(actual)
    && !unknown_or_unknown_bearing(expected)
    && !structurally_assignable(actual, expected) { ... }
```

This means `Collection[Integer]` vs `Collection[Text]` style parameter mistakes
are no longer erased by outer-name comparison, and `String`/`Text` aliasing is
inherited from `IgType::structurally_assignable` rather than reimplemented in
the array path.

The old name-only helper `infer_field_expr_type` was removed. Its full-IR
sibling `infer_field_expr_type_ir` is now the shared helper for record-field and
array-element checks.

## Code Path Changed

- `lang/igniter-compiler/src/typechecker.rs`
  - `check_array_literal_shape`, non-record `_` element arm.
  - `infer_field_expr_type_ir` comment updated to document record-field plus
    array-element usage.

No parser, SIR emitter, VM, runtime, stdlib, or `igniter-lang` files changed.

## Before / After Examples

| Example | Result |
| --- | --- |
| `compute xs : Collection[Integer] = [1, 2]` | compiles |
| `compute xs : Collection[Integer] = [1, "x"]` | `OOF-TY0`, expected `Integer`, got `String` |
| `compute xs : Collection[Text] = ["a", "b"]` | compiles through `IgType` `String` -> `Text` canonicalization |
| `compute rows : Collection[Row] = [{ id: "a", n: 1 }]` | compiles; record literal still checked against `Row` |
| `compute rows : Collection[Row] = [{ id: "a", n: "x" }]` | `OOF-TY0`, record field `n` expects `Integer`, got `String` |
| `compute xs : Collection[Integer] = [a + b]` | compiles; complex element expression remains deferred/permissive in v0 |

## Regression Matrix

New regression file:

- `lang/igniter-compiler/tests/array_literal_element_typing_tests.rs`
  - `collection_integer_array_literal_compiles`
  - `mixed_scalar_array_literal_fails_closed`
  - `string_literals_are_assignable_to_collection_text`
  - `record_element_array_literal_compiles`
  - `wrong_record_field_type_inside_array_literal_fails_closed`
  - `complex_element_expression_remains_deferred`

Existing guards kept green:

- `collection_comprehension_tests` for ordinary and empty array literal
  behavior.
- `user_fn_signature_check_tests` (P6).
- `record_literal_generic_field_tests` (P7).
- `call_contract_arg_typing_tests` (P8).
- `type_ir` unit tests for the structural boundary itself.
- Full `igniter-compiler` suite.

## Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo fmt --manifest-path lang/igniter-compiler/Cargo.toml
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test array_literal_element_typing_tests -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test collection_comprehension_tests -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test user_fn_signature_check_tests -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test record_literal_generic_field_tests -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test call_contract_arg_typing_tests -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --lib type_ir -- --nocapture
cargo test --manifest-path lang/igniter-compiler/Cargo.toml
git diff --check
```

Results:

- `array_literal_element_typing_tests`: 6 passed.
- `collection_comprehension_tests`: 10 passed.
- `user_fn_signature_check_tests`: 6 passed.
- `record_literal_generic_field_tests`: 4 passed.
- `call_contract_arg_typing_tests`: 4 passed.
- `--lib type_ir`: 10 passed.
- full `igniter-compiler` suite: 378 passed, 0 failed.
- `git diff --check`: clean.

Compiler warnings are pre-existing unused/dead-code warnings in the crate; this
slice did not add a new warning path.

## Deferrals

- Arbitrary complex element inference remains deferred. The array shape check
  still resolves only `Ref` and `Literal` elements at this boundary; expressions
  such as arithmetic, calls, field access, and match results return `None` and
  are skipped as Unknown-compatible v0 behavior.
- Stdlib builtin argument typing remains a separate surface. This slice only
  closes contextual `Collection[T]` array literal element checks.
- Empty arrays remain contextual only: `[]` type-checks as `Collection[T]` only
  when a `Collection[T]` annotation/hint exists; there is no free-standing empty
  array type.
