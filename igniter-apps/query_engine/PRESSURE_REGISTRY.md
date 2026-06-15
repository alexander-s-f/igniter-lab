# Query Engine Pressure Registry

Created: 2026-06-14 (off-track app — pulled from `igniter-view-engine/fixtures`:
query_plan / query_execution / storage_adapter)

`query_engine` is a pure **query planner + executor** — no SQL, no ORM, no DB. A
query is a typed intent AST (`QueryPlan`: source + `Collection[FilterPredicate]` +
order + limit). Execution is a pure transformation over INJECTED rows plus a
capability decision, returning a kind-discriminated `QueryResult` (denial-as-data).
It is the fleet's first app on the **relational / Collection-of-records** axis.

## Baseline

Dual-toolchain CLEAN (verified via the Open3 / MultifileResolver subprocess route).

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/query_engine/types.ig ../igniter-apps/query_engine/eval.ig \
  ../igniter-apps/query_engine/execute.ig ../igniter-apps/query_engine/example.ig \
  --out /tmp/query_engine.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 4 |
| types | 4 |
| variants | 1 (`QueryResult` — Rows / Denied / QueryError) |
| contracts | 13 |
| call_contract sites | 22 (Tier-1 literals — static dispatch) |
| fold / filter / match | 1 / 1 / 2 |
| entrypoint | `RunQuery` |
| source_hash | `sha256:9ad658ea6e48d1abf0be56e5757e5cc36dc584d5564118730a1204a63e7fc613` |

> NOTE: verify Rust via the clean subprocess route (Open3 + mktmpdir); Ruby
> cross-module via `MultifileResolver#resolve` → classify → typecheck.

## Provenance (fixture → app)

| Fixture | query_engine model |
|---|---|
| `query_plan/query_plan.ig` (QueryPlan/FilterPredicate/OrderBy records) | `types.ig` QueryPlan + FilterPredicate + OrderBy |
| `query_execution/filter_eval.ig` (Collection[FilterPredicate] over mocked rows) | `eval.ig` MatchPredicate / MatchAll / FilterRows |
| `storage_adapter/*` (capability gate, denial-as-data, row-limit clamp) | `execute.ig` ExecuteQuery (cap gate + ClampLimit) |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| QE-P01 | **stringly filter op (wants FilterOp sumtype)** | `FilterPredicate.op : String` + the `CompareInt` if-chain (eq/neq/gt/gte/lt/lte). A sealed `FilterOp` variant + `match` would make it exhaustive + fail-closed. | ACTIVE | `LANG-SUMTYPE-CONSTRUCT-MATCH` (FilterOp variant + typed value slot) |
| QE-P02 | **result KDR (positive variant)** | `variant QueryResult { Rows \| Denied \| QueryError }` — denial-as-data as a sealed sum, not a stringly `kind`. | POSITIVE — capability | regression evidence for variant/match |
| QE-P03 | **no dynamic field projection** | `MatchPredicate` dispatches `p.field` ("age"/"id"/"city"/"active") via an if-chain — there is no `row[field]`. Heterogeneous rows + dynamic columns are impossible; new columns mean editing the contract. | ACTIVE — design | dynamic field access / typed row schema (deferred; fail-closed today) |
| QE-P04 | **nested row × predicate iteration** | `MatchAll` folds predicates (scalar AND via product) and `FilterRows` maps rows over it — the row×predicate nested iteration wants `flat_map`/nested fold. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR` (+ future nested-iteration) |
| QE-P05 | **no sort primitive** | `plan.order` is carried but NOT applied — there is no `sort_by` over `Collection[T]`. Multi-key stable sort is the deeper gap (the fixtures used a proof-local sim). | ACTIVE — stdlib gap | new `LANG-STDLIB-COLLECTION-SORT` (stable `sort_by`) |
| QE-P06 | **record-literal factories** | `MakeRow` / `MakePred` / `MakeOrder` exist only to pin record types (inline/array literals infer to Unknown in Rust). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` / `LAB-NESTED-RECORD-LITERAL-TYPING` |
| QE-P07 | **typed value slots** | `FilterPredicate` carries both `num` and `str` because there is no sum-of-value (`Int \| Str`) and no parse; a typed value variant would unify them. | ACTIVE | `LANG-SUMTYPE-CONSTRUCT-MATCH` (value as a sealed sum) |
| QE-P08 | **effect surface — rows + capability are IO** | rows come from a StorageCapability read; the capability grant is a passport decision; both injected here. A real executor reads a backend and clamps to the cap's row limit. | DOCUMENTED — behind | `PROP-046` storage capability + `PROP-035` effect surface + IO-runtime |

## Capability Discovery (positive)

The heavy pattern `filter(rows, row -> fold(preds, 1, (acc,p) -> acc * MatchPredicate(row,p)))`
— a filter whose predicate folds a `Collection[FilterPredicate]` with a captured row
and a literal `call_contract` — **compiles dual-clean**. This proves the
Collection-of-records relational core (map/filter/fold + nested record access) is
expressible today; the gaps are at the edges (sumtype ops, sort, dynamic fields).

## Safety Interpretation

Proves the language can model a query planner + filter executor as a pure,
capability-gated, denial-as-data core. It does NOT claim: any SQL/DB/ORM, a real
storage read, sorting, OR/NOT/JOIN/GROUP BY, dynamic schemas, or typed value
coercion.

## Non-Goals

- No SQL / DB / ORM / connection / persistence.
- No sort (order carried, not applied).
- No OR / NOT / JOIN / GROUP BY / HAVING (flat AND filters only).
- No dynamic field projection / heterogeneous rows.
- No Map construction.
- No effect-surface / storage-capability implementation (pressure, not a fix).

## Recommended Route

1. `LANG-SUMTYPE-CONSTRUCT-MATCH` (QE-P01/P02/P07) — FilterOp + value variants.
2. `LANG-STDLIB-COLLECTION-SORT` (QE-P05) — stable `sort_by` for `plan.order`.
3. `LANG-FOLD-STRUCT-ACCUMULATOR` / nested iteration (QE-P04).
4. Storage capability + effect surface (QE-P08) once the IO membrane lands.

## Wave P13 Appendix Check (2026-06-15)

Ruby: ok/0. Rust: ok/0. Source files: 4. outside active fleet; appendix clean. This directory has a pressure registry but remains outside the 20-app active fleet metric inherited from Wave P12, so it is not counted as a P13 regression or resolution.
