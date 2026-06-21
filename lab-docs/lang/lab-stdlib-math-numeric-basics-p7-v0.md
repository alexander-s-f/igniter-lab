# lab-stdlib-math-numeric-basics-p7-v0 — N0 scalar basics (abs/min/max/clamp/sign)

**Card:** `LAB-STDLIB-MATH-NUMERIC-BASICS-P7` · **Delegation:** `OPUS-STDLIB-MATH-NUMERIC-BASICS-P7`
**Status:** CLOSED (implementation proof) — `abs`, `min`, `max`, `clamp`, `sign` over **{Integer, Float}**
(same-type, no implicit coercion), wired through the **single shared `eval_math_call`** source so they work
identically via bytecode `OP_CALL` and inside HOF/lambda bodies (P10 parity). **Total** over finite values;
non-finite Float input and `clamp(lo>hi)` are deterministic runtime errors. **Decimal deferred** (verdict
below). `STDLIB_VERSION 0.1.1 → 0.1.2`.

## Live Decimal feasibility verdict — DEFERRED (not faked)

`abs`/`sign` on `Value::Decimal{value,scale}` are trivial (sign flip / signum, no scale interaction). But
`min`/`max`/`clamp` over Decimals need a **scale-matching decision** (same-scale-required vs rescale) — the
VM's `Value::Decimal` carries an explicit `scale`, and comparing/selecting two different scales is a real
semantic choice, not a mechanical one. A *partial* Decimal surface (abs/sign only) would be inconsistent. Per
the card ("do not fake it; let live code decide"), **all Decimal N0 is deferred to a narrow follow-up** with
the exact blocker: *pick and test the min/max/clamp scale rule (same-scale → else OOF-MATH3, vs auto-rescale)*.
Integer + Float ship now.

## Final type / domain matrix

| fn | types (same-type) | arity | return | domain / total |
|---|---|---|---|---|
| `abs` | Integer, Float | 1 | T | total; Integer `i64::MIN`→overflow error; non-finite Float→error |
| `min` `max` | Integer, Float | 2 | T | total over finite; non-finite Float→error |
| `clamp` | Integer, Float | 3 | T | total over finite; **`lo>hi`→error**; non-finite Float→error |
| `sign` | Integer, Float | 1 | **Integer** (−1/0/1) | total; non-finite Float→error; `sign(±0.0)=0` |

No implicit coercion: `min(Integer, Float)` etc. is rejected at compile time. Decimal/String/etc. → not numeric.

## `clamp(lo > hi)` decision

**Deterministic runtime error** (`"clamp: invalid bounds (lo > hi)"`). Rationale (from the card + P6 control
pressure): silent hi-wins/lo-wins inversion hides bugs in guidance/control code, where `clamp` was hand-rolled
with nested `if`. An explicit error surfaces the bug; total clamping over *valid* bounds is preserved.

## Diagnostic matrix

| rule | meaning | example |
|---|---|---|
| `OOF-MATH1` | wrong arity | `min(x)` (1 arg) |
| `OOF-MATH2` | non-numeric argument (incl. **Decimal, deferred**) | `abs(String)` |
| `OOF-MATH3` | **mixed numeric types** (NEW — no implicit coercion) | `min(Float, Integer)` |

`OOF-MATH3` is introduced per the card's option, because mixed numeric types are a distinct, common,
compile-time-catchable mistake (vs `OOF-MATH2` non-numeric). Return type: `abs/min/max/clamp` mirror the first
argument's type; `sign` is always `Integer`.

## OP_CALL ↔ eval_ast parity (one source)

N0 basics live **inside `eval_math_call`** (the P10 single source) — `num_abs/num_sign/num_min_max/num_clamp`
helpers plus five `match` arms. The bytecode `OP_CALL` delegating arm was extended with the five names; the
`eval_ast` HOF path already routes every call through `eval_math_call` before its binary-operator fallback.
So there is **no second mirrored block to drift** — bytecode and HOF results/messages are identical by
construction. Proven by `clamp_inside_fold_lambda` (clamp inside a `fold` → 1.5).

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_basics_tests   → 5 passed (abs/sign/min-max/clamp values+errors; clamp-in-fold HOF)
$ cd lang/igniter-vm && cargo test --test stdlib_math_tests          → 5 passed (P2 fast, via shared helper)
$ cd lang/igniter-vm && cargo test --test stdlib_math_det_tests      → 6 passed (P5 det)
$ cd lang/igniter-vm && cargo test --test stdlib_math_hof_tests      → 7 passed (P10 HOF parity)
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests    → 6 passed (incl. numeric_basics_typecheck: OOF-MATH1/2/3 + sign→Integer)
$ cd lang/igniter-compiler && cargo test --test package_workspace_tests stdlib_version → guard green (STDLIB_VERSION 0.1.2 mirrors crate)
$ git diff --check                                                   → clean
```

**Live smoke:** `clamp(-2.5, 0.0, 1.0) → 0.0`, `clamp(0.5, 0.0, 1.0) → 0.5` (real compiler + VM `run`).
**Pre-existing unrelated VM failure** (same as P2/P5/P10): `vmg13_local_loops_and_service_loops`
(`OP_GET_FIELD` on a unix-timestamp), fails on clean HEAD, unrelated to math.

## Acceptance — mapping

- [x] `abs/min/max/clamp/sign` compile for Integer and for Float.
- [x] Decimal explicitly deferred with the live blocker (min/max/clamp scale rule).
- [x] Wrong arity → `OOF-MATH1`; non-numeric → `OOF-MATH2`; mixed types → `OOF-MATH3` (new).
- [x] VM exact-value tests cover Integer and Float.
- [x] Non-finite Float input refused deterministically; `clamp(lo>hi)` errors (tested).
- [x] Shared `eval_math_call` source → OP_CALL and eval_ast/HOF both covered (`clamp_inside_fold_lambda`).
- [x] Fast P2, deterministic P5, and P10 HOF math tests remain green.
- [x] `STDLIB_VERSION` bumped `0.1.1 → 0.1.2`; package mirror guard green.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-vm/src/vm.rs` — N0 helpers + arms in `eval_math_call`; OP_CALL delegating arm extended.
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` — N0 arm (polymorphic return; OOF-MATH1/2/3).
- `lang/igniter-stdlib/stdlib/math.ig` — N0 declarations.
- `lang/igniter-stdlib/Cargo.toml`, `lang/igniter-compiler/src/lib.rs` — `STDLIB_VERSION 0.1.2` (+ lockfiles).
- `lang/igniter-vm/tests/stdlib_math_basics_tests.rs` (new, 5); `…/igniter-compiler/tests/stdlib_math_tests.rs` (+1).

## What remains for P8 (and beyond)

- `LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` — `isqrt/ipow/mod` (Integer-first, domain errors for `isqrt(x<0)`,
  `ipow(exp<0)`, `mod` by 0).
- **Decimal N0** — the deferred narrow card: decide + test the min/max/clamp scale rule.
- `floor/ceil/round`, `tan/exp/ln/atan2/powf` — second wave (not N0).

---

*Implementation proof. 2026-06-21. `abs/min/max/clamp/sign` over Integer+Float, same-type, total over finite,
in the single `eval_math_call` source (bytecode + HOF parity, no drift). `sign`→Integer; `clamp(lo>hi)` and
non-finite Float are deterministic errors; mixed types = new `OOF-MATH3`. Decimal deferred (scale-rule
blocker). 5 N0 VM + 1 compiler typecheck tests; P2/P5/P10 green; `STDLIB_VERSION 0.1.2`; `git diff --check`
clean.*
