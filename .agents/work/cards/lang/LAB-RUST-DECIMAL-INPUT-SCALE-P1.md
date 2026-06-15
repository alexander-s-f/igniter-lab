# LAB-RUST-DECIMAL-INPUT-SCALE-P1

**Status:** CLOSED - IMPLEMENTED (Rust lab typechecker, 78/78, 2026-06-15)
**Route:** lab / Rust typechecker / Decimal input scale parity
**Date:** 2026-06-15
**Authority:** Rust lab typechecker fix only; no Ruby, VM, app, or language surface changes

## Goal

Fix the Rust typechecker bug found during `LANG-RUBY-NUMERIC-OPS-PARITY-P1`: Decimal scale
from input annotations is read as `0` in `operator_type` / numeric typing paths.

Observed bad behavior:

- `input a : Decimal[2]`, `input b : Decimal[2]`, `a * b` is inferred as `Decimal[0]` or fails against expected `Decimal[4]`.
- `Decimal[2] + Decimal[4]` can miss the scale mismatch because both scales are read as `0`.

Ruby canon is now correct here; Rust should match it.

## Gate

Start after:

- `LANG-RUBY-NUMERIC-OPS-PARITY-P1` CLOSED — bug documented and isolated.
- `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` CLOSED — constructor path already works and must remain green.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-RUBY-NUMERIC-OPS-PARITY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/proposals/LANG-RUBY-NUMERIC-OPS-PARITY-P1-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker/stdlib_calls.rs`
- Decimal construct and boundary proof runners.

## Work

1. Reproduce the Rust-only Decimal input annotation scale bug.
2. Locate scale extraction for Decimal type IR in Rust numeric/operator typing.
3. Fix scale extraction for both input annotations and constructor-created Decimal types.
4. Preserve constructor path behavior.
5. Confirm scale mismatch remains rejected.

## Deliverables

- Rust typechecker implementation in `igniter-compiler`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/verify_rust_decimal_input_scale_p1.rb`, target at least 60 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-decimal-input-scale-p1-v0.md`.
- Update this card and portfolio index.

## Acceptance

- Rust infers `Decimal[2] * Decimal[2] -> Decimal[4]` for input annotations.
- Rust rejects `Decimal[2] + Decimal[4]` with the existing scale mismatch diagnostic.
- Rust constructor path `decimal(1,2)` remains unchanged.
- Ruby behavior is treated as baseline but not modified.
- No VM or app source changes.

## Closed Surfaces

- No Ruby changes.
- No VM changes.
- No app migrations.
- No new Decimal syntax.
- No implicit coercion or rounding.

## Agent Recommendation

Give this to **Codex GPT 5.5**. It is a narrow Rust parity fix with high confidence and useful Decimal correctness value.

---

## Closure Summary - CLOSED 2026-06-15

Implemented the Rust-only Decimal input annotation scale fix in the lab compiler. Ruby
canon behavior from `LANG-RUBY-NUMERIC-OPS-PARITY-P1` was used as baseline evidence only;
no Ruby/canon files were changed.

### Done

- Added `TypeChecker::decimal_scale` in `igniter-compiler/src/typechecker.rs`.
- `operator_type` now reads Decimal operand scales through `get_param`/`type_ir`
  normalization instead of raw `params[0].name`, so input annotation params (`"2"`) and
  constructor params (`{"name":"2"}`) are read consistently.
- Updated the sibling `mul` stdlib arm in `typechecker/stdlib_calls.rs` to use the same
  helper, closing the second Rust numeric typing path with the same scale-zero risk.

### Evidence

- `cargo build --release` - ok.
- `ruby igniter-compiler/verify_rust_decimal_input_scale_p1.rb` - RESULT: 78/78 PASS.

### Acceptance

- `input Decimal[2] * input Decimal[2] -> Decimal[4]` - MET.
- `input Decimal[2] + input Decimal[4]` rejects with `OOF-TC5` and concrete
  `left_scale=2, right_scale=4` - MET.
- Constructor path `decimal(150,2) * decimal(200,2) -> Decimal[4]` remains green - MET.
- `mul(input Decimal[2], input Decimal[2]) -> Decimal[4]` now preserves scale - MET.
- `Float -> Decimal` remains `OOF-TY1`; bare `Decimal` remains `OOF-DM3` - MET.

### Closed Surfaces Held

- No Ruby changes.
- No VM changes.
- No app migrations.
- No new Decimal syntax.
- No implicit coercion or rounding.

### Artifacts

- Implementation: `igniter-compiler/src/typechecker.rs`
- Implementation: `igniter-compiler/src/typechecker/stdlib_calls.rs`
- Proof: `igniter-compiler/verify_rust_decimal_input_scale_p1.rb`
- Lab doc: `lab-docs/lang/lab-rust-decimal-input-scale-p1-v0.md`
