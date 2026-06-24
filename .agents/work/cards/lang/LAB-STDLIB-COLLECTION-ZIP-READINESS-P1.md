# LAB-STDLIB-COLLECTION-ZIP-READINESS-P1 - paired iteration for science/statistics

Status: CLOSED (2026-06-24) — readiness packet delivered; verify-first found `zip` already wired (untested) → recommend prove+lock, not design. NO code changes.
Lane: stdlib science / collections
Type: readiness packet
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Statistics P2 proved pure `.ig` `mean/variance/stddev` over `Collection[Float]`. Its closing report named the
next real blocker: covariance/correlation require paired iteration (`zip`) over two collections.

This is not only a statistics nicety. Scientific workloads need paired observations:

- `covariance(x, y)` / `correlation(x, y)`;
- comparing two time series (`r(t)` vs `Z_i(t)`);
- transfer-entropy preprocessing and surrogate alignment;
- vectorized residual/error calculations.

Do not implement first. Decide the shape and error semantics against live collection/HOF behavior.

## Goal

Design the first `zip`/paired-iteration surface for Igniter collections.

## Verify First

Read live code and prior proof docs:

- collection stdlib cards/docs for `map`, `filter`, `sum`, `append`, `concat`;
- `lab-docs/lang/lab-stdlib-statistics-descriptive-p2-v0.md`;
- `lang/igniter-vm` HOF execution/eval_ast paths;
- compiler/typechecker support for records and collection element types;
- any current collection pair/record fixtures.

Live source wins over old docs. Check whether `zip` or pair records already exist before designing them.

## Questions To Answer

1. Should v0 return `Collection[Pair[T,U]]`, require same element type, or only support `Collection[Float]`?
2. How should unequal lengths behave: truncate, `none()`, explicit error, or diagnostic?
3. Should paired stats avoid public `zip` and implement internal paired reduction instead?
4. Can a generic `Pair[A,B]` be expressed today, or does v0 need fixed records?
5. Does `zip` belong in stdlib core, authored `.ig` package, or VM builtin?
6. What exact implementation card should follow?

## Required Output

Write `lab-docs/lang/lab-stdlib-collection-zip-readiness-p1-v0.md` with:

- current collection/HOF capability table;
- alternatives comparison;
- recommended v0 surface;
- unequal-length semantics;
- determinism/performance statement;
- acceptance matrix for the first implementation card.

## Acceptance

- [x] Grounded in live compiler/VM collection behavior (zip read directly: `vm.rs:1817`/`:4920`, `stdlib_calls.rs:789`, `collections.ig:13`).
- [x] At least 4 alternatives compared (5 in packet §2).
- [x] Recommends one v0 shape (adopt existing `zip` + consumer length guard) and one next card ID (`LAB-STDLIB-COLLECTION-ZIP-PROOF-P2`).
- [x] Names covariance/correlation as downstream pressure without implementing them (§7).
- [x] No code changes.
- [x] `git diff --check` clean.

## Closed Surfaces

- No implementation.
- No covariance/correlation yet.
- No generic collection system rewrite.
- No canon claim.

## Closing Report (2026-06-24)

**Packet:** `lab-docs/lang/lab-stdlib-collection-zip-readiness-p1-v0.md`.

**Verify-first finding (flips the card):** `zip` **already exists** — declared
`lang/igniter-stdlib/stdlib/collections.ig:13` (`zip(Collection[A],Collection[B]) -> Collection[Pair[A,B]]`),
typecheck arm `typechecker/stdlib_calls.rs:789`, VM both paths parity-identical (`vm.rs:1817` eval_ast,
`vm.rs:4920` bytecode): 2 arrays → `Record{first,second}`, **unequal lengths silently truncate to min**.
**No test/fixture exists** → wired but unproven; truncation is a science hazard; `Pair` is a synthetic
built-in (no user generics — `parser.rs TypeDecl` has no type-params).

**Chosen v0 shape:** adopt the existing `zip` **unchanged** (`Collection[Pair[A,B]]`, `Pair={first,second}`,
truncate-to-min) as the paired-iteration primitive; express paired iteration as `map`∘`zip`. Safety is at the
**consumer**: paired statistics must guard equal length (`count(x)!=count(y) → none()`); the primitive stays
permissive.

**Unequal-length policy:** primitive truncates to min (kept, documented); statistics are strict (`none()` on
mismatch).

**Rejected alternatives:** `zip_with` fused HOF (already expressible as `map`∘`zip` — defer as ergonomics);
internal-only paired reduction (hides a reusable primitive); making `zip` error on mismatch (breaks the wired
contract); `range`+index get (no clean random-access).

**Next card:** `LAB-STDLIB-COLLECTION-ZIP-PROOF-P2` (prove + lock the existing `zip`: truncation, Pair shape,
determinism, nested-in-`map`, and whether `p.first/.second` types to `A/B` vs `Unknown`). Then downstream
`LAB-STDLIB-STATISTICS-COVARIANCE-CORRELATION-P3` (covariance/correlation, named not implemented here).

**Checks:** acceptance below all met; no code changes; `git diff --check` clean (only this card edit + the new
packet doc).
