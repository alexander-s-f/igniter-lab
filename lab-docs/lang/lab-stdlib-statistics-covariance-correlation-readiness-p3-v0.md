# lab-stdlib-statistics-covariance-correlation-readiness-p3-v0 — paired descriptive statistics

**Card:** `LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-READINESS-P3` · **Date:** 2026-06-24
**Authority: lab readiness. Design + prerequisite decision, NOT implementation. No production code changes.**

Designs deterministic **population covariance/correlation** over two `Collection[Float]` as pure `.ig`
contracts returning `Option[Float]`. The decisive verify-first finding flips the card's premise: the blocker
named by statistics P2 (paired iteration / `zip`) **no longer exists** — `zip` is implemented, proven, and
locked. So this is **not** a `zip` pressure card and **not** a local-reducer workaround; the v0 covariance/
correlation can be authored **today** via `map`∘`zip`, with the safety guard at the consumer.

## Verify-first headline — the P2 blocker is stale

Statistics P2's closing report said covariance/correlation are "blocked on paired iteration / `zip`." That was
true on 2026-06-21. **It is no longer true.** Live source (same day as this packet, after ZIP-P1/ZIP-PROOF-P2):

| fact | evidence (live) |
|---|---|
| `zip` declared | `lang/igniter-stdlib/stdlib/collections.ig:17` — `def zip(a: Collection[A], b: Collection[B]) -> Collection[Pair[A, B]]` |
| typecheck arm | `lang/igniter-compiler/src/typechecker/stdlib_calls.rs:789` synthesizes `Collection[Pair[A,B]]` |
| VM parity (both paths) | `lang/igniter-vm/src/vm.rs:1817` (eval_ast) + `:4920` (bytecode); each pair = `Record{first, second}` |
| **Pair field access types** | `p.first → A`, `p.second → B` (the ZIP-PROOF-P2 typechecker fix) — so `map(zip(a,b), p -> f(p.first, p.second))` **compiles and runs** |
| unequal lengths | **silent truncate to `min(len_a, len_b)`** — documented in `collections.ig:13-16`, Python/Elixir-consistent |
| proven + locked | `lang/igniter-vm/tests/stdlib_collection_zip_tests.rs` — **6 e2e tests** through the real compiler+VM (truncate left/right longer, empty, Float multiply, top-level + nested-in-`map`) |

So the paired-iteration primitive exists, is parity-clean, deterministic, and test-locked. **The readiness
question for covariance/correlation is therefore purely semantic + authoring — not "invent a primitive".**

## Current stats surface (live)

| surface | status | shape | source of truth |
|---|---|---|---|
| `mean` / `variance` / `stddev` | **proven (P2)** | `Collection[Float] -> Option[Float]`, population, two-pass, `det_sqrt` for stddev | `lang/igniter-vm/tests/stdlib_statistics_tests.rs` (5 e2e) |
| `count` / `sum` / `map` | proven | collection-owned reductions, fixed authored order | collection cards (P3/P4) |
| `to_float(Integer)->Float` | proven (P8) | enables `Float / Integer` division | typecheck arm + VM |
| `det_sqrt` | proven (P5) | replay-safe sqrt, cross-arch story | `det_*` math line |
| **`zip`** | **proven + locked (ZIP-PROOF-P2)** | `(Collection[A],Collection[B]) -> Collection[Pair[A,B]]`, truncate-to-min | `stdlib_collection_zip_tests.rs` |
| `covariance` / `correlation` | **this card → design only** | `(Collection[Float],Collection[Float]) -> Option[Float]` | — |

The descriptive trio ships as **authored `.ig` contracts** (proven via a VM regression test embedding the `.ig`),
not bare-importable stdlib functions — bare-importable packaging is a deferred follow-on (P2 home decision).
v0 covariance/correlation inherit this same home: a regression test + reusable library-by-inclusion.

## Prerequisite status (the card's central question)

> "decide whether covariance/correlation wait for public `zip`, use a local paired reducer, or become a
> pressure card for `zip`."

**Resolved: none of those three.** `zip` is already **public and proven**. So:

- ❌ *Wait for public `zip`* — not needed; it is public and locked today.
- ❌ *Local paired reducer* — rejected. A bespoke `paired_fold`/Rust covariance builtin would hide a reusable,
  already-proven primitive and duplicate `zip`. (Same rejection ZIP-P1 §2 made.)
- ❌ *Pressure card for `zip`* — moot; the pressure already discharged into ZIP-PROOF-P2.
- ✅ **Author covariance/correlation as pure `.ig` today via `map`∘`zip`**, with a strict equal-length guard at
  the statistic (the consumer), exactly as ZIP-P1 §3 prescribed. **No new prerequisite.**

The one inherited obligation from ZIP-P1: **silent truncation is a science hazard**, so the *statistic* must be
strict about length — never lean on `zip`'s truncate-to-min for a scientific input.

## Semantic decisions (answers to the card's Q1–Q7)

**Q1 — Population vs sample (v0).** **Population** (`/N`), mirroring P2 variance. Rationale: consistency with the
proven descriptive trio, and population correlation is denominator-cancelling (the `/N` in covariance and in
each stddev cancel), so `correlation = cov/(sx·sy)` is exact regardless. Sample `/(N-1)` covariance and the
Bessel-corrected correlation are **documented variants**, deferred (a separate `*_sample` function later, no v0
ambiguity).

**Q2 — Empty and length-1.**
- **Empty → `none()`** (both functions). Option, never a sentinel `0` (mirrors P2).
- **Length-1:** population `covariance` of a single pair is mathematically `0` (mean-centered single point), so
  `covariance([a],[b]) = some(0.0)` is *defined but degenerate*. **`correlation` of length-1 → `none()`**:
  variance is `0`, so the denominator `sx·sy = 0` and correlation is undefined. This is subsumed by the general
  **zero-variance guard** below (length-1 is just one way to get a constant series).

**Q3 — Unequal length.** **Strict `none()` at the statistic.** Guard `if count(x) != count(y) { none() }`
*before* zipping. Do **not** rely on `zip`'s truncate-to-min — truncation silently dropping tail observations
would be a covariance/correlation correctness bug. The primitive stays permissive (truncate); the statistic is
strict (`none()`). This is the explicit ZIP-P1 split-responsibility decision.

**Q4 — Numerical stability.** **Two-pass, mean-centered**, fixed authored order — identical policy to P2
variance:
`cov = sum( map(zip(x,y), p -> (p.first - mx) * (p.second - my)) ) / to_float(n)`,
where `mx = mean(x)`, `my = mean(y)`. The mean-centered `Σ(x−mx)(y−my)` form avoids the catastrophic
cancellation of the one-pass `Σxy − n·mx·my`. No parallel reassociation, ever. (Welford/Kahan are
order-preserving future optimizations, not needed for correctness.)

**Q5 — Does v0 require `zip`?** **It requires `zip` and `zip` is already there.** v0 is authored as
`map`∘`zip` today — no new primitive, no design debt. (If `zip` had *not* existed, this card would have
gated to a readiness note per its own instruction. It does exist, so the card proceeds to a concrete impl
spec.)

**Q6 — `det_sqrt` and fixed-order reductions.** **Yes to both.** `correlation` reuses P2 `stddev`, which is
`det_sqrt(variance)` (replay-safe, P5 cross-arch story). All reductions (`sum`, `map`, the paired fold over
`zip`) are fixed authored order. Covariance itself is an exact rational reduction (no transcendental);
correlation inherits `det_sqrt` determinism through the two stddevs. **Zero-variance guard:** if
`sx == 0.0 || sy == 0.0` then `correlation → none()` (constant series; undefined). v0 does **not** clamp the
result to `[-1, 1]` (documented limit — float rounding may nudge a hair outside; a `[-1,1]` clamp is a named
follow-on). Finite input assumed (same as P2).

**Q7 — Exact next card.** **`LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P4`** (implementation). Naming note:
ZIP-P1's acceptance matrix referred to the downstream impl as `…-P3`, but that slot is occupied by *this*
readiness card (`…-READINESS-P3`); the implementation therefore takes **P4**. One card, both statistics.

## Implementation strategy (for P4 — design sketch, not committed code)

Pure `.ig` contracts, authored, mirroring P2 (reuse `mean`/`stddev`, do not re-derive):

```ig
covariance(x, y) =
  if count(x) != count(y) { none() }            -- strict length guard (NOT zip-truncate)
  else if count(x) == 0    { none() }            -- empty → none()
  else {
    mx = mean(x); my = mean(y)                   -- P2 mean (unwrapped; guarded non-empty)
    some( sum( map(zip(x, y), p -> (p.first - mx) * (p.second - my)) ) / to_float(count(x)) )
  }

correlation(x, y) =
  match (covariance(x, y), stddev(x), stddev(y)) {
    (some(cov), some(sx), some(sy)) ->
        if sx == 0.0 || sy == 0.0 { none() }     -- constant series / length-1 → undefined
        else { some( cov / (sx * sy) ) }
    _ -> none()
  }
```

(`p.first`/`p.second` type to `Float` via the ZIP-PROOF-P2 typechecker fix. Population `/N` cancels between
`cov` and `sx·sy`, so the population/sample choice does not change `correlation`'s value.)

**Home (inherit P2):** ship as a regression test embedding the `.ig` (run through real compiler + `igniter-vm
run`), plus the reusable library-by-inclusion artifact for the emergence consumer. Bare-importable packaging
stays the deferred follow-on. STDLIB_VERSION bump only if a stdlib-wiring path is chosen (proof-only otherwise).

## Acceptance matrix — the implementation card (P4)

| case | expected | note |
|---|---|---|
| `covariance([1,2,3],[1,2,3])` | `some(0.6666666666666666)` | = population variance (identical series), `2/3` |
| `covariance([1,2,3],[3,2,1])` | `some(-0.6666666666666666)` | anti-correlated, `-2/3` |
| `correlation([1,2,3],[1,2,3])` | `some(1.0)` | perfect positive |
| `correlation([1,2,3],[3,2,1])` | `some(-1.0)` | perfect negative |
| `covariance([],[])` / `correlation([],[])` | `none()` | empty → none |
| unequal length (e.g. `[1,2,3]` vs `[1,2]`) | `none()` | **strict guard**, NOT zip-truncate-to-2 |
| `correlation([5,5,5],[1,2,3])` | `none()` | constant series → zero variance → undefined |
| `covariance([a],[b])` (length-1) | `some(0.0)` | defined-but-degenerate (population) |
| `correlation([a],[b])` (length-1) | `none()` | zero variance |
| determinism | re-run identical | fixed authored order; `det_sqrt` replay-safe |
| non-finite input | documented assumption | v0 assumes finite (P2 inheritance) |

## Determinism statement

Deterministic by **fixed authored-order reduction** throughout: `zip` is positional `min`+`clone` (no float
math, `BTreeMap`-ordered keys), the paired fold and `sum`/`map` are source-ordered, covariance is an exact
rational reduction, and correlation inherits `det_sqrt`'s P5 cross-arch story through the two stddevs. No
hidden parallel reassociation. No silent NaN/Inf: empty/unequal/constant → `none()`; finite input assumed.

## Downstream consumer pressure (named, not implemented)

The emergence Stage-2 line is the concrete consumer of paired statistics:
`../igniter-emergence/cards/EMERGENCE-STAGE2-TRANSFER-ENTROPY-READINESS-P18.md`,
`…/EMERGENCE-STAGE2-NODE-TIMESERIES-P17.md`, and the finite-size/null analyses
(`…/docs/stage2-transfer-entropy-readiness.md`) need paired series: `r(t)` vs `Z_i(t)`, transfer-entropy
preprocessing / surrogate alignment, vectorized residuals. None are implemented here.

## Acceptance — mapping to the card

- [x] **Does not implement around a missing `zip` without naming the tradeoff** — verify-first found `zip`
  proven + locked (ZIP-PROOF-P2); the "blocked on zip" P2 premise is explicitly retired, local-reducer and
  pressure-card alternatives named and rejected with reasons.
- [x] **Covariance/correlation semantics defined including empty/constant series** — empty → `none()`,
  unequal → strict `none()`, constant/length-1 correlation → `none()` (zero-variance guard), population `/N`.
- [x] **Deterministic fixed-order reduction kept explicit** — two-pass mean-centered, `map`∘`zip`+`sum`,
  `det_sqrt`, no reassociation.
- [x] **Names one exact next card** — `LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P4` (with the P3/P4
  naming reconciliation).
- [x] **No production code changes** — readiness/design only.
- [x] **`git diff --check` clean** — only this new packet doc + the card status edit.

## Closed scope (honored)

No inferential statistics; no p-values/significance; no matrix/dataframe surface; no implementation; no canon
claim. Sample `/(N-1)` variants, `[-1,1]` clamp, `zip_with` fusion, and bare-importable packaging are named
deferred follow-ons, not v0.

---

*Readiness / design. 2026-06-24. The statistics-P2 "blocked on `zip`" premise is stale — `zip` is implemented,
proven, and locked (ZIP-PROOF-P2). v0 covariance/correlation = pure `.ig`, population, two-pass mean-centered
via `map`∘`zip`, `Option[Float]`: empty/unequal/constant → `none()`, strict equal-length guard (not
zip-truncate), `correlation = cov/(sx·sy)` reusing P2 `stddev`/`det_sqrt`. No new primitive, no pressure card.
Next = `LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P4` (implementation).*
