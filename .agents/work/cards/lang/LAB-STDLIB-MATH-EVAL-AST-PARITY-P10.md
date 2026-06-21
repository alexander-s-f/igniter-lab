# LAB-STDLIB-MATH-EVAL-AST-PARITY-P10 — stdlib math inside HOF/lambda runtime path

Status: CLOSED
Lane: standard / stdlib math + VM parity
Type: implementation proof
Delegation code: OPUS-STDLIB-MATH-EVAL-AST-PARITY-P10
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-MATH-TRANSCENDENTALS-P2` — fast `sin/cos/sqrt/pi` in the bytecode `OP_CALL` path.
- `LAB-STDLIB-MATH-DET-TIER1-P5` — deterministic `det_sin/det_cos/det_sqrt` in the bytecode `OP_CALL` path.
- `LAB-STDLIB-MATH-NBODY-PRESSURE-P9` — N-body Kuramoto pressure proof.

P9 found the first real scientific runtime blocker after Tier-1 math:

```ig
compute terms = map(others, other -> sin(other.theta - theta_i))
compute coupling = sum(terms)
```

This **compiles cleanly** but fails at runtime:

```text
VM evaluation failed: Operator sin expects exactly 2 operands; got 1
```

The no-math control (`other.theta - theta_i`) runs correctly, so records, closure capture, Float arithmetic,
`map`, and `sum` are not the blocker. The blocker is precise: HOF/lambda bodies are evaluated by `eval_ast`,
while P2/P5 math was wired only in bytecode `OP_CALL`.

## Goal

Make Tier-1 stdlib math work inside `eval_ast` function-call dispatch, so math composes with `map` / `fold` /
`filter` lambda bodies.

This is a **VM parity** card, not a new math-surface card.

## Verify first

- `lab-docs/lang/lab-stdlib-math-nbody-pressure-p9-v0.md`
- `lang/igniter-vm/src/vm.rs`
  - bytecode `OP_CALL` arms for `sin/cos/sqrt/pi` and `det_sin/det_cos/det_sqrt`
  - `eval_ast` function-call dispatch around existing `stdlib.regexp` parity and binary-operator fallback
- `lang/igniter-vm/tests/stdlib_math_tests.rs`
- `lang/igniter-vm/tests/stdlib_math_det_tests.rs`
- existing HOF tests in `lang/igniter-vm/tests/vm_tests.rs`

Before changing code, reproduce or encode the P9 failing shape in a small test:

- collection of records with `theta : Float`
- `map(others, other -> sin(other.theta - theta_i))`
- `sum(...)`

If the P9 fixture lives outside this repository, create a minimal test fixture or direct VM test inside
`lang/igniter-vm/tests/` rather than depending on an external path.

## Required implementation

Add `eval_ast` parity for **exactly** these existing functions:

- fast surface: `sin`, `cos`, `sqrt`, `pi`
- qualified fast surface if already supported by `OP_CALL`: `stdlib.math.sin`, `stdlib.math.cos`,
  `stdlib.math.sqrt`, `stdlib.math.pi`
- deterministic surface: `det_sin`, `det_cos`, `det_sqrt`
- qualified deterministic surface if already supported by `OP_CALL`: `stdlib.math.det_sin`,
  `stdlib.math.det_cos`, `stdlib.math.det_sqrt`

Preserve P2/P5 semantics:

- fast `sin/cos/sqrt` remain platform f64 and may return platform results.
- `pi()` is zero-arg.
- `det_sin/det_cos` use `libm`.
- `det_sqrt` uses guarded `f64::sqrt`.
- `det_*` reject non-finite input and negative sqrt exactly like the bytecode path.
- no implicit Integer/Decimal coercion.
- arity/type/domain errors should match the bytecode path closely enough for tests and diagnostics.

Prefer a tiny shared helper over copy-pasting two divergent match blocks if that stays local and readable. The
important invariant is **one semantic source for OP_CALL and eval_ast** or a clearly mirrored implementation
with tests that catch drift.

## Acceptance

- [x] A minimal N-body coupling runtime test fails on current HEAD (or the proof doc records the current
      failure) and passes after the fix.
- [x] `map(others, other -> sin(other.theta - theta_i)) |> sum` runs and returns the expected value for a
      bounded N=3 case. Suggested sample: `theta_i = 0`, others `[0, π/2, π]` gives
      `sin(0) + sin(π/2) + sin(π) ≈ 1.0`.
- [x] The no-math control from P9 still runs.
- [x] `cos`, `sqrt`, and `pi` work inside an eval_ast/HOF lambda path, not only direct bytecode calls.
- [x] `det_sin/det_cos/det_sqrt` work inside an eval_ast/HOF lambda path and preserve golden-bit/domain
      semantics where applicable.
- [x] Negative `det_sqrt` and non-finite `det_*` inputs error inside eval_ast; no silent NaN/null.
- [x] Wrong arity/type errors inside eval_ast are deterministic and do not fall through to the binary-operator
      message (`Operator sin expects exactly 2 operands`).
- [x] Existing bytecode math tests still pass (`stdlib_math_tests`, `stdlib_math_det_tests`).
- [x] Existing regexp/decimal eval_ast parity remains green.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Fix:** one shared semantic source `pub fn eval_math_call(fn_name, args) -> Option<Result<Value,String>>`
(in `vm.rs`) now holds ALL Tier-1 math (fast P2 `sin/cos/sqrt/pi` + deterministic P5 `det_*`). The bytecode
`OP_CALL` path's 7 inline arms collapsed to one delegating arm; the `eval_ast` HOF/lambda operator-fallback
calls the same helper **before** the binary-operator assumption (which is what made a 1-arg `sin` error
"expects exactly 2 operands"). OP_CALL and eval_ast can no longer drift — one path, identical values/messages.
Proof doc: `lab-docs/lang/lab-stdlib-math-eval-ast-parity-p10-v0.md`.

**Result:** the P9 blocker is gone — `map(others, other -> sin(other.theta - theta_i)) |> sum` over
`[0, π/2, π]` runs and returns `1.0000000000000002` (tol 1e-12). cos/sqrt/pi and det_* all work inside HOFs;
det golden bits preserved inside fold; negative det_sqrt + non-finite errors inside eval_ast (no silent NaN);
arity errors give the math message, not the binary-op fallback.

**Tests/green:** `stdlib_math_hof_tests` **7** (direct P9-style map→sum sin, HOF sin/cos/sqrt/pi/det,
arity-msg + shared-source unit),
`stdlib_math_tests` **5** + `stdlib_math_det_tests` **6** (OP_CALL via the shared helper, no regression),
igniter-compiler `stdlib_math_tests` **5**, full VM suite green except the pre-existing unrelated `vmg13`
(git-stash-proven). `git diff --check` clean. Only `vm.rs` + one new test file touched (isolated from the
concurrent package-manager work).

**Next:** numeric basics (`abs/min/max/clamp/sign`), integer roots/mod, then the **N-body order-parameter
sweep + multi-step Kuramoto loop** — the full phase-transition experiment, now that math composes inside HOFs.

## Proof doc requirements

Write `lab-docs/lang/lab-stdlib-math-eval-ast-parity-p10-v0.md` with:

- the exact pre-fix blocker from P9;
- the implementation shape (shared helper vs mirrored arms);
- the N-body coupling result and tolerance;
- a table showing OP_CALL vs eval_ast parity for fast and deterministic functions;
- what remains out of scope.

Close this card with a report and exact test commands/counts.

## Closed scope

- No new stdlib functions (`abs/min/max/clamp/sign`, `isqrt`, `ipow`, `mod` belong to P7/P8).
- No new compiler/typechecker surface.
- No multi-step simulation loop.
- No performance benchmark.
- No qemu cross-arch proof.
- No broad refactor of `eval_ast` beyond local math dispatch parity.
- No canon claim; this is lab implementation evidence for scientific workloads.

## Next

After P10, the N-body scientific lane can split cleanly:

1. `LAB-STDLIB-MATH-NUMERIC-BASICS-P7` — N0 `abs/min/max/clamp/sign`.
2. `LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` — N1 `isqrt/ipow/mod`.
3. N-body order-parameter sweep / multi-step Kuramoto loop — only after eval_ast parity is green.
