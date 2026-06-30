# LAB-STDLIB-DECIMAL-MONEY-SAFE-P2

Status: READY
Date: 2026-06-27
Lane: igniter-lab / stdlib+VM / foundation-hardening
Type: implementation proof

## Boundary

This packet implements the lab P1 Decimal money-safe v0 contract from:

```text
lab-docs/lang/lab-stdlib-decimal-money-contract-readiness-p1.md
```

It does not change canon `igniter-lang`, compiler/parser/package/server/machine,
home-lab, SparkCRM, frame-ui, render-html, Float formatting, or
`to_text(Float)`.

## Implemented Contract

- Public VM/SIR/JSON shape remains `Value::Decimal { value: i64, scale: u32 }`.
- `MAX_DECIMAL_SCALE = 18` is enforced by Decimal operations and VM
  `decimal(value, scale)` construction.
- Decimal add/sub/mul/div use checked `i128` intermediates and fail closed with
  `OOF-DM1` on overflow.
- Add/sub still require equal scales and preserve `OOF-TC5` for scale mismatch.
- Mul is now fallible and rejects scale overflow/out-of-range with
  `OOF-DM5`/`OOF-DM4`; the C ABI `stdlib_decimal_mul` now returns an error code.
- Div is exact-only, rejects zero with `OOF-DM2`, rejects inexact results with
  `OOF-DM3`, and preserves lhs scale.
- Decimal equality/order are numeric and scale-normalized.
- VM bytecode and eval_ast Decimal comparisons no longer route through
  `to_f64()`.
- `try_from_f64` is explicit/fallible; no VM Decimal construction path accepts
  Float.

## Changed Tests

- Updated old VM division behavior:
  `test_decimal_division_scale_subtraction` became
  `test_decimal_division_preserves_lhs_scale`, with expected
  `Decimal { value: 1050, scale: 2 }`.
- Added stdlib contract tests:
  `lang/igniter-stdlib/tests/decimal_money_safe_tests.rs`.
- Added VM bytecode tests for:
  checked add/sub/mul overflow, scale bound, exact-only division,
  scale-normalized equality, scale-normalized order, and the
  `9007199254740993 > 9007199254740992` no-f64 precision guard.

## Verification

Commands run from current checkout:

```text
cd lang/igniter-stdlib && cargo test
cd lang/igniter-vm && cargo test --test vm_tests decimal_ -- --nocapture
cd lang/igniter-vm && cargo test
```

Results:

- `igniter-stdlib`: pass, including 4 Decimal money-safe tests and existing
  regexp proof tests.
- `igniter-vm` focused Decimal tests: pass, 12/12.
- `igniter-vm` full crate tests: pass.
- Existing `stdlib_to_text_tests.rs` remains green, including exact
  `to_text(Decimal)` cases.

The full VM suite still emits pre-existing warnings about unused `has_integer`,
unnecessary `unsafe`, and an unused `LoopFrame.name`; this card did not expand
that warning cleanup scope.
