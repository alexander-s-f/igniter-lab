# LAB-QUERY-ORDER-LIMIT-P1: Order and Limit Semantics Over Mocked Rows

**Track:** `lab-query-order-and-limit-semantics-over-mocked-rows-v0`
**Status:** CLOSED — PROOF COMPLETE (54/54)
**Route:** LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

`QueryPlan.order` and `QueryPlan.limit` are no longer just shape — they have v0 semantic meaning over mocked in-memory rows. An `OrderBy` record and an `Integer` limit can be applied to mocked rows and produce deterministic `QueryResult` data without SQL, database access, ORM, query optimizer, or storage runtime authority.

Specifically proved:
- Two `OrderBy` shapes (asc, desc) accepted at Layer A (Ruby TypeChecker) and Layer B (Rust compiler + VM).
- `BuildQueryPlanOrderLimit` inline filter array types as `Collection[FilterPredicate]` in the Rust SIR (record-field-context mechanism from LAB-TC-ARRAY-P2, confirmed again in this fixture).
- Layer C `OrderLimitSim` evaluates asc/desc lexicographic sort correctly over a 5-row deterministic dataset:
  - `asc`: alice → bob → carol → dave → eve (ascending by name)
  - `desc`: eve → dave → carol → bob → alice (descending by name)
- Stable sort: rows with equal order field values preserve their original input order.
- Empty direction string → no ordering applied; input order preserved.
- Limit applied AFTER ordering: limit 2 asc gives first-alphabetically 2 rows (alice, bob).
- `limit > 0` → return at most `limit` rows.
- `limit == 0` → `kind:"empty"`, count:0.
- `limit < 0` → `kind:"query_error"` (NOT `kind:"denied"`).
- Unknown direction → `kind:"query_error"` (NOT `kind:"denied"`).
- Missing order field in any row → `kind:"query_error"` (fail-closed).
- `count == returned_rows.length` holds as an invariant across all evaluations.
- Metadata pass-through preserved in result (no metadata dropped).
- KDR 3-kind routing: `rows` (process), `empty` (show empty state), `query_error` (fix plan field before retry).
- `QueryPlan.limit` is orthogonal to `StorageCapability row_limit` gate (the capability clamp is a separate concern at G4 in LAB-EXECUTE-QUERY-P1).
- All 7 contracts VM-executed: BuildOrderAsc, BuildOrderDesc, BuildQueryPlanOrderLimit, OrderLimitRows, OrderLimitEmpty, OrderLimitQueryError, OrderLimitMetadataReader.
- `OrderLimitMetadataReader` — `map_get + or_else` on `QueryResult.metadata` works on order/limit outputs.
- Filter → order → limit pipeline composes at Layer C: filter active rows first, then sort by name asc, then limit 2 produces alice and bob.

---

## Core formula

```
OrderLimit v0  =  mocked rows  +  OrderBy  +  limit  →  ordered/limited rows + QueryResult
OrderLimit v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
OrderLimit v0  ≠  StorageCapability row-limit gate
OrderLimitSim  =  PROOF-LOCAL ONLY  ≠  production order/limit evaluation runtime
```

---

## Files

| File | Purpose |
|------|---------|
| `igniter-view-engine/fixtures/query_execution/order_limit.ig` | 7 pure contracts (all CORE; no effect; no capability) |
| `igniter-view-engine/proofs/verify_lab_query_order_limit_p1.rb` | Proof runner — 54 checks, 9 sections |
| `lab-docs/lang/lab-query-order-and-limit-semantics-over-mocked-rows-v0.md` | This document |
| `.agents/work/cards/lang/LAB-QUERY-ORDER-LIMIT-P1.md` | Agent card |

---

## Type shapes

### OrderBy (2 fields)

```igniter
type OrderBy {
  field:     String,
  direction: String
}
```

### QueryPlan.order and QueryPlan.limit (same QueryPlan shape as prior proofs)

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

### QueryResult (same 4-field shape as LAB-FILTER-EVAL-P1)

```igniter
type QueryResult {
  kind:     String,
  count:    Integer,
  message:  String,
  metadata: Map[String, String]
}
```

**Note:** Ordered/limited rows are not stored in `QueryResult` in the Igniter fixture — the Igniter VM has no iteration/loop/sort opcodes. Row data is carried by the Layer C `OrderLimitSim` (Ruby). `count` in `QueryResult` reflects the number of returned rows.

---

## Contracts (7)

| Contract | Proves |
|----------|--------|
| `BuildOrderAsc` | `OrderBy { direction:"asc" }` shape |
| `BuildOrderDesc` | `OrderBy { direction:"desc" }` shape |
| `BuildQueryPlanOrderLimit` | QueryPlan with order + limit + inline filter array (LAB-TC-ARRAY-P2 mechanism) |
| `OrderLimitRows` | `QueryResult{kind:"rows", count:N}` — ordered/limited rows returned |
| `OrderLimitEmpty` | `QueryResult{kind:"empty", count:0}` — limit zero produces empty |
| `OrderLimitQueryError` | `QueryResult{kind:"query_error"}` — unknown direction or negative limit (≠ "denied") |
| `OrderLimitMetadataReader` | `map_get(result.metadata, key)` + `or_else` on order/limit output |

**Note on B5:** `OrderLimitQueryError` uses `input reason : String` (not `input message`) — `message` is a Ruby parser keyword and cannot be used as an input name (boundary finding B4 from LAB-EXECUTE-QUERY-P1, confirmed again here).

---

## v0 order semantics (Layer C)

### Direction

| Direction | Semantics | Sort key |
|-----------|-----------|----------|
| `"asc"` | Ascending lexicographic order | `row[field]` ascending |
| `"desc"` | Descending lexicographic order | `row[field]` descending |
| `""` (empty) | No ordering; preserve input order | N/A |
| other | `kind:"query_error"` (NOT `"denied"`) | — |

### Comparison model

All comparisons are **lexicographic String comparisons** in v0. Numeric, date, and locale-aware ordering are explicitly deferred.

### Stability

Ruby's `sort_by` is stable — rows with equal order field values preserve their original input order. This is the v0 guarantee.

### Missing field

If any row does not contain the order field, the result is `kind:"query_error"` (fail-closed). This is the v0 documented rule. Alternative: sort missing-field rows to end. v0 chose fail-closed because silently dropping/reordering rows is surprising.

---

## v0 limit semantics (Layer C)

| `limit` value | Result | Kind |
|---------------|--------|------|
| `> 0` | Return first `limit` rows (after ordering) | `rows` or `empty` |
| `== 0` | Return zero rows | `empty` |
| `< 0` | `kind:"query_error"` (NOT `"denied"`) | `query_error` |

**Order-then-limit invariant:** Limit is always applied AFTER ordering. `limit 2 desc` gives the top-2 rows in descending order, not an arbitrary 2 rows.

### QueryPlan.limit vs StorageCapability row_limit gate

These are orthogonal concerns:
- `QueryPlan.limit` — user-specified query intent (how many rows the query requests).
- `StorageCapability.row_limit` — capability clamp (G4 gate in LAB-EXECUTE-QUERY-P1) that enforces an upper bound independent of user intent.

A production path would apply G4 first (clamp effective_limit to min(plan.limit, cap.row_limit)), then pass effective_limit to the order/limit evaluation.

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

All 7 contracts accepted; zero type_errors. `OrderBy`, `QueryPlan`, `QueryResult` types in type_env with correct field types. `QueryPlan.order: OrderBy`, `QueryPlan.limit: Integer`.

### Layer B — Lab Rust compiler + VM

- Fixture compiles; 7 contracts; zero diagnostics.
- Rust SIR: `BuildQueryPlanOrderLimit.filters` compute_type_tag = `Collection[FilterPredicate]` (record-field-context mechanism — fourth confirmation across fixtures).
- VM: all 7 contracts VM-executed; all return `status:"success"` with correct shapes.

### Layer C — Proof-local OrderLimitSim (Ruby)

Pure Ruby implementation; in-memory Hash rows only. Proves semantic correctness of asc/desc lexicographic sort, stable sort, limit slicing, and all edge cases. `OrderLimitSim` is PROOF-LOCAL — not a production order/limit runtime.

---

## Proof results (54/54)

| Section | Checks | What was proved |
|---------|--------|-----------------|
| OLIMIT-COMPILE | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| OLIMIT-SHAPE | 7 | OrderBy 2 fields; QueryPlan.order/limit; QueryResult count/kind/metadata |
| OLIMIT-SEMANTICS | 8 | asc/desc correct; stable sort; empty direction=preserve; unknown dir=query_error; missing field=query_error |
| OLIMIT-LIMIT | 7 | limit 1/2/over/zero/negative; order-then-limit invariant; count==length |
| OLIMIT-RESULT | 6 | rows/empty/query_error kinds; count invariant; metadata pass-through; KDR routes |
| OLIMIT-VM | 8 | All 7 contracts VM-executed: OrderBy shapes, QueryPlan, rows/empty/query_error, metadata chain |
| OLIMIT-COMPOSE | 4 | order-then-limit; filter→order→limit pipeline; StorageCapability row_limit orthogonal; lex comparison |
| OLIMIT-CLOSED | 5 | No SQL/DB/ORM/StorageCapability/write at any layer |
| OLIMIT-GAP | 4 | In-memory only; lex-only; row_limit gate distinct; unknown dir/neg limit = query_error not denied |

---

## Boundary findings

### Finding B1: VM has no sort/iteration opcodes — Layer C required for order/limit semantics

The Igniter VM (v0) has no sort, iteration, or loop opcodes. It cannot sort a `Collection` of rows or apply a limit slice at runtime. The correct boundary:

- **Layer A + B**: Prove order/limit shapes (types, SIR, VM record construction).
- **Layer C**: Prove order/limit evaluation semantics over mocked rows (Ruby simulator).

Same pattern as LAB-FILTER-EVAL-P1 (B1). Not a workaround — the correct separation of concerns.

### Finding B2: Collection[FilterPredicate] from record-field context — fourth confirmation

`compute filters = [{ field: "status", op: "eq", value: "active" }]` in `BuildQueryPlanOrderLimit` types as `Collection[FilterPredicate]` from the QueryPlan.filters record-field context. This is the same LAB-TC-ARRAY-P2 mechanism confirmed in LAB-FILTER-EVAL-P1 and LAB-EXECUTE-QUERY-P1. Fourth confirmation across fixtures.

### Finding B3: Unknown direction ≠ negative limit ≠ missing field — all produce query_error, not denied

Three distinct v0 failure modes all route to `kind:"query_error"` (not `kind:"denied"`):
- Unknown direction string: malformed `OrderBy.direction`
- Negative limit: malformed `QueryPlan.limit`
- Missing order field in row: row data doesn't have the named column

All three require the consumer to fix the query plan before retry — none are access denial decisions.

### Finding B4: QueryPlan.limit and StorageCapability row_limit are orthogonal

`QueryPlan.limit` is user query intent. `StorageCapability.row_limit` is the capability gate (G4 in LAB-EXECUTE-QUERY-P1). A production path would compute `effective_limit = min(plan.limit, cap.row_limit)` before invoking the order/limit evaluation. These two concerns must not be conflated.

### Finding B5: `message` is a Ruby parser keyword — use `reason` for input names

`input message : String` fails to parse in the Ruby TypeChecker (boundary finding B4 from LAB-EXECUTE-QUERY-P1). `OrderLimitQueryError` uses `input reason : String` instead. Confirmed again in this fixture.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL order-by clause execution | Closed — no sql order-by, no ORDER\s+BY |
| Real database connection | Closed — no establish_connection, no ORM |
| StorageCapability live execution | Closed — no IO.StorageCapability, no effect contracts |
| Write ops / transactions | Closed |
| ORM / ActiveRecord / Arel | Closed |
| Query optimizer / index hints | Closed |
| Numeric/date/locale-aware ordering | Deferred — v0 is lexicographic String only |
| Multi-column ordering | Deferred — v0 supports single OrderBy field |
| Production order/limit runtime | Closed — OrderLimitSim is PROOF-LOCAL ONLY |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); field access patterns |
| LAB-EXECUTE-QUERY-P1 | StorageCapability gate sequence (57/57); `message` keyword finding (B4) |
| LAB-FILTER-EVAL-P1 | Layer C mocked row evaluation pattern (50/50); denial-as-data vocabulary |
| LAB-TC-ARRAY-P2 | `Collection[FilterPredicate]` from record-field context (19/19) |
| PROP-043-P5 | Map[String,String] production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM map_get/or_else (48/48) |
| LAB-RECORD-VM-P3 | Nested record field access (49/49) |

---

## KDR 3-kind routing (order/limit domain)

| Kind | Consumer action | Condition |
|------|----------------|-----------|
| `rows` | Process returned rows; count > 0 | One or more rows after order + limit |
| `empty` | Show empty state; no rows | Zero rows (limit==0, or limit larger than empty filtered set) |
| `query_error` | Fix plan field before retry | Unknown direction, negative limit, or missing order field |

Note: `denied` and `system_error` are not produced by order/limit evaluation — they belong to the StorageCapability gate sequence (LAB-EXECUTE-QUERY-P1).

---

## Next authorized routes

**For LAB-EXECUTE-QUERY-P2:**
- Integrate gate sequence + filter + order + limit + receipt in one mocked execution simulator.
- Requires explicit card.

**For multi-column ordering:**
- `order: Collection[OrderBy]` — requires typed collection field, separate card.
- v0 supports single OrderBy field only.

**For numeric/date ordering:**
- Requires type promotion in row values (string → Integer/Date coercion) or a typed Row record.
- Deferred — not in scope for v0.

**For production order/limit runtime:**
- OrderLimitSim is PROOF-LOCAL only; a production path requires a separate card.
- Will need either: (a) Igniter VM sort/iteration opcodes, or (b) compiled-to-host evaluation.

---

*LAB-ONLY. No canon claim. No framework compat. No public API.*
