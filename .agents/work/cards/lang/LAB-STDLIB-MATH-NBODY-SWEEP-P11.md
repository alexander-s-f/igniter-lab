# LAB-STDLIB-MATH-NBODY-SWEEP-P11 — N-body Kuramoto order-parameter proof after HOF parity

Status: CLOSED
Lane: standard / stdlib math + scientific pressure
Type: proof / pressure
Delegation code: OPUS-STDLIB-MATH-NBODY-SWEEP-P11
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-MATH-NBODY-PRESSURE-P9` — found the eval_ast math parity blocker.
- `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — fixed Tier-1 math inside HOF/lambda bodies.
- `LAB-STDLIB-MATH-DET-TIER1-P5` — deterministic `det_sin/det_cos/det_sqrt` surface.

P9 proved the language can express N-body coupling at compile time but runtime failed on math inside lambdas.
P10 removed that blocker. Now we need the next scientific pressure proof: not a full simulator, but a real
N-body order-parameter calculation over a collection.

## Goal

Build a bounded proof that Igniter can compute a Kuramoto-style order parameter over a collection:

```text
r = (1/N) * sqrt((Σ cos(theta_j))^2 + (Σ sin(theta_j))^2)
```

Use a small N (3 or 4) and run through the real compiler + VM. Prefer the deterministic `det_*` surface for the
primary proof if it works inside HOFs after P10; optionally compare the fast surface as a secondary check.

This is a scientific pressure proof, not a broad simulator or benchmark.

## Verify first

- `lab-docs/lang/lab-stdlib-math-nbody-pressure-p9-v0.md`
- `lab-docs/lang/lab-stdlib-math-eval-ast-parity-p10-v0.md`
- `lang/igniter-vm/tests/stdlib_math_hof_tests.rs`
- existing collection/map/fold/sum tests in VM/compiler.
- current support for division by Float / Integer-to-Float literal style.

Start with the smallest shape that runs. If a clean `Collection[Oscillator]` record shape is too heavy, use
`Collection[Float]` first and document the record-shape blocker separately. Do not hide a runtime blocker behind
handwritten constants.

## Preferred proof shape

Try this order:

1. `Collection[Float]` phases, with two HOF reductions:
   - `sum_cos = fold(phases, 0.0, (acc, theta) -> acc + det_cos(theta))`
   - `sum_sin = fold(phases, 0.0, (acc, theta) -> acc + det_sin(theta))`
   - `r = det_sqrt(sum_cos*sum_cos + sum_sin*sum_sin) / n_float`
2. If that runs, try `Collection[Oscillator]` with `theta` field access.
3. If division or count/N conversion is awkward, use a fixed Float denominator literal for N and document the
   limitation. Do not open a numeric tower/card inside this proof.

Suggested test cases:

- synchronized `[0, 0, 0]` -> `r = 1.0`
- quarter spread `[0, π/2, π, 3π/2]` -> `r ≈ 0.0`
- P9 sample `[0, π/2, π]` -> `r = 1/3` within tolerance (because vector sum magnitude ≈1)

## Questions to answer

1. Does `det_sin/det_cos/det_sqrt` compose through collection folds in a realistic order-parameter expression?
2. Is `Collection[Float]` enough, or does `Collection[Oscillator]` record-field access still run after P10?
3. What is the smallest remaining scientific blocker: numeric basics, integer roots/mod, loops, type inference,
   collection ergonomics, or performance?
4. Does the proof require P7 numeric basics, or can Tier-1 + HOF parity carry it?
5. Is the result stable enough for replay-style golden tests, or should this stay tolerance-based until
   cross-arch CI exists?

## Acceptance

- [x] A minimal order-parameter fixture/test is added or encoded in VM tests. (`stdlib_math_nbody_tests.rs`, 5 tests.)
- [x] The primary proof uses `det_sin/det_cos/det_sqrt` unless a live blocker makes that impossible. (det_* used; no blocker.)
- [x] Synchronized case returns exactly or approximately `1.0` with a stated tolerance. (`[0,0,0]`→1.0, `<1e-12`.)
- [x] Spread case returns approximately `0.0` or the P9 sample returns approximately `1/3`. (BOTH: spread≈0, P9≈1/3.)
- [x] If record-based `Collection[Oscillator]` is attempted, success/blocker is documented precisely. (compiles+typechecks clean; VM-value run deferred.)
- [x] The proof runs through real compiler + VM, not only hand-built bytecode. (`Compiler`→`VM::execute`.)
- [x] No new stdlib functions are introduced.
- [x] No multi-step loop or time integration is introduced.
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-math-nbody-sweep-p11-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Proof:** the Kuramoto order parameter `r = (1/N)·sqrt((Σcosθ)² + (Σsinθ)²)` computes over a
`Collection[Float]` through the **real compiler + VM** (`Compiler`→`VM::execute`), using deterministic
`det_sin/det_cos/det_sqrt` inside HOF fold lambdas. Results: synchronized `[0,0,0]`→**1.0 exact** (`<1e-12`),
P9 sample `[0,π/2,π]`→**1/3** (`<1e-9`), quarter-spread `[0,π/2,π,3π/2]`→**0** (`<1e-9`); a fast-surface
secondary run matches. `lang/igniter-vm/tests/stdlib_math_nbody_tests.rs` = 5 passed.

**Key finding — no fold-as-subexpression blocker:** `map_reduce_aggregate` composes compositionally, so two
folds (`Σcos`, `Σsin`) nest cleanly inside `sqrt((·)²+(·)²)/N`. The main open risk is cleared. Both
`Collection[Float]` (proven with values via VM) and `Collection[Oscillator]` record-field access (`o.theta`
in the fold lambda — compiles+typechecks clean via `igc`) work; only the record *VM-value* run is deferred
(needs record-literal AST). **No P7 numeric basics required** — Tier-1 `det_*` + P10 HOF parity carried it.

**Smallest remaining scientific blocker = the multi-step time-integration loop** (not the math). Minor:
`count`→Float (N is a Float literal today). Replay: exact where math is exact (synchronized→1.0 to the bit),
tolerance-based otherwise until qemu cross-arch CI (P3/P5). This is a fixed-algorithm/golden-vector lab claim,
not a physical multi-device identity claim.

**Artifacts:** proof doc `lab-docs/lang/lab-stdlib-math-nbody-sweep-p11-v0.md`; authored `.ig` in
`igniter-home-lab/apps/emergence/kuramoto/{nbody_order,nbody_order_record}.ig`. No new stdlib fns; no code
touched outside the new test file (neighbor's P5–P10 + package-mgr untouched); `git diff --check` clean.

**Next:** `LAB-STDLIB-MATH-KURAMOTO-LOOP-P12` — bounded multi-step Kuramoto integration measuring `r(t)`
rising toward synchronization (the first *dynamical* emergence proof); becomes a loop-readiness finding if
the language lacks the iteration construct.

## Proof doc requirements

Include:

- the exact authored `.ig` or test AST shape;
- numeric expected values and tolerances;
- whether `det_*` was used and why;
- record-vs-float collection result;
- remaining blockers ranked;
- next-card recommendation.

## Closed scope

- No full Kuramoto time integration.
- No loop/fuel work.
- No UI/charting.
- No performance benchmark except a tiny observation if it falls out naturally.
- No new math functions.
- No Decimal/fixed-point work.
- No qemu cross-arch proof.
- No canon claim.

## Next

Depending on the blocker:

- if math surface is enough: open a multi-step Kuramoto loop proof;
- if ergonomics hurt: open a collection/scientific-authoring card;
- if runtime is slow: open a proto-benchmark card;
- if numeric basics are needed: route to `LAB-STDLIB-MATH-NUMERIC-BASICS-P7`.
