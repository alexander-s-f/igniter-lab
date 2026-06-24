# LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-READINESS-P3 - paired descriptive statistics

Status: CLOSED (2026-06-24) — readiness packet delivered; verify-first found the P2 "blocked on `zip`" premise stale (`zip` proven + locked by ZIP-PROOF-P2) → covariance/correlation authorable as pure `.ig` today, no new prerequisite. NO code changes.
Lane: stdlib science / statistics
Type: readiness packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

`Mean/Variance/Stddev` are proven as pure `.ig` descriptive statistics. The next useful stats surface for
science is paired statistics: covariance and correlation. But the P2 closing report explicitly says this is
blocked on paired iteration / `zip`.

This card should not force an implementation around the blocker. It should decide whether covariance/correlation
wait for public `zip`, use a local paired reducer, or become a pressure card for `zip`.

## Goal

Design deterministic covariance/correlation for `Collection[Float]` and name the prerequisite precisely.

## Verify First

Read:

- `lab-docs/lang/lab-stdlib-statistics-readiness-p1-v0.md`;
- `lab-docs/lang/lab-stdlib-statistics-descriptive-p2-v0.md`;
- `LAB-STDLIB-COLLECTION-ZIP-READINESS-P1` if it has already closed;
- live collection/HOF implementation and tests;
- emergence docs that need paired series (`stage2-transfer-entropy`, finite-size/null analyses).

If `zip` is not implemented, do not pretend it is. Either gate the implementation or design a local reducer.

## Questions To Answer

1. Population vs sample covariance/correlation for v0?
2. Empty and length-1 semantics: `none()`, error, or zero?
3. Unequal length semantics.
4. Numerical stability: two-pass mean-centered vs one-pass.
5. Does v0 require `zip`, or can it be authored as paired recursion/reduction today?
6. Does correlation use `det_sqrt` and fixed-order reductions?
7. What exact implementation card follows?

## Required Output

Write `lab-docs/lang/lab-stdlib-statistics-covariance-correlation-readiness-p3-v0.md` with:

- current stats surface;
- prerequisite status;
- semantic decisions;
- implementation strategy;
- acceptance matrix for implementation or prerequisite card.

## Acceptance

- [x] Does not implement around a missing `zip` without naming the tradeoff. (`zip` proven; local-reducer + pressure-card alternatives named and rejected.)
- [x] Defines covariance/correlation semantics including empty/constant series. (empty/unequal → `none()`; constant/length-1 correlation → `none()`.)
- [x] Keeps deterministic fixed-order reduction explicit. (two-pass mean-centered, `map`∘`zip`+`sum`, `det_sqrt`, no reassociation.)
- [x] Names one exact next card. (`LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P4`.)
- [x] No production code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

- No inferential statistics.
- No p-values/significance testing.
- No matrix/stat dataframe surface.
- No canon claim.

## Closing Report (2026-06-24)

**Packet:** `lab-docs/lang/lab-stdlib-statistics-covariance-correlation-readiness-p3-v0.md`.

**Verify-first finding (flips the card):** the statistics-P2 closing claim "blocked on paired iteration /
`zip`" is **stale**. `zip` is now implemented, parity-clean, and **proven + locked** by ZIP-PROOF-P2:
declared `collections.ig:17`, typecheck arm `stdlib_calls.rs:789`, VM both paths (`vm.rs:1817`/`:4920`),
`p.first→A`/`p.second→B` field typing fixed, **6 e2e tests** in `stdlib_collection_zip_tests.rs` (incl.
`map(zip(a,b), p -> f(p.first,p.second))`). Unequal lengths silently truncate to min (documented).

**Chosen prerequisite path:** **none of the card's three options.** Not "wait for public `zip`" (it is public),
not "local paired reducer" (rejected — hides/duplicates a proven primitive), not "pressure card for `zip`"
(moot — already discharged into ZIP-PROOF-P2). → **Author covariance/correlation as pure `.ig` today via
`map`∘`zip`**, with a strict equal-length guard at the consumer. No new prerequisite.

**Stats semantics:** `(Collection[Float],Collection[Float]) -> Option[Float]`. **Population** `/N`, **two-pass
mean-centered** (`Σ(x−mx)(y−my)`, no catastrophic cancellation), fixed authored order. Empty → `none()`;
**unequal length → strict `none()`** (NOT zip's truncate-to-min — never silently drop scientific tail obs);
**correlation = cov/(sx·sy)** reusing P2 `stddev`/`det_sqrt`, with a **zero-variance guard** (constant series /
length-1 → `none()`). Population `/N` cancels in correlation. v0 assumes finite input; no `[-1,1]` clamp
(named follow-on). Sample `/(N-1)` deferred.

**Next card:** `LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P4` (implementation; one card, both statistics).
Naming reconciled: ZIP-P1 called the impl `…-P3`, but that slot is this READINESS card → impl takes **P4**.

**Checks:** acceptance below all met; no production code changes; `git diff --check` clean (only this card edit
+ the new packet doc).
