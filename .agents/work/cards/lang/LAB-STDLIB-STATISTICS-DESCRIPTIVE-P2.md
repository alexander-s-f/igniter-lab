# LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2 — pure descriptive statistics over Collection[Float]

Status: CLOSED
Lane: standard / stdlib science / statistics
Type: implementation proof
Delegation code: OPUS-STDLIB-STATISTICS-DESCRIPTIVE-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-STDLIB-STATISTICS-READINESS-P1` — picked pure `.ig` descriptive stats.
- `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` — prerequisite for `sum / to_float(count)`.
- `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — math inside HOF/lambda bodies.
- `LAB-STDLIB-MATH-DET-TIER1-P5` — use `det_sqrt` for replay-safe `stddev`.

This card should not start until `to_float(Integer)->Float` exists. If it starts early, it must stop at a
readiness/proof note and not invent implicit coercion.

## Goal

Add the first deterministic descriptive statistics library surface:

- `mean(xs: Collection[Float]) -> Option[Float]`
- `variance(xs: Collection[Float]) -> Option[Float]`
- `stddev(xs: Collection[Float]) -> Option[Float]`

Bias from P1: implement as pure `.ig` library contracts, not VM builtins, unless live language limitations make
that impossible.

## Verify first

- `lab-docs/lang/lab-stdlib-statistics-readiness-p1-v0.md`
- `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` proof doc and implementation.
- current stdlib module layout: is there a natural `stdlib/statistics.ig`, or should this live in a local proof
  fixture first?
- collection HOF syntax and existing pure library import behavior.
- `Option[T]`, `some`, `none`, `det_sqrt`, `sum`, `count`, `map`, `fold` live behavior.

## Semantics

- Empty collection returns `none()`.
- Non-empty collection returns `some(value)`.
- `mean` = fixed authored-order sum divided by `to_float(count(xs))`.
- `variance` = two-pass population variance: `sum((x-mean)^2) / to_float(count(xs))`.
- `stddev` = `det_sqrt(variance)` for replay-safe deterministic path.
- v0 assumes finite input values; if non-finite checks are not expressible, document the gap and keep tests
  finite. Do not silently add broad `is_finite` unless it is already live.
- No sample-vs-population ambiguity: v0 is population variance. Sample variance is a future separate function.

## Required implementation

Pick the smallest live-compatible home:

1. Preferred: pure `.ig` stdlib/library file (`stdlib/statistics.ig` or equivalent) with declarations/contracts
   if the stdlib system supports authored `.ig` contracts.
2. If stdlib cannot yet host pure contracts, create a proof fixture that compiles and executes through the real
   compiler+VM, then document the packaging blocker explicitly.

Do not implement VM builtins unless pure `.ig` is blocked and the blocker is proven.

## Acceptance

- [x] `mean([])` returns `none()`.
- [x] `mean([1.0,2.0,3.0])` returns `some(2.0)`.
- [x] `variance([1.0,2.0,3.0])` returns population variance `2/3` within documented tolerance.
- [x] `stddev([1.0,2.0,3.0])` uses `det_sqrt` and matches expected tolerance.
- [x] Fixed authored-order reduction is stated; no hidden parallel reassociation.
- [x] Pure `.ig` implementation compiles through the real compiler, or a live blocker is documented.
- [x] Tests run through real compiler+VM, not only string inspection.
- [x] Empty behavior uses `Option[Float]` (`none`), not sentinel `0`.
- [x] `to_float` is used explicitly; no implicit numeric coercion added.
- [x] Proof doc written: `lab-docs/lang/lab-stdlib-statistics-descriptive-p2-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Gate passed:** `to_float` (P8) is live, so `sum(xs)/to_float(count(xs))` compiles. **Implementation:**
`Mean/Variance/Stddev : Collection[Float] -> Option[Float]` as **pure `.ig` contracts** (no VM builtin) using
live `count`/`sum`/`map`/`to_float`/`det_sqrt`. Empty → `none()` (`m` empty-guarded so no discarded NaN);
**population** variance, **two-pass** `Σ(x−m)²` (stable), **fixed authored-order** (no reassociation); `stddev`
= `det_sqrt(variance)` (replay-safe). Proof doc: `lab-docs/lang/lab-stdlib-statistics-descriptive-p2-v0.md`.

**Home:** authored contracts (the stdlib `.ig` files are Rust-wired declarative signatures, so authored
contracts aren't bare-importable) → shipped as a regression test + a reusable library file
`igniter-home-lab/apps/emergence/lib/statistics.ig`. Bare-importable packaging = named follow-on.

**Live (real compiler+VM):** `Mean([1,2,3])=some(2.0)`, `Mean([])=none`, `Variance([1,2,3])=some(0.6666666666666666)`,
`Variance([])=none`, `Stddev([1,2,3])=some(0.816496580927726)`. Tests: `stdlib_statistics_tests` **5** green
(assert the `Resulting Output:` record, not source strings); full VM suite green except pre-existing `vmg13`.
`git diff --check` clean.

**Blockers (named) for the rest:** median/percentile (no `sort`), covariance/correlation (no `zip`/paired
iteration), histogram (dataframe-ish), bare-importability (library/import mechanism). **Next:** library-packaging
card, or `covariance`/`correlation` after `zip`. For emergence: stats now enable order-parameter summaries +
finite-size scaling (`~1/√N`) in the rigor contract.

## Proof doc requirements

The proof doc must include:

- implementation home decision (stdlib pure contracts vs proof fixture);
- exact empty and finite-input policies;
- variance formula (population, not sample);
- reduction determinism statement;
- exact tests and counts;
- blockers for median/percentile/correlation/histogram.

## Closed scope

- No median, percentile, histogram, covariance, correlation, regression, dataframe, or streaming windows.
- No random/probability.
- No VM performance optimization.
- No implicit numeric coercion.
- No canon claim.

## Next

If this lands as fixture-only due to stdlib packaging limits, next card should be a small library-packaging card.
If it lands in stdlib, next pressure slice is `covariance/correlation` only after `zip`/paired iteration exists.
