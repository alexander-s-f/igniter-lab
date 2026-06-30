# LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1

Status: CLOSED (2026-06-29) — promote predicate slice first; zip deferred; cards named
Lane: lang / stdlib / collection / algebra / parity
Mode: research-readiness / proposal packet
Skill: idd-agent-protocol

## Goal

Turn the collections horizon roadmap into a concrete promotion plan for the next coherent collection
algebra slice after `flat_map`.

This card should answer:

- which lab-ahead collection operations are already proven enough to promote toward canon;
- which operations need new typechecker/VM work first;
- which operations should remain syntax sugar, host/query-layer behavior, or out of scope;
- what exact implementation cards should follow.

This is **not** a broad implementation card. It is the decision packet that prevents the next wave from
becoming one-function-at-a-time drift.

## Why Now

`flat_map` is now closed end-to-end:

- `LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1` — admitted the shape.
- `LANG-STDLIB-COLLECTION-FLATMAP-P3` — Ruby/canon TC.
- `LANG-STDLIB-COLLECTION-FLATMAP-P4` — Rust/lab parity.
- `LANG-STDLIB-COLLECTION-FLATMAP-P5` — canon inventory + digest.

The pressure remains larger than `flat_map`:

- ViewArtifact and frame-ui want descriptor-tree and list construction.
- 3D/game descriptors want mesh/list construction without host-side pairing.
- Todo/API rows and data projection want row-to-view/list transformations.
- Reports/exports want sections/tables from rows.
- Emergence/science wants vector/list transforms that stay deterministic and efficient.

The previous horizon packet says the lab already runs a richer algebra than canon admits:
`zip/find/any/all/take/reduce/flat_map` are reported as lab-ahead/proven or near-proven. This card must
verify that claim live and convert it into a precise wave plan.

## Read First

Primary:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTIONS-HORIZON-RESEARCH-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-FLATMAP-P5.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/stdlib-inventory.json`

Live code:

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/src/emitter.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm/src/vm.rs`

Tests/proofs to inspect:

- collection tests in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-compiler/tests/`
- VM collection/HOF tests in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lang/igniter-vm/tests/`
- prior cards for `zip`, `concat`, `append`, `range`, `is_empty`, `first/last`, `sum`, `fold`, `filter_map`

Pressure examples:

- frame-ui/ViewArtifact cards around Element trees and `.ig` descriptors
- `lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md`
- Todo/API data projection docs
- emergence/science docs using vector/list transforms

## Verify-First Tasks

Build a live inventory table. Do not trust old horizon statements until verified.

For each candidate, classify current state across four surfaces:

```text
operation | canon Ruby | canon inventory | lab Rust compiler | VM/runtime | tests/proofs | verdict
```

Candidates:

- `zip`
- `zip_with`
- `take`
- `drop`
- `find` / `first_where`
- `any`
- `all`
- `reduce`
- `fold`
- `sum`
- `first`
- `last`
- `flatten`
- `flat_map`
- `concat`
- `append`
- `range`
- `is_empty`
- `non_empty`
- optional: `group_by`, `sort_by`, `distinct_by`, `index_by`, `window`, `chunk`, `scan`, `enumerate`

Also verify whether function names are:

- source aliases only;
- canonical `stdlib.collection.*` SIR calls;
- VM opcodes/handlers;
- inventory entries.

## Research Questions

### Q1. What is the smallest coherent promotion slice?

Choose one:

- **A. Predicate/query slice**: `find`, `any`, `all`
- **B. Slicing slice**: `take`, `drop`, `first`, `last`
- **C. Pairing slice**: `zip`, `zip_with`
- **D. Lab-ahead bundle**: `zip/take/drop/find/any/all` together
- **E. Do not promote yet; fix type-system gaps first**

Recommendation must be evidence-based. If a bundle is too risky, split it.

### Q2. Which operations are “core now” vs “core later”?

Use these buckets:

- `core-now`: deterministic, pure, bounded implementation, clear typing
- `core-later`: useful but blocked by comparator policy, grouping maps, typed empty, performance, etc.
- `syntax-sugar`: lowers to existing core ops; no new semantic primitive
- `host/query`: belongs to DB/query/renderer/export layer, not collection stdlib
- `reject-v0`: too broad or insufficient pressure

### Q3. What typing gaps block the next slice?

Inspect and name:

- typed empty collection literals;
- lambda body inference;
- predicate body must be `Bool`;
- optional result shape for `find`;
- tuple/pair representation for `zip`;
- record output from HOFs;
- generic preservation through nested HOFs;
- output-context inference vs local inference.

Name diagnostics:

- reuse existing `OOF-COL*` where possible;
- propose new codes only if necessary.

### Q4. What is the canonical pair/tuple shape?

`zip` is the most dangerous candidate because it forces a representation decision.

Evaluate:

- `Pair[A,B]` stdlib record;
- two-field record `{ left: A, right: B }`;
- app-local record requirement;
- `zip_with(xs, ys, (x,y) -> ...)` without exposing Pair;
- defer `zip` until record generics/pair policy is settled.

This answer should be explicit. Do not smuggle an ad hoc tuple into stdlib.

### Q5. What are the authority boundaries?

Keep stdlib collection ops pure and in-memory:

- no database `join`;
- no host-backed query;
- no renderer-specific node builders;
- no file/export side effects;
- no ambient randomness.

Relational joins, pagination, sorting over DB rows, and export/report projection may use collection-like
language, but they are not the same authority surface.

### Q6. What performance work should follow?

Name likely hotspots:

- repeated `append`/`concat`;
- `flat_map` intermediate allocations;
- nested HOFs over large lists;
- descriptor generation for ViewArtifact / mesh;
- science vector loops.

Propose one proto-bench card if needed, but do not implement it here.

## Expected Deliverable

Write:

```text
/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lang-stdlib-collection-algebra-parity-prop-p1-v0.md
```

Required sections:

1. Executive recommendation.
2. Live surface inventory table.
3. Operation classification (`core-now`, `core-later`, `sugar`, `host/query`, `reject-v0`).
4. Pressure matrix.
5. Typing/diagnostic gaps.
6. Pair/tuple decision for `zip`.
7. Authority boundary.
8. Performance notes.
9. Ranked follow-up cards with exact card names.

## Acceptance

- [x] Live inventory covers 25 ops (≥16) — §2.
- [x] Each op has canon Ruby / canon inventory / lab Rust / VM status — §2 table.
- [x] 6 pressure sources mapped to ops — §4.
- [x] Recommendation picks one slice (predicate `find/any/all`) + rejects D (zip-bundle) and E
      (fix-types-first) — §1.
- [x] `zip` pair/tuple policy explicitly answered: DEFER behind a Pair-policy card — §6.
- [x] Host/query boundary explicit — §7.
- [x] Performance risks named + one proto-bench card — §8.
- [x] Follow-up cards named + ordered — §9.
- [x] No production code / no inventory change; `git diff --check` clean (both repos).

## Report (2026-06-29)

**Recommended next card:** `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2` (Ruby canon `find`/`any`/`all`),
then `-P3` (lab Rust parity) → `-P4` (inventory+digest), mirroring the flat_map chain.

**Why first (one sentence):** `find`/`any`/`all` are already implemented and proven in the lab Rust TC
+ VM, are pure/deterministic/single-pass with early-exit, and need **no new type and no new
diagnostic** (`Option[T]`/`Bool` results; predicate-not-Bool reuses `OOF-COL3`) — the lowest-risk,
broadest-pressure slice.

**Intentionally deferred:** `zip`/`zip_with`/`enumerate` (Pair policy), `take`+`drop` (clean second
slice, not first), `group_by`/`sort_by`/`distinct_by`/`index_by` (comparator/Map policy),
`chunk`/`window`/`scan` (no pressure), typed-empty/fold-seed inference, perf proto-bench. `reduce`
stays a `fold` alias (not a distinct op). Rejected for v0: relational `join` (host/query),
lazy/transducers (no proof).

**`zip` status:** NOT ready — it forces `Collection[Pair[A,B]]`, and `Pair` is not a constructible
canon type (only a signature spelling inside `map.from_pairs`); needs a dedicated
`LANG-STDLIB-COLLECTION-ZIP-PAIR-READINESS-P2` (Pair-as-sealed-type vs `zip_with`-hides-pair) before
promotion. No ad-hoc tuple smuggled into stdlib.

**Files read/grepped for live verification:**
`igniter-lang/lib/igniter_lang/typechecker.rb` (dispatch arms + COLLECTION_HOF_FNS / FIRST_LAST /
filter_map/concat/sum/fold/append/is_empty/non_empty/range);
`igniter-lang/docs/spec/stdlib-inventory.json` (collection canonical_names; `Pair` only in
`map.from_pairs`); `igniter-lab/lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (arms incl.
the `zip` → `Collection[Pair[A,B]]`, `find` → `Option[T]`, `any`/`all` → `Bool`, `take`; `drop`
absent); `igniter-lab/lang/igniter-vm/src/vm.rs` (handlers: find/any/all/take/zip/reduce/fold/…).
Path correction: the card's `lib/igniter/typechecker.rb` is `lib/igniter_lang/typechecker.rb`.

Deliverable: `lab-docs/lang/lang-stdlib-collection-algebra-parity-prop-p1-v0.md`.
`git diff --check`: PASS (igniter-lab + igniter-lang); no code, no inventory change.

## Likely Next Cards

The packet should decide final names, but likely candidates are:

- `LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2` — `find/any/all` if verified low-risk.
- `LANG-STDLIB-COLLECTION-SLICING-OPS-P2` — `take/drop/first/last` if verified low-risk.
- `LANG-STDLIB-COLLECTION-ZIP-PAIR-READINESS-P2` — if `zip` needs a Pair policy first.
- `LANG-STDLIB-COLLECTION-TYPED-EMPTY-FOLD-SEED-P2` — if inference blocks useful ops.
- `LAB-STDLIB-COLLECTION-PERF-PROTOBENCH-P1` — if performance pressure is real enough.

## Non-Goals

- No code implementation.
- No changes to `stdlib-inventory.json`.
- No new syntax.
- No tuple/Pair implementation.
- No DB/query DSL.
- No lazy stream/transducer implementation.

## Closing Report Requirements

The closing report must include:

- recommended next implementation card;
- one-sentence reason why that slice is first;
- which operations are intentionally deferred;
- whether `zip` is ready or needs a separate Pair policy;
- exact files read or grepped for live-state verification;
- `git diff --check` result.
