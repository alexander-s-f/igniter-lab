# LAB-STDLIB-MATH-NUMERIC-BASICS-P7 — total scalar basics for scientific/control code

Status: CLOSED
Lane: standard / stdlib math
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-NUMERIC-BASICS-P7
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-MATH-TIER2-READINESS-P6` — evidence-ranked Tier-2 plan.
- `LAB-STDLIB-MATH-TRANSCENDENTALS-P2` — current OOF-MATH1/2 pattern.
- `LAB-STDLIB-MATH-DET-TIER1-P5` — stdlib version/provenance discipline.

P6 changed the obvious-looking Tier-2 order. The highest proven app pressure is not `exp/ln`; it is N0 numeric
basics that were hand-rolled with nested `if` in pursuit/guidance pressure code: `abs`, `min`, `max`, `clamp`,
`sign`. These are total, deterministic by construction, and useful for control, physics, vector math, and
scientific simulation hygiene.

This card implements only N0 basics. It does not implement integer roots/mod or advanced Float transcendentals.

## Goal

Add the smallest high-value numeric basics surface:

- `abs(x)`
- `min(a, b)`
- `max(a, b)`
- `clamp(x, lo, hi)`
- `sign(x)`

Support the live numeric types where feasible:

- `Integer`
- `Float`
- `Decimal[N]` if the VM/value path already has enough Decimal support for exact same-scale behavior.

If Decimal support is not small/live enough, do **not** fake it. Implement Integer+Float first and document
Decimal as the next narrow card with exact blockers. Let live code decide.

## Verify first

- `lab-docs/lang/lab-stdlib-math-tier2-readiness-p6-v0.md`
- `lang/igniter-stdlib/stdlib/math.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-compiler/tests/stdlib_math_tests.rs`
- `lang/igniter-vm/tests/stdlib_math_tests.rs`
- existing Decimal value representation/tests in `lang/igniter-vm` and compiler Decimal tests.

Before implementation, characterize how Decimal values are represented at runtime and how Decimal scale is
stored in type IR. Do not infer a Decimal design from docs if live code disagrees.

## Semantics

- `abs(T) -> T`, for same numeric type T.
- `min(T,T) -> T`, `max(T,T) -> T`; no mixed-type coercion.
- `clamp(x, lo, hi) -> T`; no mixed-type coercion.
- `sign(T) -> Integer`, returning `-1`, `0`, `1`.
- Float non-finite policy follows the math-line discipline: do not silently produce lineage-hostile NaN/Inf.
  For N0 functions, prefer deterministic runtime error on non-finite Float input unless there is already a
  project-wide Float-non-finite policy saying otherwise.
- `clamp` with `lo > hi`: choose and document one total semantics. Recommendation: deterministic runtime error
  for invalid bounds, because silent inversion hides bugs in control code. If you choose total hi-wins/lo-wins,
  justify it against control/simulation pressure.

## Diagnostics

Reuse existing math diagnostics where possible:

- `OOF-MATH1` — wrong arity.
- `OOF-MATH2` — non-numeric argument if a function expects numeric.
- Introduce `OOF-MATH3` only if mixed numeric types need a distinct compile-time diagnostic (e.g. `min(Integer,
  Float)` or mismatched Decimal scales). If not needed, document why.

No implicit Integer/Float/Decimal coercion.

## Required implementation

- Add declarations to `lang/igniter-stdlib/stdlib/math.ig`.
- Wire typechecker support in `stdlib_calls.rs`.
- Wire VM support in `vm.rs`.
- If these functions can appear inside HOF/lambda bodies, ensure `eval_ast` parity from P10 is preserved. Prefer
  a shared helper if adding another mirrored dispatch block would recreate the OP_CALL/eval_ast drift P10 fixed.
- Bump `igniter-stdlib` version and compiler `STDLIB_VERSION` if the stdlib surface changes.

## Acceptance

- [x] `abs/min/max/clamp/sign` compile for valid Integer inputs.
- [x] `abs/min/max/clamp/sign` compile for valid Float inputs.
- [x] Decimal support either works with exact scale preservation or is explicitly deferred with live blockers.
- [x] Wrong arity emits `OOF-MATH1`.
- [x] Non-numeric arguments emit `OOF-MATH2` (or documented existing rule if the checker routes differently).
- [x] Mixed numeric types are rejected deterministically (`OOF-MATH3` if introduced, otherwise a documented rule).
- [x] VM exact-value tests cover Integer and Float.
- [x] Float non-finite input is refused deterministically if reachable.
- [x] `clamp` invalid-bounds behavior is explicit and tested.
- [x] If implemented in shared runtime helper, both OP_CALL and eval_ast/HOF paths are covered by tests.
- [x] Fast P2 math, deterministic P5 math, and P10 HOF math tests remain green.
- [x] Package `STDLIB_VERSION` mirror guard remains green if version is bumped.
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-math-numeric-basics-p7-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation:** `abs/min/max/clamp/sign` over **{Integer, Float}** (same-type, no coercion), all in the
**single `eval_math_call` source** (P10) so bytecode `OP_CALL` and HOF/lambda bodies share one path — no drift.
Helpers `num_abs/num_sign/num_min_max/num_clamp` + 5 arms in `vm.rs`; OP_CALL delegating arm extended with the
5 names; typecheck arm in `stdlib_calls.rs` (polymorphic return — `sign`→Integer, others mirror arg type;
**OOF-MATH3** new for mixed numeric); `math.ig` decls; `STDLIB_VERSION 0.1.1→0.1.2`. Proof:
`lab-docs/lang/lab-stdlib-math-numeric-basics-p7-v0.md`.

**Decisions:** `clamp(lo>hi)` = deterministic error (control-code hygiene, no silent inversion); non-finite
Float input = error (lineage discipline); N0 total over finite. **Decimal DEFERRED** (verdict) — abs/sign
trivial but min/max/clamp need a scale-matching rule (a real semantic choice); partial Decimal would be
inconsistent → one narrow follow-up card. Integer+Float ship now.

**Tests/green:** `stdlib_math_basics_tests` **5** (values+errors+clamp-in-fold HOF) + compiler
`numeric_basics_typecheck` (OOF-MATH1/2/3 + sign→Integer); P2 fast 5, P5 det 6, P10 HOF 7 all green;
STDLIB_VERSION mirror guard green (0.1.2); full VM suite green except pre-existing `vmg13`. Live smoke
`clamp(-2.5,0,1)=0.0`. `git diff --check` clean.

**Next:** `LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` (`isqrt/ipow/mod`, domain errors); Decimal-N0 narrow card.

## Proof doc requirements

The proof doc must include:

- live Decimal feasibility verdict;
- final type/domain matrix;
- exact `clamp(lo>hi)` decision;
- diagnostic matrix (`OOF-MATH1/2/3` as applicable);
- OP_CALL/eval_ast parity statement;
- exact tests and counts;
- what remains for P8.

## Closed scope

- No `isqrt`, `ipow`, `mod` / `rem` (P8).
- No `floor`, `ceil`, `round` unless discovered as a tiny prerequisite and explicitly justified.
- No `atan2`, `tan`, `exp`, `ln`, `powf`.
- No numeric tower or implicit coercion.
- No qemu cross-arch proof.
- No performance benchmark.
- No canon claim.

## Next

`LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` — `isqrt/ipow/mod` with deterministic integer algorithms and domain
errors.
