# LAB-STDLIB-MATH-DET-TIER2-LN-EXP-P1 — deterministic ln/exp

Status: CLOSED — implemented + tested + cross-arch verified
Lane: standard / stdlib math
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-DET-TIER2-LN-EXP-P1
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Depends on `LAB-STDLIB-MATH-DET-TIER1-P5` (det_sin/det_cos/det_sqrt) + `LAB-STDLIB-MATH-TIER2-READINESS-P6`
(named tan/pow/exp/ln/… as the next surface). **Science pull:** the public `igniter-emergence` work now needs
deterministic `ln`/`exp` from two directions at once — SIRS Gaussian/Poisson contact models (Box–Muller needs
`ln`+`cos`+`sqrt`; Poisson/Knuth needs `exp`) and the Kuramoto Lorentzian ω (`tan`, sibling). det Tier-2 was
the highest cross-cutting stdlib lever across the nonlinear directions map.

## Goal

Add the smallest deterministic Tier-2 slice — `det_ln`, `det_exp` — beside Tier-1, via the **same vendored
`libm`** path, same totality discipline (never NaN/Inf), same golden-bit lock, same `STDLIB_VERSION` governance.

## What changed (surgical/additive; math parity preserved)

- `igniter-vm/src/vm.rs` — `eval_math_call`: added `det_ln`/`det_exp` arms (`libm::log`/`libm::exp`); added
  both names to the `OP_CALL` dispatch arm (so the bytecode path reaches the shared helper, like Tier-1).
- `igniter-compiler/src/typechecker/stdlib_calls.rs` — added `det_ln`/`det_exp` to the `(Float)->Float`
  resolution arm (OOF-MATH1 arity / OOF-MATH2 non-Float shared).
- `igniter-stdlib/stdlib/math.ig` — `def det_ln(x: Float) -> Float` / `def det_exp(x: Float) -> Float`.
- `igniter-vm/tests/stdlib_math_det_tests.rs` — golden vectors + a `det_ln_exp_totality` test.
- `STDLIB_VERSION` bumped `0.1.5 → 0.1.6` in `igniter-compiler/src/lib.rs` **and** `igniter-stdlib/Cargo.toml`
  (mirror guard `stdlib_version_mirrors_crate` green).

## Totality (never NaN/Inf — preserves the non-finite→null lineage invariant)

- `det_ln(x)`: non-finite input → error; `x <= 0` → domain error; else `libm::log(x)` (always finite for x>0).
- `det_exp(x)`: non-finite input → error; compute `libm::exp(x)`, then if the **result** is non-finite
  (overflow, e.g. `exp(710)`) → error. Large-negative input underflows to exactly `0.0` (finite) — allowed.

## Golden vectors (the cross-arch reference, vendored libm 0.2.16)

- `det_ln(2.0) = 0x3fe62e42fefa39ef` (0.6931471805599453); `det_ln(1.0) = 0.0` exact.
- `det_exp(1.0) = 0x4005bf0a8b14576a` (2.7182818284590455); `det_exp(0.0) = 1.0` exact;
  `det_exp(-1.0) = 0x3fd78b56362cef38`.

## Tests

- `igniter-vm` `stdlib_math_det_tests` → **7 passed** (golden incl. ln/exp + `det_ln_exp_totality`).
- No regression: `stdlib_math_tests` 5, `stdlib_math_basics_tests` 6, `stdlib_math_hof_tests` 7,
  `stdlib_random_tests` 10 — all green.
- Compiler: `stdlib_version_mirrors_crate` green; a real `.ig` kernel `det_ln(x)`/`det_exp(x)` compiles +
  typechecks + emits "ok" and **executes** on the VM (`det_ln(1.0) = 0.0`).

## Cross-architecture evidence

A 6001-point `libm::log`/`libm::exp` golden grid (pinned `libm 0.2.16`) produced a **bit-identical** SHA-256
`9d420a30f1fbfbf29587e2d9e63e71b380712b98b397cf26c904df5d9029d69b` on **real x86_64 (AMD Ryzen V1756B / Ubuntu)
and aarch64 (Cortex-A76 / Debian)** — det Tier-2 inherits the Tier-1 cross-arch determinism, empirically.

## Acceptance

- [x] `det_ln`/`det_exp` wired in VM (OP_CALL + eval_ast/HOF via the shared `eval_math_call`) + typechecker +
      stdlib signatures.
- [x] Totality: domain/overflow/non-finite are deterministic errors, never NaN/Inf.
- [x] Golden-bit lock added; full det suite + math regressions green.
- [x] `STDLIB_VERSION` bumped on both mirror sites; guard green.
- [x] Real `.ig` kernel compiles, typechecks, executes; values correct.
- [x] Cross-arch bit-identical on the two real ISAs.

## Closed surfaces

- Only `det_ln`/`det_exp`. `det_tan` (Lorentzian ω) and `det_atan2`/`det_pow` remain DEFERRED (named, not
  pulled yet).
- Lab frontier surface — **not** canon authority (a separate canon/gov promotion decision).
- No fast-`Math.*` change; no new dependency (libm already vendored).

## Next

- `det_tan` sibling (Lorentzian ω in-language) when pulled.
- Emergence can now build Gaussian (Box–Muller) / Poisson contact models for SIRS on the deterministic surface.
- Feeds the `det_*` canon-promotion decision (now spanning sin/cos/sqrt/ln/exp).
