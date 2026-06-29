# LANG-STDLIB-COLLECTIONS-HORIZON-RESEARCH-P1

Status: OPEN
Lane: lang / stdlib / collections / research / horizon
Mode: research-readiness
Skill: idd-agent-protocol

## Context

Immediate pressure has now produced a clear v0 primitive:

- `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`
- `LANG-STDLIB-COLLECTION-FLATMAP-PROP-P1` admits it as the next collection HOF.
- VM runtime is already proven; compiler registration follows in P3/P4.

But this is only the first visible pressure point. The broader pattern is larger:
Igniter applications keep wanting to transform structured data into structured
descriptors:

```text
domain rows      -> ViewArtifact nodes
world bodies     -> mesh primitives / triangles
query rows_json  -> typed app rows / projections
science vectors  -> derived vectors / aggregates / statistics
reports          -> sections / tables / exports
```

If we only add one-off collection functions reactively, agents will keep
rediscovering the same walls: flattening, grouping, indexing, windowing,
ordering, zipping, joins, folds with typed empty seeds, builder ergonomics, and
performance/replay boundaries.

This card is a research step beyond the current implementation wave. It should
produce a map of the next collection model, not another small helper.

## Goal

Design the next-horizon collection roadmap for Igniter:

- what collection operations belong in the core stdlib;
- what should be syntax sugar over existing operations;
- what should stay as host/projector/query-domain work;
- what must be typed and deterministic to preserve replay;
- what is needed for business apps, UI descriptors, reports, games, and science.

The output should be a decision-ready research packet with a ranked roadmap and
named implementation cards. No production code changes.

## Inputs To Read First

Live/code evidence:

- `lab-docs/lang/lang-stdlib-collection-flatmap-prop-p1-v0.md`
- `lab-docs/lang/lab-stdlib-collection-flatmap-or-concat-p1-v0.md`
- `lab-docs/lang/lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md`
- `lab-docs/lang/lab-igniter-data-projection-boundary-readiness-p1-v0.md` if present
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-vm/src/vm.rs`
- collection tests under `lang/igniter-compiler/tests` and `lang/igniter-vm/tests`

Prior cards/evidence:

- `LAB-LANG-COLLECTION-COMPREHENSION-READINESS-P1`
- `LAB-LANG-COLLECTION-COMPREHENSION-P2`
- `LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2`
- `LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P*`
- `LANG-STDLIB-COLLECTION-CONCAT-PROP-P*`
- `LANG-STDLIB-COLLECTION-APPEND-P*`
- `LAB-STDLIB-COLLECTION-ZIP-*`
- any active TodoApp/ViewArtifact/data-projection cards that mention rows/lists.

External inspiration is allowed, but keep it short and cite the concrete idea
rather than turning this into a literature survey. Useful lenses:

- Rust iterators (`map`/`flat_map`/`fold`/`collect`);
- LINQ / query comprehensions;
- Clojure transducers;
- Haskell/F#/Scala list/sequence comprehensions;
- SQL relational operators;
- array languages / NumPy only where they reveal vector/science pressure.

## Research Questions

### 1. Core Algebra

What is the minimal coherent algebra after `map/filter/count/concat/append/zip`
and proposed `flat_map`?

Evaluate at least:

- `flatten(Collection[Collection[T]]) -> Collection[T]`
- `flat_map(Collection[A], A -> Collection[B]) -> Collection[B]`
- `fold/reduce` with typed empty seeds
- `scan`
- `any` / `all`
- `find` / `first_where`
- `sort_by` / `order_by`
- `group_by`
- `distinct_by`
- `index_by`
- `join` / `zip_with`
- `chunk` / `window`
- `take` / `drop`
- `enumerate` / `with_index`

For each, classify:

```text
core now / core later / syntax sugar / host concern / reject
```

### 2. Typing And Diagnostics

Where does the current type system struggle?

- empty collection literals (`[]`) and element inference;
- lambdas returning records/collections/options/results;
- nested collections;
- record field access after HOFs;
- generic element preservation;
- diagnostics for HOF lambda body type mismatch.

Name any needed OOF codes or reuse policy.

### 3. Syntax

Which surfaces are worth syntax and which should remain stdlib calls?

Compare:

- function calls: `flat_map(xs, x -> ...)`
- collection comprehensions;
- pipeline syntax if any exists/proposed;
- builder helpers for descriptors;
- `for` / local loop forms if present in proposals.

Avoid inventing syntax unless it clearly lowers to existing canon primitives.

### 4. Determinism And Authority

Classify operations by replay risk:

- deterministic pure data transforms;
- order-sensitive operations;
- comparison/sort stability;
- floating comparisons;
- host-backed reads/query operations that should NOT be stdlib collections.

Keep the boundary explicit: stdlib collections are pure in-memory transforms, not
database/query authority.

### 5. Performance Model

Look for the likely efficiency pain points:

- repeated `concat` / `append` O(n^2) behavior;
- intermediate allocation chains (`map` then `flatten`);
- streaming/transducer possibilities;
- VM collection budget interactions;
- large ViewArtifact/report/science vectors.

This is not a benchmark card, but it should name what to benchmark later.

### 6. App Pressure Matrix

Map operations to concrete pressure:

| Pressure | Needed operations |
| --- | --- |
| Todo/ViewArtifact rows | ? |
| 3D mesh / game descriptors | ? |
| reports/exports | ? |
| relational rows_json projection | ? |
| emergence/science vectors | ? |
| future Spark/TBackend ledgers | ? |

Use live examples where possible.

## Expected Output

Write:

```text
lab-docs/lang/lang-stdlib-collections-horizon-research-p1-v0.md
```

The packet should include:

1. live surface inventory;
2. pressure matrix;
3. operation taxonomy;
4. type-system gaps;
5. syntax recommendations;
6. determinism/authority boundary;
7. performance risks;
8. ranked roadmap with named cards.

## Acceptance

- [ ] Live collection surface verified from code/tests, not old docs alone.
- [ ] At least 12 candidate operations classified.
- [ ] At least 5 concrete app/science/business pressure cases mapped.
- [ ] Clear distinction between core stdlib, syntax sugar, host/query concerns,
      and rejected ideas.
- [ ] Type gaps and OOF/diagnostic needs named.
- [ ] Determinism and authority boundaries explicit.
- [ ] Performance risks named with proposed future benchmark cards.
- [ ] Ranked roadmap with 5-8 named follow-up cards.
- [ ] No production code changes.
- [ ] `git diff --check` clean.

## Suggested Next-Card Shape

The packet should likely end with something like:

```text
P2: flat_map implementation completion (if not already done)
P3: typed empty collection / fold seed inference
P4: collection builders or comprehensions
P5: order/sort/group readiness
P6: collection performance proto-bench
```

But let live evidence decide the exact order.

## Non-goals

- No implementation.
- No new parser syntax.
- No database query language.
- No lazy streams until there is a concrete performance proof.
- No broad “everything like LINQ” adoption without Igniter-specific pressure.
