# lab-stdlib-math-nbody-sweep-p11-v0 — N-body Kuramoto order parameter (det_* over a collection)

**Card:** `LAB-STDLIB-MATH-NBODY-SWEEP-P11` · **Type:** proof / scientific pressure
**Status:** CLOSED — a real Kuramoto-style **order parameter** `r = (1/N)·sqrt((Σcosθ)² + (Σsinθ)²)` computes
over a `Collection[Float]` of phases through the **real compiler + VM**, using the deterministic `det_*`
surface inside HOF fold lambdas. Synchronized → exactly `1.0`; quarter-spread → `0`; P9 sample → `1/3`.
**Builds on P5 (`det_sin/det_cos/det_sqrt`) + P10 (math inside HOF/lambda bodies). No new stdlib functions.**

## Result

| Phases | N | Σcos | Σsin | r | assertion |
|---|---|---|---|---|---|
| `[0,0,0]` | 3.0 | 3 | 0 | **1.0** | exact (`(r−1).abs()<1e-12`) — `det_sqrt(9)=3`, `/3=1` |
| `[0, π/2, π]` (P9 sample) | 3.0 | ≈0 | ≈1 | **≈1/3** | `<1e-9` |
| `[0, π/2, π, 3π/2]` (quarter spread) | 4.0 | ≈0 | ≈0 | **≈0** | `<1e-9` |

All through `igniter_vm::compiler::Compiler` → `VM::execute` (real bytecode, not hand-built). A
**fast-surface** (`sin/cos/sqrt`) run of the P9 sample matches `1/3` within `1e-9` (secondary check).

## What this proves (the card's questions)

1. **`det_*` composes through collection folds in a realistic order-parameter expression — YES.** Two folds
   (`Σcos`, `Σsin`) nest as **sub-expressions** inside `sqrt((·)²+(·)²)/N`. **No fold-as-subexpression
   blocker** — `map_reduce_aggregate` composes compositionally; this was the main open risk and it is clear.
2. **`Collection[Float]` is enough, AND `Collection[Oscillator]` record-field access also works.** The Float
   path runs end-to-end **with values** (VM test). The record shape (`Collection[Oscillator]`,
   `o.theta` accessed inside the fold lambda) **compiles + typechecks clean** (status ok, all stages) — no
   compile blocker. A record-path *VM-value* run is the only deferred step (needs record-literal AST), not a
   fundamental gap.
3. **Smallest remaining scientific blocker = the multi-step time-integration loop**, not the math. A *single*
   order parameter computes cleanly; a *full* Kuramoto sim needs a bounded loop iterating the micro-rule over
   evolving phase state. Secondary minor limitation: **N is a fixed Float literal** (`3.0`/`4.0`) — there is
   no `count→Float` / Integer→Float cast (deliberately not opened here; numeric-tower territory).
4. **Does NOT require P7 numeric basics.** Tier-1 `det_*` + HOF parity (P10) carry it; no `abs/min/max/clamp`
   needed for an order parameter. (P7 basics serve control/guidance, a different pressure.)
5. **Replay/golden vs tolerance:** mixed and stated conservatively. Where the math is exact (perfect squares
   / zeros) the result is **exact** (synchronized `[0,0,0]` → `1.0` to the bit, since `det_sqrt(9)=3.0`).
   Where `det_cos(π/2)≈6e-17` etc. enter, results are **tolerance-based** until the qemu cross-arch CI
   (deferred per P3/P5). So: golden-bit for det *unit* values (already locked in P5/P10), tolerance for the
   sweep until cross-arch CI.

## Why `det_*` (not the fast surface) for the primary proof

`det_sin/det_cos` are the deterministic (golden-bit-locked, vendored pure-Rust libm) surface from P5;
`det_sqrt` is IEEE-correct `f64::sqrt` with a finite-domain guard. Using them makes the order parameter
**replay-safe by construction** (the emergence-line thesis) — the same phases yield the same `r` bits on any
node running the same stdlib surface. The fast surface is kept only as a secondary tolerance check.

## The proof shapes

**Authored `.ig`** (compiles clean through `igc`; `igniter-home-lab/apps/emergence/kuramoto/nbody_order.ig`):

```ig
pure contract OrderParameter {
  input phases : Collection[Float]
  compute sum_cos : Float = fold(phases, 0.0, (acc, theta) -> acc + det_cos(theta))
  compute sum_sin : Float = fold(phases, 0.0, (acc, theta) -> acc + det_sin(theta))
  compute mag2 : Float = (sum_cos * sum_cos) + (sum_sin * sum_sin)
  compute r : Float = det_sqrt(mag2) / 3.0
  output r : Float
}
```

(Record variant `nbody_order_record.ig` — `Collection[Oscillator]` + `o.theta` — also compiles clean.)

**VM value proof** (`lang/igniter-vm/tests/stdlib_math_nbody_tests.rs`): builds the same shape as the
compiler-emitted AST — `map_reduce_aggregate{fold: acc + det_cos(theta)}` nested inside
`binary_op "/" { left: det_sqrt(Σcos²+Σsin²), right: N }` — compiles via `Compiler`, runs via `VM::execute`,
asserts the table above. Plus building-block anchors (`Σcos≈0`, `Σsin≈1` for the P9 sample) to isolate any
nesting regression.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test stdlib_math_nbody_tests   → 5 passed; 0 failed
  (sum_cos_and_sum_sin_via_fold, order_param_synchronized_is_one, order_param_p9_sample_is_one_third,
   order_param_quarter_spread_is_zero, order_param_fast_surface_matches)
$ igc compile nbody_order.ig        → status: ok (parse/typecheck/classify/emit/assemble)
$ igc compile nbody_order_record.ig → status: ok (Collection[Oscillator], o.theta in fold)
$ git diff --check                  → clean
```

## Acceptance — mapping

- [x] A minimal order-parameter fixture/test encoded in VM tests (`stdlib_math_nbody_tests.rs`, 5 tests).
- [x] Primary proof uses `det_sin/det_cos/det_sqrt`.
- [x] Synchronized case returns exactly `1.0` (`<1e-12`).
- [x] Spread case ≈ `0.0` and P9 sample ≈ `1/3` (both `<1e-9`).
- [x] Record-based `Collection[Oscillator]` attempted — compiles+typechecks clean (VM-value run deferred), documented.
- [x] Runs through real compiler + VM, not only hand-built bytecode.
- [x] No new stdlib functions; no time-integration loop introduced.
- [x] `git diff --check` clean.

## Remaining blockers (ranked)

1. **Multi-step time-integration loop** — the next real scientific pressure (iterate the Kuramoto micro-rule
   over evolving phases). Needs a bounded loop over mutable/threaded state. **Highest.**
2. **`count`/N → Float** ergonomics — N is a literal today; a `Collection.count` → Float bridge (or an
   Integer→Float cast) would let `r` use the actual collection size. Minor; numeric-tower-adjacent.
3. **Record-path VM-value run** — record shape compiles; executing it for a value needs record-literal AST
   construction (or an igc-`.igapp`→VM value bridge, since `igniter-vm trace` surfaces execution not the
   return value). Low — no fundamental blocker indicated.

## Files

- `lang/igniter-vm/tests/stdlib_math_nbody_tests.rs` (new; 5 tests; isolated from the P10 HOF test file).
- `igniter-home-lab/apps/emergence/kuramoto/nbody_order.ig` + `nbody_order_record.ig` (authored sources).

## Closed scope (honored)

No full Kuramoto time integration; no loop/fuel work; no UI/charting; no benchmark; no new math functions; no
Decimal/fixed-point; no qemu cross-arch proof; no canon claim.

## Next

**`LAB-STDLIB-MATH-KURAMOTO-LOOP-P12`** — a bounded multi-step Kuramoto integration (iterate the micro-rule
`θ_i += dt·(ω_i + (K/N)Σ sin(θ_j−θ_i))` for a few steps over a small N), measuring `r(t)` rising toward
synchronization — the first *dynamical* emergence proof. Routes through whatever loop/iteration construct the
language offers; if that construct is missing, the card becomes a loop-readiness pressure finding.

---

*Lab proof. 2026-06-21. The Kuramoto order parameter runs over a collection through the real compiler+VM on
the deterministic `det_*` surface — synchronized phases give exactly `1.0`, spread gives `0`, the P9 sample
gives `1/3`. Folds compose as sub-expressions (no nesting blocker); records compile; the next pressure is the
time-integration loop, not the math.*
