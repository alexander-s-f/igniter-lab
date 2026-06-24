# LAB-STDLIB-MATH-DET-TIER2-TAN-P2 — deterministic tan (Lorentzian ω in-language)

Status: CLOSED — implemented + tested + cross-arch verified
Lane: standard / stdlib math
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-DET-TIER2-TAN-P2
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Sibling of `LAB-STDLIB-MATH-DET-TIER2-LN-EXP-P1`. Completes the science-pulled Tier-2 transcendentals with
`det_tan`, which closes **Lorentzian ω generation in-language** (`ω = γ·tan(π(u−½))`, the Kuramoto natural-
frequency distribution) — previously the runner generated ω host-side with std `.tan()`.

## What changed (same surgical pattern as P1)

- `igniter-vm/src/vm.rs` — `eval_math_call` `det_tan` arm (`libm::tan`); name added to the `OP_CALL` arm.
- `igniter-compiler/src/typechecker/stdlib_calls.rs` — `det_tan` → `(Float)->Float`.
- `igniter-stdlib/stdlib/math.ig` — `def det_tan(x: Float) -> Float`.
- `igniter-vm/tests/stdlib_math_det_tests.rs` — golden vectors + `det_tan_totality`.
- `STDLIB_VERSION` `0.1.6 → 0.1.7` (compiler `lib.rs` + stdlib `Cargo.toml`; mirror guard green).

## Totality

`det_tan(x)`: non-finite input → error; compute `libm::tan(x)`, then if the **result** is non-finite (a pole)
→ error; else `Ok`. Over the Lorentzian range `(−π/2, π/2)` tan is finite, so ω generation is total.

## Golden vectors (libm 0.2.16)

`det_tan(0.5)=0x3fe17b4f5bf3474a` (0.5463024898437905); `det_tan(1.0)=0x3ff8eb245cbee3a6`;
`det_tan(0.0)=0.0`; `det_tan(1.4708)=0x4023ef1c536b2da2` (≈9.967, the α=π/2−0.1 edge — finite).

## Verification

- `stdlib_math_det_tests` **8/8** (golden incl. tan + `det_tan_totality`); no regression (math 5, basics 6,
  hof 7).
- mirror guard `stdlib_version_mirrors_crate` green (0.1.7); a real `.ig` `det_tan(x)` kernel compiles +
  typechecks + **executes** (`det_tan(0.5)=0.5463024898437905`).
- **Cross-arch:** 3001-point `libm::tan` grid over `(−1.5, 1.5)` → SHA-256
  `31b0294d9165370941f2a9506c73a9de5dca8db32a78b76d92fab35f76005bc8` bit-identical on real x86_64 + aarch64.

## Acceptance

- [x] `det_tan` wired (VM OP_CALL + eval_ast/HOF via shared helper) + typechecker + stdlib signature.
- [x] Totality: non-finite input/result = deterministic error, never NaN/Inf.
- [x] Golden-bit lock; det suite + math regressions green; STDLIB_VERSION bumped (guard green).
- [x] Real `.ig` kernel compiles/typechecks/executes; value correct.
- [x] Cross-arch bit-identical on the two real ISAs.

## Closed surfaces

- Only `det_tan`. `det_atan2` / `det_pow` remain DEFERRED (named, not pulled).
- Lab frontier surface — not canon authority.
- No fast-`Math.*` change; no new dependency.

## Next

- Emergence: Lorentzian ω can now be generated **in-language** (det_tan) — replay-critical path no longer
  depends on host std `.tan()`.
- det Tier-2 now spans `ln/exp/tan`; feeds the `det_*` canon-promotion decision (sin/cos/sqrt/ln/exp/tan).
