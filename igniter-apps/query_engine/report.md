# Query Engine — Pressure Report

## What This Is

`query_engine` is a pure **query planner + executor**, pulled from the lab
`igniter-view-engine/fixtures` (query_plan / query_execution / storage_adapter). It
is the fleet's first app on the **relational axis**: a typed query intent over a
collection of records, executed as a pure data transformation.

```
QueryPlan ──► FilterRows (predicates, AND) ──► count + limit clamp ──► QueryResult
 (intent AST)   (over INJECTED Collection[Row])   (capability gate)     (Rows|Denied|QueryError)
```

A query is a `QueryPlan` (source + `Collection[FilterPredicate]` + order + limit).
Rows and the capability decision are **injected** at the boundary — there is no DB,
no SQL, no connection. The result is a kind-discriminated envelope, so a denial is
data, not an exception.

## Why This App Exists

Nothing in the fleet exercised **Collection-of-records** relational evaluation. This
app does, and it shows exactly where the relational story is solid (filter/fold over
records) and where it frays (stringly ops, no sort, no dynamic fields). It is the
clean motivation for a `FilterOp` sumtype and a `sort_by` stdlib.

## Pressure 1 — the relational core already works (positive)

The load-bearing pattern compiles **dual-clean**:

```igniter
compute kept = filter(rows, row ->
  if call_contract("MatchAll", row, preds) == 1 { true } else { false }
)
-- where MatchAll folds the predicates:
compute hits = fold(preds, 1, (acc, p) -> acc * call_contract("MatchPredicate", row, p))
```

A `filter` whose predicate folds a `Collection[FilterPredicate]` with a captured
`row` and a literal `call_contract` — map/filter/fold + nested record access — is
expressible today. The Collection-of-records substrate is real.

## Pressure 2 — stringly ops want a sumtype (QE-P01 / QE-P07)

`FilterPredicate.op : String` drives a six-way `if`-chain in `CompareInt`
(eq/neq/gt/gte/lt/lte). A sealed `FilterOp` variant + `match` would make it
exhaustive and fail-closed. The same predicate carries **both** `num` and `str`
because there is no `Int | Str` value sum — a typed value variant would unify them.
Both are direct demand for `LANG-SUMTYPE-CONSTRUCT-MATCH` to land construction +
match for sealed sums.

## Pressure 3 — no dynamic field projection (QE-P03)

`MatchPredicate` dispatches `p.field` ("age"/"id"/"city"/"active") via an if-chain
because there is no `row[field]`. Rows are a fixed schema; heterogeneous rows and
dynamic columns are impossible. This is honest and fail-closed today, but it caps
the engine at hand-enumerated columns — a real query engine wants a typed row schema
with projectable fields.

## Pressure 4 — no sort primitive (QE-P05)

`plan.order` is carried through the plan but **not applied** — there is no `sort_by`
over `Collection[T]`. Multi-key stable sort (the fixtures used a proof-local
`MultiOrderSim`) is the deeper gap and the cleanest motivation for a small
`LANG-STDLIB-COLLECTION-SORT`. Rows return in input order, documented.

## What We Need From IO

A real executor is a **storage-capability** application:

| Subsystem | What it needs from IO | Track |
|---|---|---|
| **Row source** | a StorageCapability read producing `Collection[Row]` | `PROP-046` storage + `PROP-035` effect surface |
| **Capability gate** | a passport decision (granted / denied / row-limit) | capability executor + passports |
| **Result sink / receipt** | a write capability to record the query receipt | effect write family |

The pure core (`FilterRows`, `MatchAll`, `ExecuteQuery`) stays CORE; IO is the thin
membrane that feeds it rows and a grant and carries the result out — the same
"pure core under an effect shell" shape as the other companions, here on the
data/relational axis.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 4 files, 4 types, 1 variant, 13
contracts, `entrypoint RunQuery`. A positive baseline and the fleet's first
relational/Collection-of-records evidence. See `PRESSURE_REGISTRY.md`.
