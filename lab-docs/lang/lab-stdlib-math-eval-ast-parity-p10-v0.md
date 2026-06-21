# lab-stdlib-math-eval-ast-parity-p10-v0 — stdlib math inside HOF/lambda bodies

**Card:** `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` · **Delegation:** `OPUS-STDLIB-MATH-EVAL-AST-PARITY-P10`
**Status:** CLOSED (implementation proof) — Tier-1 stdlib math (fast P2 `sin/cos/sqrt/pi` + deterministic P5
`det_sin/det_cos/det_sqrt`) now works **inside `map`/`fold`/`filter` lambda bodies**, not only as direct
bytecode calls. Both the bytecode `OP_CALL` path and the `eval_ast` HOF path resolve math through **one shared
semantic source** (`eval_math_call`). **VM parity card — no new math surface, no compiler/typechecker change.**

## The pre-fix blocker (from P9)

```ig
compute terms = map(others, other -> sin(other.theta - theta_i))
compute coupling = sum(terms)
```
Compiles clean, but at runtime:
```text
VM evaluation failed: Operator sin expects exactly 2 operands; got 1
```
Root cause: P2/P5 wired math **only** into the bytecode `OP_CALL` dispatch. HOF/lambda bodies are evaluated by
the `eval_ast` tree-walker, where a 1-arg `sin` (AST node `{kind:"call", fn:"sin", args:[…]}`) fell to the
**binary-operator** fallback (`vm.rs` "Operator … expects exactly 2 operands"). The no-math control ran fine,
so records/capture/arithmetic/`map`/`sum` were never the blocker — only the math call.

## Implementation shape — one shared source (not mirrored arms)

A single free function is now the **only** place Tier-1 math semantics live:

```rust
pub fn eval_math_call(fn_name: &str, args: &[Value]) -> Option<Result<Value, String>>
//  None  → not a math fn (caller falls through to its own dispatch)
//  Some  → the value, or a deterministic error (arity / non-Float / det non-finite / det negative-sqrt)
```

- **`OP_CALL`** (bytecode): the seven inline P2/P5 arms were **replaced** by one delegating arm →
  `match eval_math_call(fn_name, &args) { Some(r) => r?, None => unreachable!() }`.
- **`eval_ast`** (HOF/lambda bodies): the math dispatch runs at the **top of the operator fallback**, *before*
  the binary-operator assumption — `if let Some(math) = eval_math_call(op, &evaluated_operands) { return math; }`.

So OP_CALL and eval_ast cannot drift: identical values, identical error messages, one code path. (Float-only,
no implicit coercion; `det_*` finite-guaranteed — non-finite input and negative `det_sqrt` are errors, never
NaN/null.)

## OP_CALL ↔ eval_ast parity (proven)

| function | OP_CALL (direct call) | eval_ast (inside map/fold/filter) |
|---|---|---|
| `sin` `cos` `sqrt` (fast f64) | ✓ (P2 tests) | ✓ (`cos_sqrt_pi_inside_fold_lambda`, `sin_inside_fold_lambda_runs`) |
| `pi()` (zero-arg) | ✓ | ✓ |
| `det_sin` `det_cos` (libm) | ✓ golden bits (P5) | ✓ golden bits inside HOF (`det_sin_inside_fold_lambda_is_golden`) |
| `det_sqrt` (IEEE + guard) | ✓ | ✓; negative → error (`det_sqrt_negative_inside_fold_lambda_errors`) |
| arity / non-Float / domain errors | math message | **same** math message, NOT the binary-op fallback (`arity_error_inside_lambda_is_math_message`) |

## The N-body coupling result

Post-fix, the exact P9 shape runs (real compiler + VM `run`):

```text
CouplingSum(theta_i=0, others=[0, π/2, π]) → 1.0000000000000002
  = sin(0) + sin(π/2) + sin(π)   (the 2e-16 tail is sin(π) ≈ 1.2e-16)
```
HOF test tolerance: `|result − 1.0| < 1e-12` (well clear of the f64 tail). The no-math control still runs
(`other.theta − theta_i` → 4.712…).

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_hof_tests     → 7 passed (NEW: map→sum sin; sin/cos/sqrt/pi/det inside HOF; arity msg; shared-source unit)
$ cd lang/igniter-vm && cargo test --test stdlib_math_tests         → 5 passed (P2 OP_CALL, now via the shared helper — no regression)
$ cd lang/igniter-vm && cargo test --test stdlib_math_det_tests     → 6 passed (P5 OP_CALL golden bits, via the shared helper)
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests   → 5 passed (typecheck, untouched)
$ cd lang/igniter-vm && cargo test                                  → green EXCEPT one pre-existing, unrelated failure (below)
$ git diff --check                                                  → clean
```

New HOF tests exercise the real `eval_ast` path via the VM's `Compiler` (the exact `array_literal` + `map` /
`fold` + `call` AST the compiler emits) + `VM::execute`. The `shared_source_values_and_errors` unit test pins
`eval_math_call` directly (the one source both paths use).

**Pre-existing unrelated VM failure** (same as P2/P5): `vm_candidate_proof_tests::
test_proof_vmg13_local_loops_and_service_loops` (`OP_GET_FIELD: expected Record, got Integer(<unix-ts>)`) — a
service-loop/temporal test, fails on clean HEAD (git-stash-proven in P2), unrelated to math dispatch.

## Acceptance — mapping

- [x] Pre-fix blocker recorded (P9) and the same shape now passes (`sin_inside_fold_lambda_runs`).
- [x] `map(others, other -> sin(other.theta - theta_i)) |> sum` returns ≈1.0 for N=3 `[0, π/2, π]`.
- [x] The no-math control still runs.
- [x] `cos`, `sqrt`, `pi` work inside an eval_ast/HOF lambda, not only direct bytecode.
- [x] `det_sin/det_cos/det_sqrt` work inside HOF and preserve golden-bit / domain semantics.
- [x] Negative `det_sqrt` and non-finite `det_*` error inside eval_ast; no silent NaN/null.
- [x] Wrong arity/type errors inside eval_ast are the math message, not "expects exactly 2 operands".
- [x] Existing bytecode math tests pass (`stdlib_math_tests`, `stdlib_math_det_tests`).
- [x] Existing regexp/decimal eval_ast parity remains green (full VM suite green except the isolated `vmg13`).
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-vm/src/vm.rs` — added `pub fn eval_math_call` (single source); OP_CALL math arms collapsed to
  one delegating arm; eval_ast operator-fallback dispatches it before the binary-operator assumption.
- `lang/igniter-vm/tests/stdlib_math_hof_tests.rs` — new, 7 tests.

## Out of scope

No new stdlib functions (`abs/min/max/clamp/sign`, `isqrt/ipow/mod` are N0/N1 cards); no compiler/typechecker
change; no multi-step simulation loop; no perf benchmark; no qemu cross-arch proof; no broad `eval_ast`
refactor beyond local math dispatch parity.

## Next

The N-body scientific lane is now unblocked: (1) `LAB-STDLIB-MATH-NUMERIC-BASICS` (`abs/min/max/clamp/sign`),
(2) integer roots/mod, (3) the **N-body order-parameter sweep** and **multi-step Kuramoto loop** — the full
phase-transition experiment from the emergence charter, now that math composes inside HOFs.

---

*Implementation proof. 2026-06-21. Tier-1 math (fast + deterministic) now composes inside `map`/`fold`/`filter`
lambdas — one shared `eval_math_call` source for the bytecode `OP_CALL` and the `eval_ast` HOF paths, so they
cannot drift. The P9 N-body coupling runs (≈1.0); 7 HOF + 5 fast + 6 det tests green; one pre-existing
unrelated VM failure isolated; `git diff --check` clean.*
