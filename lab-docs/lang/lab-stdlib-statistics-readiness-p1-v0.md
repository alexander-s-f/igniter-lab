# lab-stdlib-statistics-readiness-p1-v0 — descriptive statistics over collections

**Card:** `LAB-STDLIB-STATISTICS-READINESS-P1` · **Delegation:** `OPUS-STDLIB-STATISTICS-READINESS-P1`
**Status:** CLOSED (readiness / design — NO code) — designs the first statistics surface (`mean`, `variance`,
`stddev`) as **pure `.ig` library contracts** returning `Option[Float]`, gated on **one tiny prerequisite**
(`to_float(Integer)->Float`) that the verify-first uncovered. Deterministic by fixed authored-order fold +
`det_sqrt`. Descriptive only; no dataframe, no inferential stats, no random.

## Verify-first pressure inventory (live)

| Source | Evidence | Stats pressure |
|---|---|---|
| `apps/igniter-apps/neural_net` (NN-P04) | dense layers / inner products need `sum`/`fold` to collapse collections; normalization implied | mean / normalization |
| `apps/igniter-apps/sim_framework` (SIM-P03) | `SumPopulation` = first confirmed `fold` in an app (`fold(populations, 0, (acc,v)->acc+v)`) | sum (have it); mean next |
| `apps/igniter-apps/vector_math`, `vector_editor` | magnitude / dot / averages | mean, variance (spread) |
| Emergence Kuramoto / N-body (P4/P11) | order parameter `r = (1/N)·sqrt((Σcosθ)² + (Σsinθ)²)` | **`1/N` over a runtime collection = the same blocker** |

The pressure is real and **convergent**: every collection reduction that goes beyond `sum`/`fold` needs to
divide by the element count — and that is exactly where the language wall is.

## The gating finding (verify-first, decisive)

`mean(coll) = sum(coll) / count(coll)`. Live types: `count -> Integer`, `sum(Collection[Float]) -> Float`. The
typechecker (`typechecker.rs:5080-5084`) **deliberately defers heterogeneous numeric ops**: a binary op
typechecks only when `left_name == right_name`. So `Float / Integer` does **not** compile. **Pure-`.ig` mean
is blocked today — not on statistics, but on a missing Integer→Float conversion.** No `to_float`/`as_float`
exists in the live tree. This also blocks the N-body `1/N` order parameter for variable-size collections.

## Candidate taxonomy (≥5, classified)

| stat | first? | expressible in `.ig` after `to_float`? | blocker if deferred |
|---|---|---|---|
| `mean` | **yes** | `sum/to_float(count)` ✓ | — |
| `variance` | **yes** | two-pass `sum(map(c, x->(x-mean)²))/to_float(count)` ✓ (stable) | — |
| `stddev` | **yes** | `det_sqrt(variance)` ✓ | — |
| `min`/`max`/`range` | partial | `min`/`max` **owned by math P7**; `range = max−min` derivable | — |
| `median`/`percentile` | defer | needs a **sort primitive** (none in `.ig`) | no `sort` |
| `covariance`/`correlation` | defer | needs **paired iteration / `zip`** | no element-wise `zip` over two collections in a reduction |
| `histogram` | defer | bucketing = dataframe-ish (card forbids) | scope |

**First surface = `mean`, `variance`, `stddev`** over `Collection[Float]`. `min`/`max` already exist (P7);
`range` is a one-liner. Everything else is deferred with a *named* blocker (sort / zip).

## Design decisions (answers to the card's Q1–Q10)

- **Q1 first stats:** `mean`, `variance`, `stddev`. (Q2) **`sum` stays collection-owned** — stats reuse it,
  don't duplicate it.
- **Q3 empty collection:** **`Option[Float]` — `none()` on empty.** Total and composable; fits pure `.ig`
  (pure contracts return values, not errors; `Option` is built-in). `sum([])` stays `0` (already total);
  `mean([])`/`variance([])`/`stddev([])` = `none()`. (Avoids `0/0 → NaN → JSON null`.)
- **Q4 reduction determinism:** **fixed authored-order `fold`** — Igniter's `fold` is sequential and
  deterministic; **no parallel reassociation, ever.** Variance uses the **two-pass form** `Σ(x−mean)²`
  (numerically stable — avoids the catastrophic cancellation of `Σx² − n·mean²`). (Kahan/Welford are
  *compatible* optimizations because they don't reorder — noted as future, not needed for correctness.)
- **Q5 non-finite:** v0 **assumes finite input** (documented limit). Rationale: the deterministic `det_*`
  math (P5) already **refuses** to *produce* non-finite, so data fed from the math line is finite by
  construction. Strict refusal of a non-finite *element* needs an `is_finite(Float)->Bool` predicate — named
  as a small follow-on, not required for v0.
- **Q6 det_stats variants:** **NO.** Stats are **deterministic by construction** (fixed-order fold + finite
  input + `det_sqrt` for the only transcendental). A separate `det_stats.*` surface would be redundant.
- **Q7 result types:** `mean/variance/stddev : Collection[Float] -> Option[Float]`. A one-pass
  `StatsSummary{count,mean,variance,stddev}` record is **deferred** (ergonomic, needs record-return plumbing;
  a pure `.ig` helper can assemble it later).
- **Q8/Q9 pure `.ig` vs VM builtin:** **PURE `.ig` library contracts** (the card's bias), enabled by **one**
  VM/typecheck prerequisite: **`to_float(Integer)->Float`**. No stats VM builtin needed — post-P7/P10 the
  language expresses stable two-pass variance with `map`/`fold`/`sum`/arithmetic/`det_sqrt`. VM builtins
  remain a *benchmark-pressure-only* future option.
- **Q10 first impl card:** see below.

## Determinism statement

The v0 stats are **deterministic by fixed authored-order reduction** (not bit-claimed across architectures
unless the inputs and `det_sqrt` are used — `mean`/`variance` are exact rational reductions of the inputs,
`stddev` inherits `det_sqrt`'s P5 cross-arch story). No silent NaN/Inf: empty → `none()`, finite input
assumed. This is *tolerance-free* for `mean`/`variance` (exact f64 arithmetic in fixed order) and inherits
`det_sqrt` determinism for `stddev`.

## Pure `.ig` shape (design sketch — not committed code)

```ig
mean(c)     = if count(c) == 0 { none() } else { some(sum(c) / to_float(count(c))) }
variance(c) = if count(c) == 0 { none() }
              else { some( sum(map(c, x -> (x - mean_val) * (x - mean_val))) / to_float(count(c)) ) }
stddev(c)   = match variance(c) { some(v) -> some(det_sqrt(v))  none -> none() }
```
(`mean_val` = the unwrapped mean; exact two-pass; fixed-order; `det_sqrt` replay-safe.)

## Required deliverable — recap

- pressure inventory ✓ · first surface ✓ (`mean/variance/stddev`) · reduction policy ✓ (fixed-order, two-pass)
- empty ✓ (`Option`/`none`) · non-finite ✓ (assume finite v0; `is_finite` follow-on) · pure-`.ig` vs VM ✓ (pure, +`to_float`)

## Acceptance — mapping

- [x] Live pressure inventory completed (neural_net / sim_framework / vector_math / emergence order-parameter).
- [x] ≥5 statistic candidates categorized (mean/variance/stddev/min-max-range/median/percentile/covariance/histogram).
- [x] Empty (`Option`/`none`) and non-finite (assume-finite v0 + `is_finite` follow-on) policies decided.
- [x] Reduction determinism policy chosen (fixed authored-order fold; two-pass variance; no reassociation).
- [x] Pure `.ig` vs VM builtin compared → **pure `.ig`**, gated on the tiny `to_float` prerequisite.
- [x] First implementation card named with acceptance matrix (below).
- [x] No production code changes.

## Next implementation cards (named, with acceptance matrix)

**1. `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` (prerequisite, tiny):** `to_float(Integer)->Float` (and consider
`to_float(Decimal)`), no implicit coercion elsewhere. Acceptance: compiles `(Integer)->Float`; VM exact value
(`to_float(3)=3.0`); wrong arity/type rejected (OOF-MATH1/2); works inside HOF (eval_math_call source);
unblocks `1/to_float(N)`; STDLIB_VERSION bump.

**2. `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` (pure `.ig`):** author `mean/variance/stddev : Collection[Float]
-> Option[Float]` as `.ig` contracts. Acceptance matrix:
| case | expected |
|---|---|
| `mean([1.0,2.0,3.0])` | `some(2.0)` |
| `variance([1.0,2.0,3.0])` (population) | `some(0.6666…)` |
| `stddev([…])` | `some(det_sqrt(variance))` |
| `mean([])` / `variance([])` / `stddev([])` | `none()` |
| determinism | fixed-order fold; re-run identical |
| non-finite input | documented assumption (v0) |

(Population vs sample variance: pick **population** `/N` for v0; sample `/(N-1)` is a documented variant.)

## Closed scope (honored)

No implementation; no dataframe/table; no streaming/windowed stats (future note only); no inferential tests /
regression / ML metrics; no random/probability; no canon claim.

---

*Readiness / design. 2026-06-21. First stats surface = `mean/variance/stddev` → `Option[Float]`, pure `.ig`,
deterministic by fixed authored-order two-pass fold + `det_sqrt`. The decisive verify-first finding: pure-`.ig`
stats is gated not on statistics but on a missing `to_float(Integer)->Float` (the `Float/Integer` division wall
— `Integer op Float` is deliberately deferred). First impl card = the tiny `to_float`, then the pure-`.ig`
stats contracts.*
