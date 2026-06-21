# lab-stdlib-math-nbody-pressure-p9-v0 — N-body collection pressure surfaces an eval_ast parity gap

**Card:** `LAB-STDLIB-MATH-NBODY-PRESSURE-P9` · **Delegation:** `OPUS-STDLIB-MATH-NBODY-PRESSURE-P9`
**Status:** CLOSED (pressure finding) — the N-body Kuramoto coupling `Σ_j sin(θ_j − θ_i)` over a
`Collection[Oscillator]` **compiles cleanly** but **fails at runtime** with one precise blocker: a stdlib
**math call inside a HOF lambda body** is evaluated by `eval_ast`, which lacks the unary-math dispatch and
routes `sin` to its binary-operator handler. **Pressure proof only — no language change (per card scope).**

## What was attempted (the clean form — and it typechecks)

`igniter-home-lab/apps/emergence/kuramoto/nbody_coupling.ig`:

```ig
type Oscillator { theta : Float  omega : Float }

contract CouplingSum {
  input theta_i : Float
  input others  : Collection[Oscillator]
  compute terms    = map(others, other -> sin(other.theta - theta_i))   -- math INSIDE a lambda
  compute coupling = sum(terms)
  output coupling : Float
}
```

`igc compile` → **`parse: ok`, `typecheck: ok`, `status: ok`.** The language **expresses** N-body coupling
at the type level: a user `type` with `Float` fields, `Collection[Oscillator]`, `map` with a lambda doing
**record-field access** (`other.theta`), **capture of an outer input** (`theta_i`), a **stdlib call**
(`sin`), and `sum` over `Collection[Float]` — all infer and compile.

## The blocker (exact, runtime)

```text
$ igniter-vm run --entry CouplingSum …
  status: error — "VM evaluation failed: Operator sin expects exactly 2 operands; got 1"
```

`sin` called *inside the map lambda* is evaluated by the **`eval_ast` tree-walker** (which runs HOF/lambda
bodies), not the **bytecode `OP_CALL`** dispatch. P2/P5 wired stdlib math (`sin/cos/sqrt/pi`, `det_*`) **only
into the `OP_CALL` path** (`vm.rs` ~line 2060). In `eval_ast`, an unknown single-arg call falls through to
the **binary-operator** handler (`vm.rs` ~line 5274, "Operator {} expects exactly 2 operands; got {}"), so
`sin` with one operand errors. This is the **eval_ast↔bytecode parity gap** flagged (but not hit) back in P2.

## Isolation control (airtight classification)

The same lambda shape with the **math call removed** runs perfectly
(`apps/emergence/kuramoto/nbody_control.ig`):

```ig
compute terms = map(others, other -> other.theta - theta_i)   -- field + capture + arithmetic, NO math
compute total = sum(terms)
```

```text
$ igniter-vm run --entry DiffSum --inputs {θ_i=0, others=[0, π/2, π]} …
  status: success — result: 4.71238898038469      (= 0 + π/2 + π)
```

So **record-field access, closure capture of an outer input, Float arithmetic, `map`, and `sum` all execute
correctly inside `eval_ast` lambda bodies.** The *only* thing that fails is a **stdlib math call inside the
lambda**. The blocker is isolated to a single cause.

## Questions answered

1. **Record-field access inside lambdas — typecheck & run?** **Yes, both** (control runs; real apps use
   `filter(e -> e.field == …)`).
2. **`sum`/`map` over Float compose with `sin`?** **At compile time, yes** (clean typecheck). **At runtime,
   no** — only because `sin` inside the lambda hits the `eval_ast` gap. `map`/`sum` over plain Floats run.
3. **Main blocker classification:** **VM execution coverage** — specifically the **`eval_ast` lambda-body
   call dispatch lacks the P2/P5 stdlib math functions**. NOT math (the functions exist), NOT collections
   (`map`/`sum`/`fold` work — see `apps/igniter-apps/sim_framework`), NOT record inference (field access +
   capture work), NOT loops (single-step, no loop needed), NOT typechecking (compiles clean).
4. **Need Tier-2 (`abs/min/max/clamp/mod`)?** **No.** Tier-1 `sin` alone surfaces the blocker; the blocker
   is dispatch parity, not a missing math function. Broadening math now would not help.
5. **Smallest next card:** wire the P2/P5 stdlib math (`sin/cos/sqrt/pi` + `det_*`) into the **`eval_ast`
   function-call dispatch** (the HOF/lambda-body path), mirroring the `OP_CALL` arms — a small, targeted
   parity fix. Then `CouplingSum` runs and N-body Kuramoto is unblocked.

## Acceptance — mapping

- [x] A minimal N-body/Kuramoto collection fixture attempted against the real compiler (compiles clean).
- [x] VM execution attempted; the exact runtime error captured.
- [x] Exact diagnostic captured ("Operator sin expects exactly 2 operands; got 1").
- [x] Blocker classified: **VM execution (eval_ast↔bytecode parity)** — not math/collection/record/loop.
- [x] No broad language changes in this card (pressure proof only).
- [x] Proof doc written with next-card recommendation.
- [x] `git diff --check` clean (only fixtures added, in the private home-lab repo).

## Files

- `igniter-home-lab/apps/emergence/kuramoto/nbody_coupling.ig` (compiles; fails at runtime — the pressure).
- `igniter-home-lab/apps/emergence/kuramoto/nbody_control.ig` (the no-math isolation control; runs = 4.712…).

## Closed scope

No production fix (the parity wiring is the next card); no full simulator/charting; no deterministic-math
change; no multi-step loop; no perf benchmark.

## Next

`LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — dispatch P2/P5 Tier-1 math (`sin/cos/sqrt/pi` + `det_*`) in the
`eval_ast` HOF/lambda-body call path so math works inside `map`/`fold`/`filter` lambdas (mirror the `OP_CALL`
arms; same f64/libm + finite guards). Acceptance = `CouplingSum` runs and returns ≈1.0 for the
[0, π/2, π] inputs. After that, the N-body order-parameter sweep and the multi-step simulation loop.

---

*Pressure finding. 2026-06-21. N-body Kuramoto coupling compiles (type-level expression is clean — records,
collections, capture, `map`/`sum` all infer) but a stdlib math call inside a HOF lambda fails: `eval_ast`
(lambda-body evaluator) lacks the P2/P5 math dispatch that only the bytecode `OP_CALL` path has, and routes
`sin` to the binary-operator handler. Isolated by a no-math control that runs cleanly. Blocker = eval_ast↔
bytecode parity; fix = one targeted dispatch addition (next card). `git diff --check` clean.*
