# lab-stdlib-math-det-tier2-tan-p2-v0 — deterministic tan

**Card:** `LAB-STDLIB-MATH-DET-TIER2-TAN-P2` · **Status:** CLOSED (implemented + tested + cross-arch verified)
**Date:** 2026-06-24

## Summary

`det_tan` added beside `det_ln`/`det_exp` (P1), same vendored `libm 0.2.16` path. Closes **Lorentzian ω
in-language** (`ω = γ·tan(π(u−½))`). Lab frontier surface — not canon authority.

## Wiring (6 edits, same pattern as P1)

`vm.rs` (eval_math_call `det_tan` arm `libm::tan` + OP_CALL name) · `typechecker/stdlib_calls.rs`
(`det_tan`→Float) · `stdlib/math.ig` (`def det_tan`) · `stdlib_math_det_tests.rs` (golden + totality) ·
`STDLIB_VERSION 0.1.6→0.1.7` (compiler lib.rs + stdlib Cargo.toml, mirror guard green).

## Totality

non-finite input → error; non-finite result (pole) → error; finite over `(−π/2, π/2)` (the Lorentzian range).

## Golden (libm 0.2.16)

`det_tan(0.5)=0x3fe17b4f5bf3474a`, `det_tan(1.0)=0x3ff8eb245cbee3a6`, `det_tan(0.0)=0.0`,
`det_tan(1.4708)=0x4023ef1c536b2da2`.

## Verification

- `stdlib_math_det_tests` 8/8; regressions green (math 5, basics 6, hof 7); mirror guard green.
- Real `.ig` `det_tan` kernel compiles+typechecks+executes (`det_tan(0.5)=0.5463024898437905`).
- **Cross-arch:** 3001-point `libm::tan` grid → SHA-256
  `31b0294d9165370941f2a9506c73a9de5dca8db32a78b76d92fab35f76005bc8` bit-identical on real x86_64 + aarch64.

## Deferred

`det_atan2`, `det_pow` — named, not pulled. det Tier-2 now spans ln/exp/tan.
