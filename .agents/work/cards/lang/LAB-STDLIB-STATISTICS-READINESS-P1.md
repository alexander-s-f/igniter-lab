# LAB-STDLIB-STATISTICS-READINESS-P1 — deterministic descriptive statistics over collections

Status: CLOSED
Lane: standard / stdlib science
Type: readiness / design
Delegation code: OPUS-STDLIB-STATISTICS-READINESS-P1
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

After P10, math composes inside HOF/lambda bodies. That makes collection-based scientific reductions possible.
Statistics should be designed carefully because floating reductions are order-sensitive and can undermine replay
if parallelized or reassociated silently.

Pressure sources likely include simulations, telemetry summaries, vector/science apps, model evaluation, and
future probabilistic workflows.

## Goal

Design the first statistics surface for Igniter: deterministic, collection-based, and small enough to prove.

No production code changes in this card.

## Verify first

- `lab-docs/lang/lab-stdlib-math-eval-ast-parity-p10-v0.md`
- current collection HOF support in compiler/VM (`map`, `fold`, `sum`, comprehensions)
- `apps/igniter-apps/neural_net/*`
- `apps/igniter-apps/vector_math/*`
- simulation/Kuramoto/N-body docs
- any telemetry / report / scorecard apps that mention averages, variance, percentiles, correlation

Search live tree for `mean`, `average`, `variance`, `stddev`, `standard deviation`, `correlation`, `covariance`,
`percentile`, `median`, `histogram`, `metric`, and classify real pressure.

## Questions to answer

1. Which statistics are genuinely first?
   - `sum`, `mean`, `variance`, `stddev`
   - `min/max/range` (maybe math P7 owns min/max)
   - `covariance/correlation`
   - `median/percentile/histogram`
2. Should `sum(Collection[Float])` be language-owned if collection already has `sum`?
3. What should empty collection behavior be?
   - runtime domain error
   - `Option[Float]`
   - zero for `sum`, error for `mean`
4. What deterministic reduction policy is required?
   - authored-order fold
   - Kahan compensated sum
   - pairwise stable reduction
   - Welford for variance
5. How should Float non-finite values be handled?
6. Should there be deterministic `det_stats.*` variants, or are stats deterministic by using fixed order and
   finite checks?
7. What result types are needed?
   - plain Float
   - record `StatsSummary { count, mean, variance, stddev }`
8. Can current `.ig` express these as app-local helper contracts, or is stdlib VM support needed for performance
   / ergonomics?
9. Which pieces need VM builtins vs pure `.ig` library contracts?
10. What is the first implementation card and acceptance matrix?

## Design constraints

- No hidden parallel reassociation.
- No silent NaN/Inf in lineage/output streams.
- Determinism must be stated: exact bits if claimed, tolerance if only approximate.
- Do not implement a dataframe library.
- Prefer small descriptive stats before inferential statistics.
- Keep random/probability separate unless needed as explicit dependency.

## Candidate splits to compare

At least compare:

1. Pure `.ig` statistics library contracts over `Collection[Float]`.
2. VM stdlib builtins for performance and stable algorithms.
3. Hybrid: pure proof first, VM builtin only under benchmark pressure.
4. Defer stats until N-body / app pressure proves exact missing functions.

Bias: pure `.ig` proof first for `mean`/`variance` if expressible; VM builtin only if current language cannot
express a stable/ergonomic version.

## Required deliverable

Write `lab-docs/lang/lab-stdlib-statistics-readiness-p1-v0.md` with:

- pressure inventory;
- chosen first stats surface;
- deterministic reduction policy;
- empty/non-finite behavior;
- pure `.ig` vs VM builtin decision;
- next implementation card name + acceptance matrix.

Close this card with a report.

## Acceptance

- [x] Live pressure inventory completed.
- [x] At least five statistic candidates categorized.
- [x] Empty collection and non-finite policies decided or explicitly deferred.
- [x] Reduction determinism policy chosen.
- [x] Pure `.ig` vs VM builtin route compared.
- [x] First implementation card named with acceptance matrix.
- [x] No production code changes.

---

## Closing Report (2026-06-21)

**Design-only, no code.** Proof doc: `lab-docs/lang/lab-stdlib-statistics-readiness-p1-v0.md`.

**Decisive verify-first finding:** pure-`.ig` stats is gated **not on statistics** but on a missing
**`to_float(Integer)->Float`**. `mean = sum/count` is `Float / Integer`, and the typechecker
(`typechecker.rs:5080`) **deliberately defers heterogeneous numeric ops** (only same-type compiles). No
`to_float` exists. This same wall blocks the emergence order parameter's `1/N` over a runtime collection.

**Chosen design:** first surface = **`mean/variance/stddev` : `Collection[Float]` -> `Option[Float]`** (empty
→ `none()`), as **pure `.ig` library contracts** (card's bias), enabled by the one tiny prerequisite. Reduction
= **fixed authored-order `fold`, no reassociation**; variance = **two-pass stable** `Σ(x−mean)²`; stddev =
`det_sqrt(variance)`. **Deterministic by construction → no `det_stats` variants.** Non-finite: v0 assumes
finite (det_* already refuses to produce non-finite); `is_finite` is a named follow-on. `min/max` already
owned by P7; median/percentile (needs sort), covariance/correlation (needs zip), histogram (dataframe-ish)
deferred with named blockers.

**Next impl cards:** (1) `LAB-STDLIB-NUMERIC-TO-FLOAT-P8` — tiny `to_float(Integer)->Float` (unblocks stats +
`1/N` + all numeric reductions); (2) `LAB-STDLIB-STATISTICS-DESCRIPTIVE-P2` — pure `.ig` `mean/variance/stddev`
with the acceptance matrix in the proof doc. No production code changed; `git diff --check` clean.

## Closed scope

- No implementation.
- No dataframe/table library.
- No streaming/windowed stats unless only noted as future.
- No inferential tests, regression, or ML metrics beyond pressure notes.
- No random/probability implementation.
- No canon claim.
