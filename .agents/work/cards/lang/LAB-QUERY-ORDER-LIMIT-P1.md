# LAB-QUERY-ORDER-LIMIT-P1

**Card:** LAB-QUERY-ORDER-LIMIT-P1
**Track:** lab-query-order-and-limit-semantics-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (54/54)
**Route:** LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Prove v0 `QueryPlan.order` and `QueryPlan.limit` semantics over mocked in-memory rows, complementing LAB-FILTER-EVAL-P1. An `OrderBy` record and an `Integer` limit can be applied to mocked rows and produce deterministic `QueryResult` data without SQL, database access, ORM, query optimizer, or storage runtime authority.

Core formula:
```
OrderLimit v0  =  mocked rows  +  OrderBy  +  limit  →  ordered/limited rows + QueryResult
OrderLimit v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
OrderLimit v0  ≠  StorageCapability row-limit gate
```

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); field access patterns |
| LAB-EXECUTE-QUERY-P1 | StorageCapability gate sequence (57/57); `message` keyword finding (B4) |
| LAB-FILTER-EVAL-P1 | Layer C mocked row evaluation pattern (50/50); denial-as-data vocabulary |
| LAB-TC-ARRAY-P2 | `Collection[FilterPredicate]` from record-field context (19/19) |
| PROP-043-P5 | Map[String,String] production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM map_get/or_else (48/48) |
| LAB-RECORD-VM-P3 | Nested record field access (49/49) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/order_limit.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_order_limit_p1.rb` | DONE (54/54) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-order-and-limit-semantics-over-mocked-rows-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-QUERY-ORDER-LIMIT-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (54/54)

| Section | n | Checks |
|---------|---|--------|
| OLIMIT-COMPILE  | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| OLIMIT-SHAPE    | 7 | OrderBy 2 fields; QueryPlan.order/limit; QueryResult count/kind/metadata |
| OLIMIT-SEMANTICS| 8 | asc/desc correct; stable sort; empty direction=preserve; unknown dir=query_error; missing field=query_error |
| OLIMIT-LIMIT    | 7 | limit 1/2/over/zero/negative; order-then-limit invariant; count==length |
| OLIMIT-RESULT   | 6 | rows/empty/query_error kinds; count invariant; metadata pass-through; KDR routes |
| OLIMIT-VM       | 8 | All 7 contracts VM-executed: OrderBy shapes, QueryPlan, rows/empty/query_error, metadata chain |
| OLIMIT-COMPOSE  | 4 | order-then-limit; filter→order→limit pipeline; StorageCapability row_limit orthogonal; lex comparison |
| OLIMIT-CLOSED   | 5 | No SQL/DB/ORM/StorageCapability/write at any layer |
| OLIMIT-GAP      | 4 | In-memory only; lex-only; row_limit gate distinct; unknown dir/neg limit = query_error not denied |

---

## Closed surfaces (permanently in effect)

- Real DB / SQL order-by execution / ORM / ActiveRecord: CLOSED
- StorageCapability live execution: CLOSED
- Transactions / persistence runtime: CLOSED
- Write ops: CLOSED
- Query optimizer / index hints: CLOSED
- Numeric/date/locale-aware ordering: DEFERRED (v0 is lexicographic String only)
- Multi-column ordering: DEFERRED (v0 single OrderBy field)
- Production order/limit runtime: CLOSED (OrderLimitSim is PROOF-LOCAL ONLY)
- Stable / public API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Igniter VM has no sort/iteration opcodes — Layer C (OrderLimitSim) is required for order/limit semantics; not a workaround but the correct boundary |
| B2 | `BuildQueryPlanOrderLimit` inline filter array types as `Collection[FilterPredicate]` from record-field context — fourth confirmation of LAB-TC-ARRAY-P2 mechanism |
| B3 | Unknown direction ≠ negative limit ≠ missing field — all three produce `kind:"query_error"` (NOT `"denied"`); all require fix-before-retry |
| B4 | `QueryPlan.limit` and `StorageCapability row_limit` are orthogonal concerns — capability gate runs before order/limit evaluation; must not be conflated |
| B5 | `input message : String` fails Ruby TypeChecker parse — `message` is a Ruby parser keyword; use `reason` instead (confirmed again from LAB-EXECUTE-QUERY-P1 B4) |

---

## Next authorized

- LAB-EXECUTE-QUERY-P2: integrate gate sequence + filter + order + limit + receipt in one mocked execution simulator — requires explicit card
- Multi-column ordering: `order: Collection[OrderBy]` — requires typed collection field, separate card
- Numeric/date ordering: requires type promotion in row values or typed Row record — deferred v0
- Production order/limit runtime: OrderLimitSim is PROOF-LOCAL only; separate card required

---

## Key v0 semantics proved

### Order

| Direction | Semantics |
|-----------|-----------|
| `"asc"` | Ascending lexicographic order |
| `"desc"` | Descending lexicographic order |
| `""` (empty) | No ordering; preserve input order |
| other | `kind:"query_error"` (NOT `"denied"`) |

- All comparisons are lexicographic String in v0.
- Stable sort: equal keys preserve input order.
- Missing order field in any row → `kind:"query_error"` (fail-closed).

### Limit

| limit | Result |
|-------|--------|
| `> 0` | First limit rows after ordering |
| `== 0` | `kind:"empty"`, count:0 |
| `< 0` | `kind:"query_error"` (NOT `"denied"`) |

- Limit applied AFTER ordering (order-then-limit invariant).
- `QueryPlan.limit` ≠ `StorageCapability row_limit` gate (orthogonal).
