# lab-stdlib-math-kuramoto-proof-p4-v0 — clean Kuramoto pressure proof on Tier-1 math

**Card:** `LAB-STDLIB-MATH-KURAMOTO-PROOF-P4` · **Delegation:** `OPUS-STDLIB-MATH-KURAMOTO-PROOF-P4`
**Status:** CLOSED (proof / downstream pressure) — a bounded N=2 Kuramoto slice now uses `stdlib.Math` Tier-1
(`sin`/`cos`/`sqrt`) **directly**, with **no hand-rolled Taylor**, compiles through the real compiler, and
**executes with an asserted numeric output** through `igniter-vm run`. The P1 pressure loop is fully closed.
**No det.* / no collection model / no sim loop / no coercion changes.**

## What was built

A scalar, all-Float, collection-free fixture — `igniter-home-lab/apps/emergence/kuramoto/kuramoto_proof.ig`:

- **`KuramotoR2`** — the Kuramoto **order parameter** for two oscillators:
  `r = (1/2)·sqrt((cos ti + cos tj)² + (sin ti + sin tj)²)` (native `cos`/`sin`/`sqrt`).
- **`KuramotoStep2`** — one explicit-Euler **phase-coupling step** (the micro-rule):
  `ti' = ti + dt·(ω + (K/N)·sin(tj − ti))`, K=1.0, N=2, ω=1.0, dt=0.1 (native `sin`).

No Taylor helper, no `Collection`, every literal Float (`0.5`, `1.0`, `2.0`, `0.1`).

## Numeric proof (live, through the real compiler + VM `run`)

`igc compile … && igniter-vm run --contract k.igapp --entry <C> --inputs <json> --json` → reads `result`:

| call | inputs | `result` | expected |
|---|---|---|---|
| `KuramotoR2` (synchronized) | ti=0.0, tj=0.0 | **1.0** | r=1 |
| `KuramotoR2` (synchronized at π/2) | ti=tj=1.5707963… | **1.0** | r=1 |
| `KuramotoR2` (anti-phase) | ti=0.0, tj=π | **6.12e-17** | r≈0 |
| `KuramotoStep2` (coupling step) | ti=0.0, tj=π/2 | **0.15000000000000002** | 0.15 |

The order parameter behaves exactly as the physics requires — **r=1 fully synchronized, r≈0 anti-phase** (the
`6.12e-17` residue is IEEE rounding of `sin(π)`). That r→{0,1} split is itself a tiny emergence signature,
recovered on the Igniter substrate with native math.

## Questions answered

1. **Smallest meaningful slice:** the **tiny order parameter** (r — *the* Kuramoto emergence observable) plus
   one **pair-coupling step**. Both are scalar and assertable; together they exercise `sin`, `cos`, `sqrt`.
2. **Numeric output runner:** **YES** — `igniter-vm run --json` surfaces `{"status":"success","result":…}`
   (`main.rs` execute path → `output.to_json()`). This **corrects the P2 note** that only `trace` (which
   reports `result_status`, not the value) was available. So a real numeric assertion is included, not just a
   status.
3. **Taylor removed:** **YES** — the P1 11-line Taylor `sin` is gone; `compute coupling : Float = sin(dphase)`
   and `sin/cos` in the order parameter call P2 stdlib directly.
4. **Collection pressure:** avoided by design — N=2 scalar pair, no `map`/`fold`. The N-body all-to-all sum
   over a `Collection[Oscillator]` is the **next** pressure (deferred, listed below) so P4 stays clean.
5. **Remaining blockers:** see below.

## Remaining emergence blockers (precise)

The fast-f64 scalar slice runs; a *full* Kuramoto experiment still needs:

1. **N-body via collections** — all-to-all coupling `Σ_j sin(θ_j − θ_i)` over a `Collection[Oscillator]`
   (record array) using `map`/`fold`. Whether record-field access inside a fold lambda composes cleanly is
   unverified → the next pressure card.
2. **Simulation loop** — iterating the Euler step over many timesteps. Either a host loop calling `run`
   repeatedly (state passed in/out) or an in-`.ig` accumulator loop (PROP-039) over a step count. Unproven
   for this shape.
3. **Deterministic math (`det.*`)** — fast f64 is platform-dependent; sim↔ESP32-swarm bit-identity needs the
   P3-readiness `det.*` track. Required for Stage 3, not Stage 1.
4. **Seeded ω sampling** (Lorentzian g(ω)) — no stdlib RNG; sidestep by precomputing ω offline as Float data,
   or a future `stdlib` PRNG. Not blocking a fixed-input proof.
5. **Output ergonomics** — `run --json` gives one result value; multi-series/plotting is external (out of
   scope, by design).

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests   → 4 passed (3 P2 + 1 NEW P4 Kuramoto compile-lock)
$ cd lang/igniter-vm && cargo test --test stdlib_math_tests         → 5 passed (P2 numeric, unaffected)
$ igc compile kuramoto_proof.ig --out k.igapp                       → status: ok
$ igniter-vm run --contract k.igapp --entry KuramotoR2 --inputs '{"ti":0.0,"tj":0.0}' --json   → result: 1.0
$ git diff --check                                                  → clean
```

The compile-lock (`kuramoto_order_parameter_slice_compiles_clean`) asserts the slice compiles on the Tier-1
surface AND that the fixture contains no Taylor (`5040`); the numeric behavior is locked by the live `run`
results above + the P2 VM numeric tests for `sin/cos/sqrt` that the order parameter composes.

## Acceptance — mapping

- [x] Fixture contains no hand-rolled Taylor/trig approximation.
- [x] Fixture uses P2 `stdlib.Math` Tier-1 calls through the real language surface (bare `sin/cos/sqrt`).
- [x] Compiler path green.
- [x] VM execution path green (`run` succeeds).
- [x] Numeric assertion included (runner supports it — `run --json`; r=1.0 / r≈0 / step=0.15).
- [x] Remaining emergence blockers listed precisely.
- [x] Existing P2 tests still green.
- [x] `git diff --check` clean.

## Files

- `igniter-home-lab/apps/emergence/kuramoto/kuramoto_proof.ig` (new fixture; private research repo).
- `lang/igniter-compiler/tests/stdlib_math_tests.rs` (+1 Kuramoto compile-lock test).

## Closed scope

No simulation UI/charting; no `det.*`; no perf benchmark beyond the smoke run; no Integer/Float coercion; no
N-body collection model (the next pressure).

## Next

`LAB-EMERGENCE-KURAMOTO-NBODY-PRESSURE-P5` — push the N-body all-to-all coupling over a
`Collection[Oscillator]` (map/fold of the coupling sum) to surface the next stdlib/language pressure; and/or
`LAB-STDLIB-MATH-DET-TIER1-P4` (deterministic math) before the Stage-3 swarm. Either unblocks the full
phase-transition sweep from the emergence charter.

---

*Proof / downstream pressure. 2026-06-21. A bounded N=2 Kuramoto slice (order parameter + coupling step) runs
on native Tier-1 math with an asserted numeric output (r=1.0 synchronized, r≈0 anti-phase) via `igniter-vm
run --json`; no Taylor, no collections; 4 compiler + 5 VM math tests green; `git diff --check` clean. The P1
pressure is closed; the next pressure is N-body collections.*
