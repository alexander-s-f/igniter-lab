# lab-stdlib-math-tier2-readiness-p6-v0 — the next numeric surface after Tier-1

**Card:** `LAB-STDLIB-MATH-TIER2-READINESS-P6` · **Type:** readiness / design (NO code)
**Status:** CLOSED (readiness) — taxonomizes the next math surface and splits it into bounded impl cards,
**ranked by live app-pressure** (not by guesswork). Authority: lab readiness; the canon numeric PROP route is
governance-owned (this feeds it as evidence).

## Live surface after P2/P5 (verified)

`lang/igniter-stdlib/stdlib/math.ig` now:
- **Decimal:** `add/sub/mul/div` (scale-constrained).
- **Float (P2, fast f64):** `sin/cos/sqrt`, `pi()`. Diagnostics `OOF-MATH1` (arity), `OOF-MATH2` (non-Float arg).
- **Deterministic Tier-1 (P5):** flat `det_sin/det_cos/det_sqrt`, local golden-bit locked, finite-only,
  stdlib surface version bumped to `0.1.1`; cross-arch confirmation deferred to qemu CI.

So algebra + Tier-1 transcendentals exist; the gap is **scalar numeric basics, integer roots/powers, and a
few rounding/modulo ops** — plus a longer tail of advanced transcendentals.

## App-pressure evidence (this decides the order, per the card)

Raw substring counts across `lab-docs`/`apps` are **noise-contaminated** (`sign`→"design", `log`→"logic",
`round`→"around", `abs`→"absolute") and were discarded. The real evidence is in the app-pressure docs:

- **`igniter-stdlib-numeric-coverage-proposal-readiness-v0`** (grounded in **LAB-PURSUIT-P1**, the quadcopter
  pursuit/evasion guidance probe): the gap is *empirically* `abs/min/max/clamp/compare/neg/sign` and
  `isqrt/ipow` — **`clamp` and `abs` were hand-rolled with nested `if`** in `ZemGuidance`, and the whole probe
  was forced **sqrt-free** (`t_go = r²/(−r·v)`). It proposes **PROP-NUMERIC-CORE = N0 (`abs/min/max/clamp/
  compare/sign`) + N1 (`isqrt/ipow/imuldiv`)**, and notes `sin/cos/atan2/sqrt` needed "a prior decision
  (integer CORDIC vs f64)" — **now satisfied by P2 (f64) + P3 (det)**.
- **`lab-stdlib-numeric-fixed-point-readiness-v0`**: `neural_net` (Sigmoid hand-approximated with `if`-clamps,
  wants real `exp`), `vector_math` (milli-unit normalization, wants magnitude/`hypot`/`sqrt`).
- **`lab-stdlib-math-pressure-kuramoto-p1-v0`** (this line): Kuramoto needs phase wrap → a **Float remainder /
  range-reduction** (distinct from integer `mod`; folded into the det.sin reduction, P5).
- Air-combat / trade-robot / vector baselines repeat the same shapes: `abs`, `clamp`, magnitude, `min/max`.

**Verdict:** the highest *proven* pressure is **numeric basics (N0)** and **integer roots/powers (N1)** — not
the `exp/ln` of the card's tentative bias. `atan2` (guidance) and `exp` (real sigmoid) are real but second-wave.
This adjusts the bias exactly as the card invited.

## Candidate taxonomy (≥5, by type / domain / determinism need)

| Function | Types | Total? / domain | Deterministic need | Pressure |
|---|---|---|---|---|
| `abs(x)` | Integer, Float, Decimal[N] | total | **none — exact by construction** | **high** (hand-rolled LAB-PURSUIT) |
| `min(a,b)` / `max(a,b)` | same numeric T (no coercion) | total | none — comparison only | **high** |
| `clamp(x,lo,hi)` | same numeric T | total (define `lo>hi`) | none | **high** (hand-rolled LAB-PURSUIT) |
| `sign(x)` | Integer/Float/Decimal → Integer (−1/0/1) | total | none | high |
| `isqrt(x)` | Integer → Integer (floor) | `x<0` error | **exact by construction** (integer) | **high** (lifts sqrt-free constraint) |
| `ipow(base,exp)` | Integer → Integer | `exp<0` error; overflow policy | exact (integer) | medium-high |
| `mod`/`rem(a,b)` | Integer first | `b==0` error | exact (integer) | medium (CA/sandpile emergence are integer) |
| `floor/ceil/round(x)` | Float → Float (or →Integer cast, separate) | non-finite → policy | f64 rounding is exact/deterministic | medium |
| `atan2(y,x)` | Float | total (0,0 policy) | needs `det` (transcendental) | medium (guidance/vector) |
| `tan(x)` | Float | `cos=0` → ±Inf policy | needs `det` | low-med (`=sin/cos`) |
| `exp/ln(x)` | Float | `ln(x≤0)` error | needs `det` | low (real but second-wave: sigmoid) |
| `powf(b,e)` | Float | domain (neg base, etc.) | needs `det` | low |

**Key property worth stating:** the high-pressure tier (`abs/min/max/clamp/sign` + `isqrt/ipow/mod`) is
**deterministic by construction** — comparisons, sign flips, and integer arithmetic are bit-identical across
architectures with **no `det.*` variant required**. Only the Float transcendentals (`atan2/tan/exp/ln/powf`)
inherit the P3 determinism fork. So Tier-2's most-wanted functions are *also* the cheapest to make replay-safe.

## Answers to the card's questions

1. **Genuinely next:** N0 `abs/min/max/clamp/sign` first (empirically hand-rolled), then N1 `isqrt/ipow` + `mod`. `tan/exp/ln/atan2` are second-wave.
2. **Types:** N0 polymorphic over `{Integer, Float, Decimal[N]}`, same-type-in/out, **no implicit coercion**. `isqrt/ipow/mod` Integer-first. `floor/ceil/round` Float→Float (a Float→Integer cast is a separate question).
3. **Total vs errors:** N0 are **total** (big win). `isqrt(x<0)`, `ipow(exp<0)`, `mod`/`rem` by `0` are runtime domain errors. `floor/ceil/round` total on finite (non-finite → Q8 policy).
4. **`pow` split: YES** — `ipow(Integer, exp≥0) -> Integer` (N1, exact, bounded) is distinct from `powf(Float, Float) -> Float` (advanced, det-bearing). Never conflate.
5. **`mod` integer-only first: YES** — matches the scale-1000 fixed-point world and integer emergence models; a Float remainder (Kuramoto phase wrap) is range-reduction, owned by the det.sin work (P5), not this.
6. **`abs/min/max/clamp` before advanced transcendentals: YES** — evidence-backed (LAB-PURSUIT hand-rolled them; total; unlock control/physics/clamping with zero domain risk).
7. **Immediate `det` counterparts:** **none** for N0/N1 — they are exact by construction. Only the deferred Float transcendentals need `det` (already covered by P3).
8. **Non-finite Float (consistent policy):** reuse P3's verified hazard (non-finite `f64` → JSON `null` in the observation stream). Rule: prefer functions that **cannot** produce non-finite from finite inputs (all of N0/N1 qualify); where one can (`mod` by 0, `powf` overflow, `ln(≤0)`), return a **runtime domain error**, never let NaN/Inf escape to the lineage stream. A value-model non-finite policy is a separate future hardening.
9. **Diagnostics beyond OOF-MATH1/2:** add **`OOF-MATH3`** = numeric **type mismatch** / mixed-type args at compile time (e.g. `min(Integer, Float)` rejected — no coercion). Runtime domain errors (`isqrt(<0)`, `ipow(exp<0)`, `mod 0`) use a single runtime convention (a `OOF-MATH-DOMAIN` runtime class or the existing VM error path) — decide spelling in the impl card; compile-time stays OOF-MATH1/2/3.
10. **Exact impl cards:** below.

## Recommended split (evidence-adjusted)

**P7 — `LAB-STDLIB-MATH-NUMERIC-BASICS` (N0).** `abs/min/max/clamp/sign` over `{Integer, Float, Decimal[N]}`.
Total, no domain errors, **deterministic by construction (no `det.*`)**, no coercion. Highest proven pressure;
unblocks control/physics/clamping. *First card — small, total, high-value.*

| P7 acceptance | Target |
|---|---|
| Functions | `abs`, `min`, `max`, `clamp`, `sign` |
| Types | polymorphic `{Integer, Float, Decimal[N]}`, same-type in/out, no coercion |
| Totality | total; `clamp(lo>hi)` semantics documented (recommend `hi` wins, or compile note) |
| Determinism | exact by construction; **no det variant** (state explicitly) |
| Diagnostics | `OOF-MATH1` arity, `OOF-MATH3` type-mismatch/mixed-type |
| Tests | compile (valid + arity + mixed-type rejected) + VM exact-value (incl. Decimal scale preserved) |
| Scope | no rounding/roots/transcendentals |

**P8 — `LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD` (N1 + integer mod).** `isqrt`, `ipow`, integer `mod`/`rem`
(+ optionally `floor/ceil/round`). Integer-deterministic; **`isqrt` lifts the sqrt-free constraint** that
shaped LAB-PURSUIT; integer `mod` serves CA/sandpile emergence models.

| P8 acceptance | Target |
|---|---|
| Functions | `isqrt(Integer)→Integer`, `ipow(Integer,exp≥0)→Integer`, `mod`/`rem(Integer,Integer)`; (opt) `floor/ceil/round(Float)` |
| Domain errors | `isqrt(<0)`, `ipow(exp<0)`, `mod 0` → runtime domain error (never silent) |
| Algorithm | `isqrt` = bounded Newton/binary loop (deterministic); document iteration bound |
| Overflow | `ipow` overflow policy stated (saturate/error) |
| Determinism | exact by construction (integer); no det variant |
| Tests | known values + domain-error cases + bounded-loop termination |
| Scope | no Float transcendentals |

**Deferred — `LAB-STDLIB-MATH-ADVANCED-FLOAT-READINESS-Pn`** (`atan2/tan/exp/ln/powf`): readiness-first, opened
when real pressure lands (`atan2` for guidance/vector heading; `exp` for a true `neural_net` sigmoid). Each is
Float, det-bearing (inherits P3), with domain errors — heavier, lower current pressure, so not P7/P8.

## Relationship to governance (authority boundary)

This split aligns with the governance doc's **PROP-NUMERIC-CORE (N0+N1)**. The **canon PROP is governance-owned**;
P7/P8 are the **lab implementation cards** that produce executable evidence feeding that route. No canon claim
here. (The governance doc's "prior decision: CORDIC vs f64" precondition for trig is now closed by P2/P3.)

## Acceptance (this card) — mapping

- [x] Existing live math surface summarized (Decimal ×4 + Float sin/cos/sqrt/pi; OOF-MATH1/2).
- [x] ≥5 candidates categorized by type/domain/determinism (12 in the table).
- [x] App-pressure evidence cited from live docs (LAB-PURSUIT N0/N1, neural sigmoid, vector magnitude, Kuramoto mod).
- [x] Recommended split chosen (P7 N0 basics → P8 N1 roots+mod → deferred advanced Float), **evidence-adjusted vs bias**.
- [x] Diagnostics/domain policy proposed (`OOF-MATH3` type-mismatch; runtime domain-error convention; non-finite rule).
- [x] No production code changes.

## Closed scope

No implementation; no broad numeric tower; Decimal transcendentals only as a (deferred) recommendation; no
registry/package work; no canon PROP authored.

## Next

`LAB-STDLIB-MATH-NUMERIC-BASICS-P7` (N0 `abs/min/max/clamp/sign`, the small total high-value first card), then
`LAB-STDLIB-MATH-INTEGER-ROOTS-AND-MOD-P8` (`isqrt/ipow/mod`), with advanced Float transcendentals deferred to
a readiness card opened on real pressure.

---

*Lab readiness. 2026-06-21. Tier-2 ranked by live pressure: numeric basics (`abs/min/max/clamp/sign`, hand-rolled
in LAB-PURSUIT) and integer roots/powers (`isqrt/ipow`, lifting the sqrt-free constraint) come first and are
deterministic by construction; `mod` integer-first; advanced Float transcendentals (`atan2/tan/exp/ln/powf`)
deferred to real pressure. Split into P7 (N0) + P8 (N1+mod), aligned with governance PROP-NUMERIC-CORE.*
