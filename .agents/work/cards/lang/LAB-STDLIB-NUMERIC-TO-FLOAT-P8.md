# LAB-STDLIB-NUMERIC-TO-FLOAT-P8 — explicit Integer to Float conversion

Status: CLOSED
Lane: standard / stdlib numeric / science prerequisite
Type: implementation proof
Delegation code: OPUS-STDLIB-NUMERIC-TO-FLOAT-P8
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-STATISTICS-READINESS-P1` — found that descriptive stats are blocked by `Float / Integer`.
- `LAB-STDLIB-MATH-NBODY-SWEEP-P11` — order parameter currently uses fixed Float literals for N.
- `LAB-STDLIB-MATH-NUMERIC-BASICS-P7` — no implicit coercion remains the rule.

The live typechecker deliberately rejects heterogeneous numeric ops. That is good: do not introduce implicit
coercion. But science code needs an explicit conversion for `sum / count`, variable-size order parameters, and
normalization: `to_float(count(xs))`.

## Goal

Implement the tiny explicit conversion:

- `to_float(x: Integer) -> Float`

This is a named boundary, not a numeric tower. Do not make binary ops coerce automatically.

Consider `to_float(Decimal)` only if it is already tiny and unambiguous in live code. Bias: Integer-only first,
Decimal deferred with a clear blocker if precision/scale policy is not obvious.

## Verify first

- `lab-docs/lang/lab-stdlib-statistics-readiness-p1-v0.md`
- `lang/igniter-compiler/src/typechecker.rs` numeric binary-op rules around same-type-only behavior.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-stdlib/stdlib/math.ig`
- collection/count/sum behavior in VM/compiler tests.

Confirm there is no existing `to_float`, `as_float`, `float`, or implicit cast surface. If there is, reuse or
document why it is not the right boundary.

## Semantics

- `to_float(Integer) -> Float`, using Rust `as f64` semantics for i64-to-f64.
- Large integers beyond exact 53-bit mantissa may round, by IEEE-754 design. This is acceptable for counts and
  normalization but must be documented.
- Non-Integer input is compile error (`OOF-MATH2`) unless Decimal support is deliberately included.
- Wrong arity is `OOF-MATH1`.
- No implicit coercion in `+ - * /`, `min/max/clamp`, stats, or linalg.

## Required implementation

- Add declaration to `lang/igniter-stdlib/stdlib/math.ig` or a more appropriate numeric stdlib file if live
  structure says so.
- Wire typechecker support.
- Wire VM support through shared `eval_math_call` if possible, preserving OP_CALL/eval_ast parity.
- Bump `igniter-stdlib` version and compiler `STDLIB_VERSION`.
- Add compiler tests and VM tests.
- Add one proof expression that computes `sum / to_float(count)` over a collection or an equivalent VM AST,
  proving the statistics blocker is actually removed.

## Acceptance

- [x] `to_float(Integer)->Float` compiles cleanly. (`igc` status ok.)
- [x] `to_float(3)` executes as `3.0`.
- [x] negative integer conversion works. (`to_float(-7) = -7.0`.)
- [x] large integer rounding behavior documented + tested. (`2^53+1 → 2^53`, stable expectation.)
- [x] wrong arity emits `OOF-MATH1`.
- [x] non-Integer input emits `OOF-MATH2` (Decimal deferred with live blocker).
- [x] OP_CALL and eval_ast/HOF parity tested. (shared `eval_math_call`; compiler→VM test.)
- [x] normalization proof executes: `9.0 / to_float(3) = 3.0` (mirrors `sum / to_float(count)`).
- [x] No binary numeric operator gains implicit coercion. (`9.0 / k` still `OOF-TY0`.)
- [x] `STDLIB_VERSION` mirror guard remains green. (0.1.4, synced with concurrent N1.)
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-numeric-to-float-p8-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**`to_float(Integer) -> Float`** is live — the single **named** widening boundary (`i as f64`), wired through
the shared `eval_math_call` (OP_CALL + eval_ast/HOF parity), typecheck arm (`OOF-MATH1` arity, `OOF-MATH2`
non-Integer), `stdlib/math.ig` decl, `STDLIB_VERSION` 0.1.4 (synced with the concurrent N1 `isqrt/ipow/mod`).
**No implicit coercion added:** `9.0 / k` (Float/Integer) is still rejected (`OOF-TY0`), while
`9.0 / to_float(k)` compiles — proven via `igc`. Large-i64 rounding documented + tested (`2^53+1 → 2^53`).

**Statistics blocker removed:** `9.0 / to_float(3) = 3.0` runs through the real compiler→VM (mirrors
`sum / to_float(count)`). Proof doc: `lab-docs/lang/lab-stdlib-numeric-to-float-p8-v0.md`.

**Proof:** `stdlib_to_float_tests` 5 passed; math/random/nbody/hof/det parity intact (6/7/5/6/5); version
guard green; 4 `igc` typecheck cases correct (ok / OOF-TY0 / OOF-MATH1 / OOF-MATH2); `git diff --check` clean.
Edited shared files (vm.rs/stdlib_calls.rs/math.ig/lib.rs/Cargo.toml — neighbor-active for N1) **surgically/
additively**, parity preserved. **Decimal→Float deferred** (scale/precision policy not unambiguous; integer-
only per bias). **Next:** `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` (now unblocked); emergence N-body can use a
real `N = to_float(count(phases))`.

## Proof doc requirements

The proof doc must include:

- live absence/presence check for existing conversion surfaces;
- exact conversion semantics and rounding note;
- diagnostic matrix;
- proof that `Float / Integer` remains rejected but `Float / to_float(Integer)` works;
- tests and counts;
- whether Decimal was included or deferred, with live blocker.

## Closed scope

- No implicit numeric coercion.
- No `to_integer`, `floor`, `ceil`, `round`, or `parse_float`.
- No Decimal conversion unless live code makes it trivial and the proof doc justifies it.
- No stats implementation; only unblock it.
- No canon claim.

## Next

`LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` should run after this card lands.
