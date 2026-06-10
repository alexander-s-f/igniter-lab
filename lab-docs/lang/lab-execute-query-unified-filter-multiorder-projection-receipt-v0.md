# LAB-EXECUTE-QUERY-P3
## Unified mocked query execution receipt — v0

**Track:** lab-execute-query-unified-filter-multiorder-projection-receipt-v0
**Status:** CLOSED — PROOF COMPLETE (68/68)
**Route:** LAB PROOF / INTEGRATED QUERY PIPELINE / NO DB
**Date:** 2026-06-10

---

## Core formula

```
UnifiedQuery v0  =  QueryPlanUnified + StorageCapability-shaped policy + mocked rows
                 →  gated / filtered / ordered / limited / projected QueryResult
                 +  QueryExecutionReceipt
UnifiedQuery v0  ≠  SQL execution  ≠  DB runtime  ≠  ORM  ≠  production StorageCapability
UnifiedQuerySim  =  PROOF-LOCAL ONLY  ≠  production unified query runtime
```

---

## Files

| Layer | Path | Purpose |
|-------|------|---------|
| Fixture | `igniter-view-engine/fixtures/query_execution/execute_query_unified.ig` | 6 types + 2 result types, 8 pure CORE contracts |
| Proof runner | `igniter-view-engine/proofs/verify_lab_execute_query_p3.rb` | 68 checks, 10 sections |
| Lab doc | `igniter-lab/lab-docs/lang/lab-execute-query-unified-filter-multiorder-projection-receipt-v0.md` | This file |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md` | Agent card |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Entry #58 |

---

## Types (8)

```igniter
type FilterPredicate   { field: String, op: String, value: String }
type QuerySource       { table: String, schema: String }
type Projection        { fields: String, include_all: Bool }
type OrderBy           { field: String, direction: String }

type QueryPlanUnified {
  kind:       String,
  source:     QuerySource,
  projection: Projection,
  filters:    Collection[FilterPredicate],
  order:      Collection[OrderBy],
  limit:      Integer,
  metadata:   Map[String, String]
}

type QueryResult {
  kind: String, count: Integer, message: String, metadata: Map[String, String]
}

type StorageCapability {
  cap_id: String, allowed_sources: Collection[String], allowed_ops: Collection[String],
  row_limit: Integer, allow_include_all: Bool, read_allowed: Bool,
  write_allowed: Bool, deny_reason: String
}

type QueryExecutionReceipt {
  cap_id: String, plan_kind: String, source_table: String, op_requested: String,
  cap_checked: Bool, cap_granted: Bool, denial_gate: String, deny_reason: String,
  plan_limit: Integer, row_limit_cap: Integer, effective_limit: Integer,
  row_limit_clamped: Bool, rows_returned: Integer, result_kind: String,
  metadata: Map[String, String]
}
```

`QueryPlanUnified` uses `Collection[OrderBy]` (multi-column, like MULTI-ORDER-P1) rather than single `OrderBy` (P2). Does not mutate `QueryPlan`, `QueryPlanMultiOrder`, or `QueryPlanProjection` from prior fixtures.

---

## Contracts (8 — all pure CORE)

| Contract | Purpose |
|----------|---------|
| `BuildUnifiedPlan` | QueryPlanUnified with inline filters (8th P2 confirmation) + 2-key order |
| `BuildUnifiedCapability` | StorageCapability schema-shaped record |
| `BuildUnifiedRowsResult` | QueryResult{kind:"rows"} |
| `BuildUnifiedEmptyResult` | QueryResult{kind:"empty"} |
| `BuildUnifiedDeniedResult` | QueryResult{kind:"denied"} |
| `BuildUnifiedQueryErrorResult` | QueryResult{kind:"query_error"} |
| `BuildUnifiedReceipt` | QueryExecutionReceipt (15 fields) for allowed execution |
| `UnifiedMetadataReader` | map_get(result.metadata, key) + or_else |

---

## v0 Pipeline order (Layer C)

```
 1. G1: source allowlist          → denied
 2. G2: op allowlist              → denied
 3. G3: read_allowed master       → denied
 4. G4: row-limit clamp           → effective_limit = min(plan.limit, cap.row_limit); NOT denial
 5. G5: include_all policy        → query_error (NOT denied)
 6. Apply filters                 → matched rows / query_error (bad op)
 7. Apply multi-column order      → sorted rows / query_error (bad dir / missing field)
 8. Apply effective_limit         → limited rows / empty / query_error (negative)
 9. Apply projection              → shaped rows / query_error (empty fields / missing field)
10. Build QueryResult + QueryExecutionReceipt
```

**G1/G2/G3 short-circuit:** filter, order, limit, and projection are NOT evaluated on denial.

**G4 clamp is NOT denial:** `cap_granted` stays `true` after clamping; `effective_limit` is recorded in receipt.

**G5 → query_error, NOT denied:** fires before filter/order/limit/projection.

**Projection is the final step:** comes after filter → multi-order → limit.

**Projection does not change row count:** it is a column selector, not a row filter.

**query_error ≠ denied throughout:** G1/G2/G3 → `denied`; all other failures → `query_error`.

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

- All 8 contracts: `status: "accepted"`
- Zero `type_errors`
- `QueryPlanUnified.filters` type: `Collection[FilterPredicate]`
- `QueryPlanUnified.order` type: `Collection[OrderBy]`
- `QueryPlanUnified.projection` type: `Projection`
- `QueryExecutionReceipt`: 15 fields

**TypeChecker boundary (B9 from PROJECTION-P1):** nested record literals inside outer record literals do not propagate inner field type context. `projection: { fields: "...", include_all: false }` embedded directly in the plan record literal fails OOF-TY0. Workaround: pass `projection` as an `input`. This card does not fix the TypeChecker; it reuses the same pattern.

### Layer B — Rust compiler + VM

**Compiler:** fixture compiles; SIR emitted for all contracts.

**Type tag (LAB-TC-ARRAY-P2 — 8th confirmation):**
```
BuildUnifiedPlan.filters  →  type_tag: Collection[FilterPredicate]
```

**VM execution — all 8 contracts:**

| Contract | Key assertion |
|----------|---------------|
| `BuildUnifiedPlan` | kind:"select"; filters array len 2; order_list len 2; limit:10 |
| `BuildUnifiedCapability` | cap_id:"cap-unified-v0"; row_limit:100; read_allowed:true |
| `BuildUnifiedRowsResult` | kind:"rows"; count:3 |
| `BuildUnifiedEmptyResult` | kind:"empty"; count:0 |
| `BuildUnifiedDeniedResult` | kind:"denied"; count:0; message non-empty |
| `BuildUnifiedQueryErrorResult` | kind:"query_error"; count:0 |
| `BuildUnifiedReceipt` | cap_granted:true; effective_limit:10; denial_gate:""; rows_returned:3 |
| `UnifiedMetadataReader` | map_get hit:"eng"; miss:"not-found" |

### Layer C — Proof-local UnifiedQuerySim

Test dataset (5 rows):
```ruby
UNIFIED_ROWS = [
  { 'name' => 'alice', 'status' => 'active',   'dept' => 'eng', 'score' => '10', 'role' => 'admin' },
  { 'name' => 'bob',   'status' => 'active',   'dept' => 'eng', 'score' => '20', 'role' => 'user'  },
  { 'name' => 'carol', 'status' => 'inactive', 'dept' => 'mkt', 'score' => '30', 'role' => 'user'  },
  { 'name' => 'dave',  'status' => 'active',   'dept' => 'mkt', 'score' => '40', 'role' => 'admin' },
  { 'name' => 'eve',   'status' => 'inactive', 'dept' => 'eng', 'score' => '50', 'role' => 'user'  },
]
```

**Happy path** (filter active + order [dept asc, name asc] + limit 10 + projection name,status):
- Filter(status=active): alice, bob, dave
- Order([dept asc, name asc]): alice(eng), bob(eng), dave(mkt)
- Limit(10): alice, bob, dave (all 3)
- Projection(name,status): `[{name:alice,status:active}, {name:bob,status:active}, {name:dave,status:active}]`
- Receipt: cap_granted:true; effective_limit:10; rows_returned:3; result_kind:"rows"

**Clamp path** (cap.row_limit=2):
- Same filter+order → alice, bob, dave; limit(2) → alice, bob; projection → 2 rows
- Receipt: effective_limit:2; row_limit_clamped:true; rows_returned:2

**Multi-column desc** (filter active + order [score desc] + limit 2 + projection name,score):
- Filter: alice(10), bob(20), dave(40); order(score desc): dave, bob, alice; limit(2): dave, bob
- Projection: `[{name:dave,score:40}, {name:bob,score:20}]`

---

## Proof results (68/68)

| Section | n | Checks |
|---------|---|--------|
| EXECQ3-COMPILE | 5 | Fixture compiles; 8 contracts; Ruby TC all accepted; zero type_errors |
| EXECQ3-SHAPE | 8 | QueryPlanUnified types; Collection[FilterPredicate/OrderBy]; Projection; receipt 15 fields; Rust SIR |
| EXECQ3-GATES | 6 | G1/G2/G3 denial; G4 clamp≠denial; G5 query_error; gate short-circuit |
| EXECQ3-PIPELINE | 7 | Happy path; filter/order/limit before projection; empty; clamp; multi-desc; no-order |
| EXECQ3-PROJECTION | 7 | include_all; field list; dedup; row count invariant; shape; values; key order |
| EXECQ3-RECEIPT | 6 | cap_checked; cap_granted; denial_gate; effective_limit; rows_returned; result_kind |
| EXECQ3-ERROR | 8 | Filter/order/projection errors → query_error NOT denied; invariant; informative messages |
| EXECQ3-VM | 8 | All 8 contracts VM-executed |
| EXECQ3-CLOSED | 8 | No SQL/DB/ORM/index/optimizer/joins/writes/transactions/StorageCapability |
| EXECQ3-GAP | 5 | Proof-local only; production? NO; typed Row[T] deferred; B9 documented; 8th P2 |

---

## Explicit answers

1. **Is the full v0 pipeline order proven?** YES — G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt
2. **Does projection happen after filter/order/limit?** YES — projection is the final step (G6d)
3. **Does G4 clamp remain non-denial?** YES — cap_granted:true after clamp; effective_limit recorded
4. **Does G5 include_all remain query_error, not denied?** YES — fires before filter/order/limit/projection
5. **Do all malformed plan errors remain query_error, not denied?** YES — confirmed for unknown filter op, unknown order direction, empty projection fields, missing projection field, negative limit
6. **Does receipt mirror the final pipeline result?** YES — result_kind and rows_returned reflect post-projection state
7. **Does this open production query runtime?** NO — UnifiedQuerySim is PROOF-LOCAL ONLY; no IO.StorageCapability; no effect contract; no DB
8. **What exact next route remains?** LAB-TC-NESTED-RECORD-CONTEXT-P1 (B9 TypeChecker gap — separate card); LAB-QUERY-TYPED-ROW-P1 (Collection[String] fields / typed Row[T] — deferred); production runtime — separate card required

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Full v0 pipeline order proven: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt |
| B2 | Projection is the final step — AFTER filter → multi-order → limit |
| B3 | G4 row-limit clamp remains NON-denial; cap_granted:true after clamp |
| B4 | G5 include_all policy → query_error (NOT denied); fires before projection |
| B5 | G1/G2/G3 short-circuit: filter/order/limit/projection NOT evaluated on denial |
| B6 | Projection does not change row count — column selector, not row filter |
| B7 | query_error ≠ denied throughout: G1/G2/G3→denied; all other failures→query_error |
| B8 | Receipt mirrors result_kind and rows_returned after full pipeline (after projection) |
| B9 | TypeChecker nested-record-literal boundary (from PROJECTION-P1): projection passed as input; gap documented; not fixed here |
| B10 | LAB-TC-ARRAY-P2 8th confirmation: BuildUnifiedPlan.filters typed Collection[FilterPredicate] in Rust SIR |

---

## Closed surfaces

- SQL SELECT generation / DB execution: CLOSED
- ORM / ActiveRecord / Arel: CLOSED
- StorageCapability live execution (IO authority): CLOSED
- Index hints / query optimizer: CLOSED
- Joins / aggregates: CLOSED (v0 single-source)
- Write operations: CLOSED
- Typed Row[T] / schema-aware projection: DEFERRED
- Collection[String] field list grammar: DEFERRED
- Production unified query runtime: CLOSED (UnifiedQuerySim is PROOF-LOCAL ONLY)
- Public / stable API: CLOSED

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline (73/73); gate sequence; receipt shape |
| LAB-QUERY-MULTI-ORDER-P1 | Collection[OrderBy] multi-column semantics (64/64); ReverseComparable; stable sort |
| LAB-QUERY-PROJECTION-P1 | Projection/include_all semantics (62/62); B9 boundary pattern |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50) |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54) |
| LAB-STORAGE-CAPABILITY-P2 | StorageCapability gate semantics (51/51) |
| LAB-TC-ARRAY-P2 | Collection[T] from record-field context (19/19); 8th confirmation |
| LAB-VM-MAP-P1 | VM map_get/or_else (48/48) |

---

## Next authorized routes

- TypeChecker nested-record-literal context propagation: separate card required (B9 boundary)
- Typed Row[T] / schema-aware projection: separate card required
- Collection[String] field list grammar: requires grammar change, separate card required
- Production unified query runtime: UnifiedQuerySim is PROOF-LOCAL ONLY — separate card required
- Hold all production runtime claims until the above are resolved
