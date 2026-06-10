# LAB-QUERY-P3: QueryPlan Nested Records and Collection[FilterPredicate] Proof

**Track:** `lab-query-plan-nested-records-and-filter-collection-proof-v0`
**Status:** CLOSED — PROOF COMPLETE (44/44)
**Route:** EXPERIMENTAL / LAB-ONLY
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

QueryPlan can carry richer pure query intent as nested typed data — without opening SQL execution, real database access, ORM behavior, persistence runtime, StorageCapability execution, joins, aggregates, writes, transactions, or public API.

Specifically proved:
- `QueryPlan` with 4 nested typed record fields (`QuerySource`, `Projection`, `FilterPredicate`, `OrderBy`) compiles clean in both Layer A (Ruby TypeChecker) and Layer B (Rust compiler + VM).
- `Collection[FilterPredicate]` as an **input type** is accepted by both layers.
- `[filter1, filter2]` array literal **infers** to `Collection[FilterPredicate]` in Layer A.
- Chained field access (`plan.source.table`) works via the two-hop `OP_GET_FIELD` path (LAB-RECORD-VM-P3 fix).
- `Map[String,String]` metadata on the richer `QueryPlan` shape supports `map_get` + `or_else` (C1 chain from PROP-043-P5 / LAB-VM-MAP-P1).
- Denial-as-data invariant holds in the query domain: `QueryResult{kind:"denied"}` constructed cleanly, no exception/raise.
- The five-kind `QueryResult` KDR vocabulary (`rows`, `empty`, `denied`, `query_error`, `system_error`) routes deterministically.

---

## Core formula

```
QueryPlan v1  =  nested typed records + Collection[FilterPredicate] + Map metadata
QueryPlan v1  ≠  ORM
              ≠  database connection
              ≠  persistence runtime
All contracts: pure → CORE. No IO. No StorageCapability.
```

---

## Files

| File | Purpose |
|------|---------|
| `igniter-view-engine/fixtures/query_plan/query_plan_nested.ig` | Igniter fixture (8 contracts, Module `Lab.Query.PlanBuilderV1`) |
| `igniter-view-engine/proofs/verify_lab_query_p3.rb` | Proof runner — 44 checks, 9 sections |
| `lab-docs/lang/lab-query-plan-nested-records-and-filter-collection-proof-v0.md` | This document |
| `.agents/work/cards/lang/LAB-QUERY-P3.md` | Agent card |

---

## QueryPlan v1 shape

```igniter
type QueryPlan {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      OrderBy,
  limit:      Integer,
  metadata:   Map[String, String]
}
```

### Nested types

```igniter
type QuerySource    { table: String, schema: String }
type Projection     { fields: String, include_all: Bool }
type FilterPredicate{ field: String, op: String, value: String }
type OrderBy        { field: String, direction: String }
```

### Result + denial types

```igniter
type QueryResult {
  kind:     String,   -- "rows"|"empty"|"denied"|"query_error"|"system_error"
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}
type StorageDenied { table: String, op: String, reason: String, kind: String }
```

---

## Contracts (8)

| Contract | Proves |
|----------|--------|
| `BuildFilterPredicate` | FilterPredicate record construction |
| `BuildOrderBy` | OrderBy record construction |
| `BuildProjection` | Projection record construction (Bool field) |
| `BuildQuerySource` | QuerySource record construction |
| `BuildRichSelectPlan` | Full QueryPlan v1 with all nested types |
| `PlanNestedFieldReader` | Chained field access `plan.source.table` |
| `PlanMetadataReader` | `map_get(plan.metadata, key)` + `or_else` |
| `QueryResultDenied` | Denial-as-data (`kind:"denied"`, no raise) |

---

## Proof results (44/44)

| Section | Checks | What was proved |
|---------|--------|-----------------|
| QPLAN3-COMPILE | 4 | Rust compiler: 0 diagnostics, 8 contracts; Ruby TC: 0 type_errors, all accepted |
| QPLAN3-TYPES | 6 | QueryPlan nested type env (source/projection/filters/order/limit/metadata) |
| QPLAN3-NESTED | 5 | BuildRichSelectPlan accepted; input types (Collection/QuerySource/Projection/OrderBy) |
| QPLAN3-BUILD | 4 | All 4 individual builders accepted |
| QPLAN3-ARRAY | 4 | Layer A: `[filter1,filter2]` infers `Collection[FilterPredicate]` (name+param), no type_errors |
| QPLAN3-VM | 8 | All VM runs succeed; nested records preserved through VM round-trip |
| QPLAN3-CHAIN | 4 | `plan.source.table` returns "users"; `map_get`+`or_else` hit+miss on richer plan |
| QPLAN3-KDR | 4 | `kind:"denied"` denial-as-data; "empty" ≠ "denied" ≠ "query_error" |
| QPLAN3-CLOSED | 5 | No SQL, no DB conn code, no ORM, all pure CORE, no stable API claim |

---

## Boundary findings

### Finding 1: Rust typechecker array_literal gap (v0 limitation)

**Layer A (Ruby TypeChecker):** Infers `[filter1, filter2]` → `Collection[FilterPredicate]` correctly.
`infer_array_literal` picks the type of the first non-Unknown element, wraps it in `Collection[...]`. No type errors.

**Layer B (Rust typechecker):** `ArrayLiteral` expression kind hits the `_ =>` catch-all in `igniter-compiler/src/typechecker.rs` (~line 3400-3411) → emits `OOF-TY0 "Unsupported expression kind: array_literal"`.

**Resolution for P3:** `BuildRichSelectPlan` takes `filters: Collection[FilterPredicate]` as an **input** (not a computed inline array literal). `Collection[FilterPredicate]` as an input type compiles cleanly in both layers. The array literal inference path is proved separately in the QPLAN3-ARRAY section (Layer A only).

**Candidate gap ticket:** `OOF-STORE1` or a new `OOF-TC-ARRAY`: "Rust typechecker does not handle ArrayLiteral expression kind — array literal construction blocked in Stage 1+."

### Finding 2: Chained field access works (LAB-RECORD-VM-P3)

`plan.source.table` requires two `OP_GET_FIELD` hops. The recursive `compile_expr` fix in `igniter-vm/src/compiler.rs` (LAB-RECORD-VM-P3) handles this correctly. `PlanNestedFieldReader` with nested QueryPlan input returns `"users"` from the VM.

### Finding 3: C1 chain on richer domain shape

The `map_get(plan.metadata, key)` + `or_else(opt, default)` chain proved in PROP-043-P5 / LAB-VM-MAP-P1 works identically on the richer `QueryPlan` v1 shape (with 4 nested records). Domain shape does not affect the Map operation.

### Finding 4: Denial-as-data invariant holds in query domain

`QueryResultDenied` constructs `{ kind: "denied", count: 0, message: reason, metadata: metadata }` cleanly. The consumer branches on `kind` — no exception/raise in the contract or VM. This establishes the same invariant proved for NetworkCapability in PROP-037-P2 / IOF-NET-P1.

---

## Closed surfaces

The following surfaces remain closed. Nothing in this proof opens them.

| Surface | Status |
|---------|--------|
| SQL execution | Closed — no `execute_sql`, `run_query`, `raw_sql` |
| Real database connection | Closed — no `establish_connection`, `database_url`, `AR::Base` |
| ORM / ActiveRecord | Closed — no `has_many`, `belongs_to`, `save!` |
| StorageCapability execution | Closed — Stage 2+ (ExecuteQuery effect contract, PROP-035) |
| Transactions | Closed |
| Joins / aggregates | Closed |
| Persistence runtime | Closed |
| Writes | Closed — fixture has no write contracts |
| Public / stable API | Closed — LAB-ONLY, no canon claim |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-QUERY-P1 | Boundary research — arel-like intent, closed surfaces |
| LAB-QUERY-P2 | Flat QueryPlan proof (42/42); C1 chain; KDR vocabulary |
| LAB-STORAGE-CAPABILITY-P1 | IO.StorageCapability schema + denial-as-data design |
| LAB-RECORD-VM-P3 | Recursive `compile_expr` fix — chained OP_GET_FIELD |
| PROP-043-P5 | Map[String,String] production surface + C1 fix |
| LAB-VM-MAP-P1 | `map_get` + `or_else` VM runtime |

---

## Next authorized routes

**For Rust typechecker array_literal gap:**
- Card: `LAB-TC-ARRAY-P1` — add `ArrayLiteral` handling to `igniter-compiler/src/typechecker.rs`; prove that `[f1, f2]` compiles through Rust typecheck pass with correct `Collection[FilterPredicate]` type

**For ExecuteQuery effect contract:**
- Card: `LAB-EXECUTE-QUERY-P1` — prove the `ExecuteQuery` effect contract form (PROP-035 grammar) compiles; show capability-checking wiring with a mocked `IO.StorageCapability`; requires StorageCapability execution surface (Stage 2+)

**For filter evaluation:**
- Card: `LAB-FILTER-EVAL-P1` — in-memory predicate evaluation over `Collection[FilterPredicate]`; no DB; pure; prove the eval loop in the VM

---

*LAB-ONLY. No canon claim. No framework compat. No public API.*
