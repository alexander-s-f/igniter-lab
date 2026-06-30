# LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1 — collection algebra promotion plan

Lane: lang / stdlib / collection / algebra / parity
Status: DONE (research/decision packet) — **ADMIT the predicate slice first**; named cards; no code
Date: 2026-06-29
Card: `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1.md`
Builds on: `lang-stdlib-collections-horizon-research-p1-v0.md`, flat_map wave P1/P3/P4/P5

Authority boundary: canon authority is `igniter-lang` (`COLLECTION_HOF_FNS` + `stdlib-inventory.json`).
The lab Rust compiler and VM run ahead of canon for several ops; that is **evidence**, not admission.
This packet only proposes. No code, no inventory change.

## 1. Executive recommendation

**Promote the predicate/query slice first: `find`, `any`, `all`** (Q1 = Option A). All three are
already implemented and proven in the lab Rust TC + VM, are pure/deterministic/single-pass with
early-exit, and need **no new type and no new diagnostic** (`find -> Option[T]` reuses the existing
Option; `any`/`all -> Bool`; predicate-not-Bool reuses `OOF-COL3` exactly as `filter`). Rejected
alternatives: **D (lab-ahead bundle `zip/take/drop/find/any/all`)** — `zip` drags in a `Collection[Pair[A,B]]`
representation decision (see §6) and would make the bundle risky; **E (fix type-system gaps first)** —
the predicate ops have no typing blocker, so blocking them on the typed-empty/fold-seed work is
needless delay. `take` is the clean second slice; `zip` is explicitly deferred behind a Pair policy.

## 2. Live surface inventory (verified from code, 2026-06-29)

`R`=present, `—`=absent. Canon authority = the first two columns.

| op | canon Ruby | canon inventory | lab Rust TC | VM runtime | verdict |
| --- | :-: | :-: | :-: | :-: | --- |
| `map` | R | R | R | R | canon, dual |
| `filter` | R | R | R | R | canon, dual |
| `filter_map` | R | R | R | R | canon, dual |
| `count` | R | R | R | R | canon, dual |
| `flat_map` | R | R | R | R | canon, dual (wave just closed) |
| `concat` | R | R | R | R | canon, dual |
| `append` | R | R | R | R | canon, dual |
| `sum` | R | R | R | R | canon, dual |
| `fold` | R | **—** | R | R | **canon dispatch but NO inventory entry → gap** |
| `range` | R | R | R | R | canon, dual |
| `is_empty` | R | R | R | R | canon, dual |
| `non_empty` | R | R | R | R | canon, dual |
| `first` | R | R | R | R | canon, dual |
| `last` | R | R | R | R | canon, dual |
| `find` / `first_where` | — | — | R (`-> Option[T]`) | R | **lab-ahead, proven** |
| `any` | — | — | R (`-> Bool`) | R | **lab-ahead, proven** |
| `all` | — | — | R (`-> Bool`) | R | **lab-ahead, proven** |
| `take` | — | — | R (`-> Collection[T]`) | R | **lab-ahead, proven** |
| `reduce` | — | — | R (alias of fold) | R | lab alias of `fold` — alias policy, not a new op |
| `zip` | — | — | R (`-> Collection[Pair[A,B]]`) | R | **lab-ahead but blocked on a Pair policy (§6)** |
| `drop` | — | — | **—** | — | net-new (trivial) — pairs with `take` |
| `zip_with` | — | — | — | — | sugar over zip+map; blocked with zip |
| `flatten` | — | — | — | — | sugar (`flat_map(xs, x -> x)`) |
| `enumerate` | — | — | — | — | sugar (`zip(range,xs)`) — blocked with zip |
| `group_by`/`sort_by`/`distinct_by`/`index_by` | — | — | — | — | core-later (comparator/Map policy) |
| `chunk`/`window`(coll)/`scan` | — | — | — | — | core-later (no current pressure) |

Name surfaces: canon collection ops are `stdlib.collection.*` SIR calls with source aliases; the lab
adds bare-name HOFs (`find/any/all/take/zip/reduce`) that the lab emitter/VM dispatch but which carry
**no canon SIR/inventory entry yet**. (Path note: the card's `lib/igniter/typechecker.rb` is actually
`lib/igniter_lang/typechecker.rb`.)

## 3. Operation classification

- **core-now (admit/promote next):** `find`, `any`, `all` (slice 1, recommended); `take` (slice 2);
  `drop` (net-new, folds into the slicing card).
- **core-later (blocked on a prerequisite):** `group_by`, `index_by` (typed `Map[K,V]` + key equality),
  `sort_by`/`distinct_by` (total/stable comparator + Float-sort hazard), `chunk`/`window`/`scan`
  (deterministic but no current pressure), `zip`/`zip_with`/`enumerate` (Pair policy, §6).
- **sugar (no new primitive):** `flatten` = `flat_map(xs, x -> x)`; `enumerate` = `zip(range, xs)`;
  `zip_with` = `map(zip(a,b), p -> f(p))`.
- **host/query (not stdlib collections):** relational `join`, DB pagination/sort over rows, export
  projection.
- **reject-v0:** lazy streams / transducers (no perf proof); `reduce` as a *distinct* op (it is a
  `fold` alias — canonicalize on `fold`).

## 4. Pressure matrix (≥5 sources → ops)

| Pressure | Live example | Ops |
| --- | --- | --- |
| Reports / validation | "all rows valid?", "any overdue?", money report | **`all`/`any`**, `find`, `fold`, `sum`, `count` |
| Todo/API + data projection | find a row by id; first matching | **`find`** (`-> Option`), `filter`, `take` (page cap) |
| ViewArtifact / frame descriptors | row → element list, first/selected | `flat_map`, `map`, `find`, `take` |
| 3D / game mesh descriptors | body → tris; vertex↔normal pairing | `flat_map`, `map`, `range`; (pairing wants `zip` — blocked) |
| Emergence / science vectors | derived/aggregate; running checks | `map`, `fold`/`scan`, `sum`, `all`/`any`; (`zip_with` wants Pair) |
| Spark/TBackend ledgers | fact stream filters/aggregates | `filter`, `fold`, `find`; `group_by` (later) |

The predicate ops (`find`/`any`/`all`) appear in the most pressure rows and unblock the broadest set
with the least risk — reinforcing slice 1.

## 5. Typing / diagnostic gaps

For the **recommended slice (`find`/`any`/`all`) there is NO blocking gap**:
- `find(Collection[T], (T) -> Bool) -> Option[T]` — Option is an admitted sealed variant.
- `any`/`all (Collection[T], (T) -> Bool) -> Bool`.
- Diagnostics reuse only: `OOF-COL1` (arity / non-lambda), `OOF-COL2` (non-collection first arg),
  `OOF-COL3` (predicate body not `Bool` — identical to `filter`). **No new OOF code.**

Broader gaps (do NOT block slice 1; tracked separately): typed empty `[]`/`{}` + `fold` empty-seed
inference (array-literal-in-lambda gap seen in flat_map P4); generic element preservation through
nested HOFs; a total/stable comparator policy + Float-sort hazard (`OOF-COL10` reserved) for the
order/group cluster.

## 6. Pair / tuple decision for `zip` (explicit)

**Defer `zip`. Do NOT promote it in this wave, and do NOT smuggle an ad-hoc tuple into stdlib.**
Evidence: lab Rust `zip` already resolves to `Collection[Pair[A, B]]`, i.e. it introduces a `Pair[A,B]`
type. But **`Pair` is not a constructible/destructurable canon type** — it appears in the canon
inventory exactly once, only as a *signature spelling* inside `stdlib.map.from_pairs`
(`Collection[Pair[K,V]]`), with no constructor, no match/destructuring, and no inventory entry of its
own. Promoting `zip` would therefore force one of:
- (a) admit `Pair[A,B]` as a first-class canon sealed type (constructor + field access/destructuring) —
  a real language decision, larger than a stdlib op;
- (b) expose `zip_with(xs, ys, (x, y) -> …)` so the pair never surfaces — needs a binary-lambda /
  pair-destructuring mechanism the language doesn't have;
- (c) a two-field record `{ left, right }` — an ad-hoc tuple in stdlib (rejected).

Recommendation: a dedicated **`LANG-STDLIB-COLLECTION-ZIP-PAIR-READINESS-P2`** decides (a) vs (b)
before any `zip`/`zip_with`/`enumerate` promotion. Until then `zip` stays lab-only evidence.

## 7. Authority boundary

stdlib collection ops are **pure, in-memory, deterministic** transforms. `find`/`any`/`all`/`take`
qualify (single-pass, order-preserving, no IO, no randomness). Explicitly NOT stdlib collections:
relational `join`, host-backed/DB query, pagination/sort over DB rows, renderer-specific node builders,
file/export side effects, ambient randomness — those are projection/query/host authority and may use
collection-like vocabulary without being the same surface.

## 8. Performance notes

Hotspots to bench LATER (not this card): repeated `append`/`concat` → O(n²); `flat_map`/nested-HOF
intermediate allocations; descriptor generation for ViewArtifact/mesh; science vector loops. The
recommended slice is cheap: `any`/`all`/`find` short-circuit (early-exit, single pass); `take` is a
bounded prefix. One proto-bench card is warranted for the alloc-heavy ops: **`LAB-STDLIB-COLLECTION-PERF-PROTOBENCH-P1`**
(name what to bench; decides if transducers are ever justified).

## 9. Ranked follow-up cards

1. **`LANG-STDLIB-COLLECTION-PREDICATE-OPS-P2`** (Ruby canon) → **`-P3`** (lab Rust parity) →
   **`-P4`** (inventory + digest) — promote `find`/`any`/`all`. *First: lowest risk, broadest
   pressure, no new type/diagnostic.* (Mirrors the flat_map P3/P4/P5 chain.)
2. **`LANG-STDLIB-COLLECTION-SLICING-OPS-P2`** (+P3/P4) — `take` (lab-ahead) + `drop` (net-new).
   Pagination/science pressure; deterministic; no new type.
3. **`LANG-STDLIB-COLLECTION-FOLD-INVENTORY-CLEANUP-P1`** — close the `fold` inventory gap (live in
   canon Ruby + lab + VM, no inventory entry) and record the `reduce`→`fold` alias policy. Small,
   independent; can run anytime (P5-style digest recompute).
4. **`LANG-STDLIB-COLLECTION-ZIP-PAIR-READINESS-P2`** — Pair[A,B] vs zip_with decision before any
   zip/zip_with/enumerate promotion (§6).
5. **`LANG-STDLIB-COLLECTION-TYPED-EMPTY-FOLD-SEED-P2`** — the deferred inference gap (typed `[]`/`{}`
   + fold empty seed); unblocks typed accumulators and the array-literal-in-lambda case.
6. **`LANG-STDLIB-COLLECTION-ORDER-GROUP-READINESS-P2`** — sort/group/distinct/index comparator +
   `Map[K,V]` policy + Float-sort hazard (`OOF-COL10`). Decision before code.
7. **`LAB-STDLIB-COLLECTION-PERF-PROTOBENCH-P1`** — §8.

Order: 1 (now) → 2 → {3 anytime} → {4,5,6 readiness, parallelizable} → 7. Rejected for v0: relational
`join` (host/query), lazy/transducers (no proof), `reduce` as a distinct op.

## Verification

```text
rg collection dispatch arms / inventory canonical_names / lab Rust arms / VM handlers / zip Pair  → §2 table
git diff --check  → PASS (research packet only; no code, no inventory change)
```
