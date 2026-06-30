# LANG-STDLIB-COLLECTIONS-HORIZON-RESEARCH-P1 — next-horizon collection roadmap

Lane: lang / stdlib / collections / research / horizon
Status: DONE (research-readiness) — ranked roadmap + named cards; **no code**
Date: 2026-06-28
Card: `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTIONS-HORIZON-RESEARCH-P1.md`
Builds on: `lang-stdlib-collection-flatmap-prop-p1-v0.md` (admits `flat_map`)

Authority boundary: canon authority is `igniter-lang` (`COLLECTION_HOF_FNS` + `stdlib-inventory.json`).
The lab Rust compiler and VM run ahead of canon for several ops; those are **evidence**, not
admission. This packet proposes; nothing here registers a canon surface.

## 1. Live surface inventory (verified from code, 2026-06-28)

| Op | Canon Ruby (authority) | Canon inventory | Lab Rust | VM runtime |
| --- | --- | --- | --- | --- |
| `map` | ✅ `COLLECTION_HOF_FNS` | ✅ | ✅ | ✅ |
| `filter` | ✅ | ✅ | ✅ | ✅ |
| `count` | ✅ | ✅ | ✅ | ✅ |
| `filter_map` | ✅ (`infer_filter_map_call`) | ✅ | ✅ | ✅ |
| `fold` | ✅ (`:1247`) | — (inventory gap) | ✅ | ✅ |
| `sum` | ✅ (`:1244`) | ✅ | ✅ | ✅ |
| `concat` | ✅ (`:1223`, OOF-COL7) | ✅ | ✅ | ✅ |
| `append` | ✅ (`:1250`) | ✅ | ✅ | ✅ |
| `first` / `last` | ✅ `COLLECTION_FIRST_LAST_FNS` | ✅ | ✅ | ✅ |
| `is_empty` / `non_empty` | — | ✅ | (via Rust) | ✅ |
| `range` | — | ✅ | (builtin) | ✅ |
| `flat_map` | ❌ (PROP-admitted, P3 pending) | ❌ | ⚠️ placeholder (Result `and_then` path) | ✅ proven (`vm.rs:1020`, `d2ed524`) |
| `zip` | ❌ | ❌ | ✅ (`:911`) | ✅ |
| `find` / `any` / `all` | ❌ | ❌ | ✅ (`:1935,:1967`) | ✅ |
| `take` | ❌ | ❌ | ✅ (`:1007`) | ✅ |
| `reduce` | ❌ (use `fold`) | ❌ | ✅ (alias) | ✅ |

**Canon-admitted core today:** `map, filter, count, filter_map, fold, sum, concat, append, first, last,
is_empty, non_empty, range`. **Lab-ahead (proven, not yet canon):** `zip, find, any, all, take, reduce,
flat_map`. The single biggest hygiene fact: the lab is already running a richer algebra than canon has
admitted — the horizon work is largely *promoting proven lab ops with a contract*, not inventing.

Adjacent live facts: VM collection budget `MAX_COLLECTION_ELEMENTS = 1_000_000` (`vm.rs:118`); canon
`pipeline`/`step` is a **declaration-level OLAP construct** (`parser.rb:625`, *not valid inside a
contract body*) — there is **no expression-level `|>` pipe operator**; comprehension readiness exists
(`lab-lang-collection-comprehension-{readiness-p1,p2}-v0.md`); nested-ops diagnostic (`lab-collection-
nested-ops-diagnostic-p2-v0.md`); fold-to-struct accumulator (OOF-COL4) is proven (fold-struct track).

## 2. App / science pressure matrix

| Pressure | Concrete live example | Needed operations |
| --- | --- | --- |
| Todo / ViewArtifact rows | `examples/todo_postgres_app` list → `{items, next}`; row→HtmlNode | `map`, `filter`, `filter_map`, `flat_map` (row→cells), `take` (page cap), `fold`(→struct) |
| 3D mesh / game descriptors | `vm_game_app.ig` `body -> [tri, tri, …]`; ViewMesh | **`flat_map`** (row→many tris), `map`, `range`, `zip` (verts↔normals) |
| reports / exports | money report fold to total; table sections | `fold` (typed seed), `group_by`, `sort_by`, `sum`, `count`, `chunk` (pagination) |
| relational `rows_json` projection | `read_dispatch` typed rows → `Collection[AppRow]` | `map`, `filter`, `filter_map`, `index_by` (id→row); **join stays host/query** |
| emergence / science vectors | Kuramoto/SIRS vectors → derived/aggregates | `map`, `zip`/`zip_with`, `fold`/`scan`, `window`/`chunk`, `sum`, det-math (separate) |
| future Spark / TBackend ledgers | fact streams → projections | `filter`, `fold`, `group_by`, `distinct_by`; **temporal/query stays host** |

## 3. Operation taxonomy (classification)

`core now` = admit/promote with a contract next wave · `core later` = real but needs a typing/
determinism prerequisite · `sugar` = lowers to existing primitives · `host` = projection/query
domain, not stdlib collections · `reject` = no Igniter pressure yet.

| Op | Class | Rationale |
| --- | --- | --- |
| `flat_map` | **core now** | PROP-admitted; VM proven; P3/P4 pending. One-level unwrap. |
| `zip` | **core now** (promote) | lab+VM proven; deterministic; vector/science + verts↔normals pressure. Canon admission pending. |
| `take` / `drop` | **core now** (promote) | deterministic prefix/suffix; page caps. `take` lab-proven; `drop` symmetric. |
| `find` / `any` / `all` | **core now** (promote) | lab+VM proven; validation/report pressure; pure, deterministic, total. |
| `fold` (typed empty seed) | **core now / refine** | fold admitted, but **empty/typed-seed inference is a type gap** (§4) — the refinement is core-later. |
| `flatten(Collection[Collection[T]])` | **sugar** (defer) | `flat_map(xs, x -> x)`. Admit as alias only if a direct double-nest site appears; out of v0. |
| `zip_with` | **sugar** | `map(zip(a,b), pair -> f(pair))`. Admit only if pair-destructuring ergonomics warrant. |
| `enumerate` / `with_index` | **sugar** | `zip(range(0,count(xs)), xs)`. Sugar once `range`+`zip` are canon. |
| `sort_by` / `order_by` | **core later** | needs a **total, stable comparator** policy + Float-sort hazard diagnostic (§4/§6). Report/table pressure. |
| `group_by` | **core later** | needs typed `Map[K, Collection[V]]` building + key equality. Report/aggregation pressure. |
| `index_by` | **core later** | typed `Map[K, V]`; relational projection (id→row). |
| `distinct_by` | **core later** | depends on equality + stable order determinism. |
| `chunk` / `window` | **core later** | deterministic + pure; science windowing + report pagination. Needs a fixed-size contract. |
| `scan` | **core later / defer** | running fold; no concrete pressure yet — defer behind `fold`. |
| `join` (relational) | **host** | relational join is projection/query authority (`read_dispatch`/data-projection), NOT a pure in-memory stdlib collection. Reject from stdlib. |
| lazy streams / transducers | **reject (now)** | no performance proof yet (§6); revisit only behind a bench. |

≥12 ops classified (16 above).

## 4. Type-system gaps + diagnostics

1. **Empty collection literal `[]` element inference.** `[]` resolves to `Collection[Unknown]`; with
   no downstream constraint the element type never refines. Needed for `fold` seeds and empty-branch
   `if`. → **typed-empty card** (P4): context-propagate the expected element type into `[]`
   (mirrors `map_empty` context-deferred inference already noted in the inventory).
2. **Typed `fold` empty seed.** `fold(xs, seed, acc -> …)` with `seed = []` or `seed = {}` needs the
   seed's element/record type from the declared output. The fold-to-struct track (OOF-COL4) handles
   the struct-accumulator case; the empty-collection seed is the remaining gap.
3. **Lambda body returning record / collection / option / result.** `flat_map` needs body =
   `Collection[B]` (new **OOF-COL9**, from the flat_map PROP). `group_by`/`index_by` need body = key;
   record-returning lambdas already work (record-literal inference closed). Generic preservation of
   `B` through HOFs is the recurring risk.
4. **Generic element preservation.** P8a's `String`/`Text` canonicalization fix (`canonical_scalar_name`)
   showed scalar-name comparison was raw; element-type preservation through chained HOFs needs the
   same care (a `map` then `filter` must not erase `B`).
5. **Field access after HOF.** `map(rows, r -> r.amount)` then aggregate — works today; nested
   `map(rows, r -> map(r.items, …))` is the double-nest that `flat_map` resolves.
6. **OOF codes:** reuse `OOF-COL1` (arity), `OOF-COL2` (first-arg-not-collection); **new `OOF-COL9`**
   (lambda body not a collection, flat_map). Future: a **sort/compare diagnostic** (non-total or
   Float comparator) when `sort_by`/`group_by` land — reserve `OOF-COL10`.

## 5. Syntax recommendations

- **Keep function calls as the base surface.** `flat_map(xs, x -> …)` etc. — every op above is a
  registered HOF; no new syntax required to ship the core algebra.
- **Comprehensions:** readiness exists (P1/P2). They **lower to** `map`/`filter`/`filter_map`/
  `flat_map`/`fold` — so they should land *after* that algebra is canon, as pure sugar with no new
  runtime. Recommend a syntax-decision card, not an ad-hoc feature.
- **Expression pipe `|>`:** does **not** exist (the canon `pipeline` keyword is a decl-level OLAP
  construct). A value-level `xs |> filter(…) |> map(…)` would restore the flow dimension and lowers to
  nested HOF calls (sugar only). High DX leverage (noted in the data-projection work) but a distinct
  syntax decision — pair it with the comprehension card so canon picks **one** flow surface, not two.
- **Builders for descriptors:** mostly a **host/projector** concern (ViewArtifact/mesh builders), not
  stdlib collections — keep out of the core algebra.
- Do not invent syntax that doesn't lower to existing canon primitives.

## 6. Determinism + authority boundary

- **Deterministic, replay-safe (pure in-memory):** `map, filter, filter_map, flat_map, concat, append,
  zip, take, drop, find, any, all, fold, sum, count, range, chunk, window` — order-preserving over the
  input order; safe for the replay/receipt model.
- **Order-sensitive / needs an explicit policy:** `sort_by`, `group_by` (group order), `distinct_by`.
  These require a **total, stable comparator**; ship them only with a documented stability rule.
- **Floating comparisons are a hazard:** sorting/grouping by `Float` (NaN, -0.0) is non-total →
  must fail closed or require a total key. Decimal compares scale-normalized (safe); Float sort needs
  a diagnostic. This is the determinism crux of the §3 "core later" cluster.
- **Authority line (explicit):** stdlib collections are **pure in-memory transforms**. Relational
  `join`, query planning, and host-backed reads are **projection/query authority** (`read_dispatch`,
  the data-projection boundary), NOT stdlib collections. `index_by`/`group_by` build in-memory Maps
  from already-materialized rows — allowed; reaching back to a DB is not.

## 7. Performance risks (name-what-to-bench, not a bench card)

- **Repeated `concat`/`append` → O(n²).** Building a list by appending in a fold reallocates each
  step. Bench: fold-with-append vs flat_map vs a single `concat`-of-lists.
- **Intermediate allocation chains.** `map` then `flatten`/`flat_map`, or `filter` then `map`, each
  materializes a full intermediate `Collection`. Bench the chain depth where it matters.
- **VM budget interaction.** `MAX_COLLECTION_ELEMENTS = 1_000_000` (`vm.rs`); `flat_map`/`range` can
  multiply sizes fast — confirm the budget check fires on the *flattened* size, not just inputs.
- **Large ViewArtifact / report / science vectors.** The realistic large-N sites. Bench mesh
  emission (`flat_map` over bodies) and a report fold over many rows.
- **Transducers / lazy streams:** a possible mitigation for the alloc chains, but **defer** until a
  bench proves the pain — do not pre-build laziness.

## 8. Ranked roadmap (named cards)

1. **`LANG-STDLIB-COLLECTION-FLATMAP-P3` / `-P4`** (already named in the flat_map PROP) — land
   `flat_map` in canon Ruby then lab Rust parity. *Unblocks mesh/descriptor pressure now.*
2. **`LANG-STDLIB-COLLECTION-ALGEBRA-PARITY-PROP-P1`** — admit the **lab-ahead, deterministic, proven**
   ops to canon with contracts: `zip`, `take`/`drop`, `find`, `any`, `all` (and `reduce`→`fold`
   aliasing policy). Cheap, high-coverage; closes the canon↔lab algebra gap. *Highest ratio.*
3. **`LANG-STDLIB-TYPED-EMPTY-AND-FOLD-SEED-P1`** — context-propagate the element type into `[]`/`{}`
   seeds (fold + empty branches). The highest-leverage **type** fix; unblocks typed accumulators.
4. **`LANG-STDLIB-COLLECTION-ORDER-GROUP-READINESS-P1`** — readiness/decision for `sort_by`,
   `group_by`, `distinct_by`, `index_by`: the total/stable comparator policy, Float-sort hazard +
   `OOF-COL10`, and `Map[K,V]` building. *Decision before code.*
5. **`LANG-STDLIB-COLLECTION-FLOW-SYNTAX-DECISION-P1`** — pick ONE flow surface: comprehensions (P1/P2)
   vs expression `|>` pipe; both lower to the core HOFs. Avoid shipping two.
6. **`LAB-STDLIB-COLLECTION-PERF-PROTOBENCH-P1`** — micro-bench the §7 risks (concat/append O(n²),
   map+flatten chains, 1M budget on flattened size). Names whether transducers are ever justified.
7. **`LANG-STDLIB-COLLECTION-FLATTEN-ENUMERATE-SUGAR-P1`** (optional, low priority) — `flatten`/
   `enumerate`/`zip_with` as sugar over `flat_map`/`range`/`zip`, only if direct sites appear.

Reject for now: relational `join` (host/query), lazy streams/transducers (no proof), `scan` (no
pressure).

## Non-goals (unchanged)

No implementation, no new parser syntax, no database query language, no lazy streams until a
performance proof, no blanket LINQ adoption without Igniter-specific pressure.

## Verification

```text
rg COLLECTION_*_FNS / inventory canonical_names / lab Rust + VM op arms  → §1 table grounded in live code
git diff --check  → PASS (research packet only; no code)
```
