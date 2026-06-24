# lab-stdlib-math-det-tier2-ln-exp-p1-v0 — deterministic ln/exp

**Card:** `LAB-STDLIB-MATH-DET-TIER2-LN-EXP-P1` · **Status:** CLOSED (implemented + tested + cross-arch verified)
**Date:** 2026-06-24

## Summary

Added `det_ln` / `det_exp` to the deterministic Tier surface beside Tier-1 (`det_sin/det_cos/det_sqrt`), via
the same vendored pure-Rust `libm 0.2.16`. Science-pulled by `igniter-emergence` (SIRS Gaussian/Poisson contact
models + Kuramoto Lorentzian ω). Lab frontier surface — not canon authority.

## Wiring (6 surgical edits, math parity preserved)

| file | change |
|---|---|
| `igniter-vm/src/vm.rs` | `eval_math_call` `det_ln`/`det_exp` arms (`libm::log`/`libm::exp`); names added to the `OP_CALL` dispatch arm |
| `igniter-compiler/src/typechecker/stdlib_calls.rs` | `det_ln`/`det_exp` → `(Float)->Float` (OOF-MATH1/2 shared) |
| `igniter-stdlib/stdlib/math.ig` | `def det_ln`/`def det_exp` signatures |
| `igniter-vm/tests/stdlib_math_det_tests.rs` | golden vectors + `det_ln_exp_totality` |
| `igniter-compiler/src/lib.rs` + `igniter-stdlib/Cargo.toml` | `STDLIB_VERSION` 0.1.5 → 0.1.6 (mirror guard green) |

## Totality (never NaN/Inf)

`det_ln`: non-finite → error; `x<=0` → domain error; else `libm::log(x)`.
`det_exp`: non-finite input → error; result non-finite (overflow) → error; large-negative underflow → exact `0.0`.

## Golden vectors (libm 0.2.16)

`det_ln(2.0)=0x3fe62e42fefa39ef`, `det_ln(1.0)=0.0`; `det_exp(1.0)=0x4005bf0a8b14576a`, `det_exp(0.0)=1.0`,
`det_exp(-1.0)=0x3fd78b56362cef38`.

## Verification

- `stdlib_math_det_tests` 7/7 (golden + totality); regressions green (math 5, basics 6, hof 7, random 10).
- mirror guard `stdlib_version_mirrors_crate` green; real `.ig` `det_ln/det_exp` kernel compiles+typechecks+
  executes on the VM (`det_ln(1.0)=0.0`).
- **Cross-arch:** 6001-point `libm::log`/`libm::exp` grid → SHA-256
  `9d420a30f1fbfbf29587e2d9e63e71b380712b98b397cf26c904df5d9029d69b` bit-identical on real x86_64 + aarch64.

## Deferred

`det_tan` (Lorentzian ω), `det_atan2`, `det_pow` — named, not pulled. Canon promotion of `det_*` = separate
gov decision.
