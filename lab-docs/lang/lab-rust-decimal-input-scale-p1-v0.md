# Lab Doc - LAB-RUST-DECIMAL-INPUT-SCALE-P1 (v0)

**Date:** 2026-06-15
**Route:** lab / Rust typechecker / Decimal input scale parity
**Authority:** Rust lab typechecker fix only. Ruby canon behavior is baseline evidence,
not modified here. No Ruby, No VM, No app source, and no language surface changes.

## Goal

Fix the Rust-only Decimal scale extraction bug documented during
`LANG-RUBY-NUMERIC-OPS-PARITY-P1`: `Decimal[N]` input annotations reached Rust
`operator_type` with their scale in the param list, but the operator path read only
`params[0].name`. Input annotation params are normalized by `type_ir`/`get_param`, so
direct raw lookup treated `Decimal[2]` as missing scale and fell back to `0`.

Observed pre-fix behavior:

- `input a : Decimal[2]`, `input b : Decimal[2]`, `a * b` inferred `Decimal[0]` and failed
  against `output c : Decimal[4]`.
- `Decimal[2] + Decimal[4]` could miss the scale mismatch because both sides read as `0`.

## Implementation

Rust lab only:

- Added `TypeChecker::decimal_scale(&self, type_info) -> String` in
  `igniter-compiler/src/typechecker.rs`.
- The helper reads scale through `get_param`, which already normalizes both source
  annotation params such as `"2"` and constructor-created params such as `{"name":"2"}`.
- Updated `operator_type` Decimal `+`, `-`, and `*` scale reads to use `decimal_scale`.
- Updated the sibling `mul` stdlib arm in `typechecker/stdlib_calls.rs` to use the same
  helper, so the non-operator numeric path does not keep the same scale-zero bug.

The fallback for bare or malformed Decimal remains `"0"`, preserving the previous
fail-soft behavior for unparameterized internal Decimal shapes. Constructor-created
`decimal(value, scale)` behavior is unchanged.

## Evidence

Proof runner:

`igniter-compiler/verify_rust_decimal_input_scale_p1.rb`

RESULT: 78/78 PASS

Coverage:

- `Decimal[2] * Decimal[2]` from input annotations compiles and SIR compute type is
  `Decimal[4]`; no `Decimal[0]` remains in the emitted SIR.
- `Decimal[2] * Decimal[4]` compiles as `Decimal[6]`.
- Same-scale `+` and `-` input annotations compile and preserve the operand scale.
- `Decimal[2] + Decimal[4]` and `Decimal[4] - Decimal[2]` are rejected with existing
  `OOF-TC5` diagnostics and concrete `left_scale` / `right_scale` values.
- Constructor-created `decimal(150,2)` paths remain green for addition and multiplication.
- Constructor mismatch still emits `OOF-TC5`.
- Non-literal constructor scale still emits `OOF-DM4`.
- `mul(a,b)` stdlib path now preserves input annotation scale.
- Implicit `Float -> Decimal` remains rejected (`OOF-TY1`).
- `Decimal` without a scale remains rejected (`OOF-DM3`).

Build verification:

- `cargo build --release` in `igniter-compiler` completed successfully.

## Acceptance

- Rust infers `Decimal[2] * Decimal[2] -> Decimal[4]` for input annotations - MET.
- Rust rejects `Decimal[2] + Decimal[4]` with existing scale mismatch diagnostic - MET.
- Rust constructor path `decimal(1,2)` remains unchanged - MET.
- Ruby behavior treated as baseline but not modified - MET.
- No VM or app source changes - MET.

## Closed Surfaces

- No Ruby changes.
- No VM changes.
- No app migrations.
- No new Decimal syntax.
- No implicit coercion or rounding.

## Artifacts

- Implementation: `igniter-compiler/src/typechecker.rs`
- Implementation: `igniter-compiler/src/typechecker/stdlib_calls.rs`
- Proof: `igniter-compiler/verify_rust_decimal_input_scale_p1.rb`
- Card: `.agents/work/cards/lang/LAB-RUST-DECIMAL-INPUT-SCALE-P1.md`
