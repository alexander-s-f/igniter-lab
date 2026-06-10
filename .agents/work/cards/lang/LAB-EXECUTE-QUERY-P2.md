# LAB-EXECUTE-QUERY-P2

**Card:** LAB-EXECUTE-QUERY-P2
**Track:** lab-execute-query-integrated-gates-filter-order-limit-receipt-v0
**Status:** CLOSED — PROOF COMPLETE (73/73)
**Route:** LAB PROOF / INTEGRATED MOCKED QUERY EXECUTION / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Integrate the previously separate mocked query layers into one coherent proof-local execution story: StorageCapability gates + filter evaluation + order/limit semantics + QueryExecutionReceipt. The first complete mocked `ExecuteQuery` pipeline.

Core formula:
```
ExecuteQueryMock v0 = QueryPlan + StorageCapability-shaped policy + mocked rows
                    → gated / filtered / ordered / limited QueryResult + QueryExecutionReceipt
ExecuteQueryMock v0 ≠ SQL execution ≠ DB runtime ≠ ORM ≠ production StorageCapability execution
```

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-EXECUTE-QUERY-P1 | StorageCapability gate sequence (57/57); G1–G6 gate pipeline |
| LAB-FILTER-EVAL-P1 | Filter evaluation semantics (50/50); Layer C mocked row evaluation pattern |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54); stable sort; order-then-limit invariant |
| LAB-STORAGE-CAPABILITY-P2 | Gate receipt fields (51/51); cap_checked/cap_granted invariants |
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44) |
| LAB-TC-ARRAY-P2 | `Collection[FilterPredicate]` from record-field context (19/19) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |
| LAB-RECORD-VM-P3 | Nested record field access (49/49) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/execute_query_integrated.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_execute_query_p2.rb` | DONE (73/73) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-execute-query-integrated-gates-filter-order-limit-receipt-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P2.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (73/73)

| Section | n | Checks |
|---------|---|--------|
| EXECQ2-COMPILE | 5 | Fixture compiles; 8 contracts; Ruby TC all accepted; zero type_errors |
| EXECQ2-SHAPE | 8 | Collection[FilterPredicate]; OrderBy; QueryResult 4 fields; StorageCapability; receipt 15 fields; Rust SIR type tag |
| EXECQ2-GATES | 6 | G1/G2/G3→denied; G4 clamp ≠ denial; G5→query_error; system_error distinct |
| EXECQ2-FILTER | 8 | eq/neq/contains/prefix; AND; empty list; missing field → empty; bad op → query_error |
| EXECQ2-ORDER-LIMIT | 8 | asc/desc; stable sort; empty direction; bad direction → query_error; limit 0/negative/order-then-limit |
| EXECQ2-INTEGRATED | 7 | Full pipeline rows/empty/bad-op/bad-dir/denied/clamped; query_error ≠ denied invariant |
| EXECQ2-RECEIPT | 7 | cap_checked; cap_granted invariant; denial_gate:G1; effective_limit; row_limit_clamped; rows_returned; result_kind |
| EXECQ2-VM | 8 | All 8 contracts VM-executed; plan filters array; cap shape; rows/empty/denied/query_error/receipt/metadata |
| EXECQ2-CLOSED | 9 | No SQL/DB/ORM/index-usage/joins/writes/transactions/capability-authority/persistence at any layer |
| EXECQ2-GAP | 7 | Complete pipeline; not production; no sql; Layer C proof-local; row_limit orthogonal; joins deferred; gate short-circuit |

---

## Closed surfaces (permanently in effect)

- SQL query execution / DB runtime: CLOSED
- ORM / ActiveRecord / Arel: CLOSED
- StorageCapability live execution (IO authority): CLOSED — StorageCapability is plain Record only
- Index hints / query optimizer usage: CLOSED
- Joins / aggregates: DEFERRED (v0 is single-source only)
- Write operations / transactions: CLOSED
- Numeric / date / locale-aware ordering: DEFERRED (v0 is lexicographic String only)
- Multi-column ordering: DEFERRED (v0 single OrderBy field)
- Production integrated query runtime: CLOSED (IntegratedQuerySim is PROOF-LOCAL ONLY)
- Public / stable API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Gate short-circuit before filter/order/limit is the correct model: G1/G2/G3 denial → rows:[], rows_returned:0, filter/order/limit never invoked |
| B2 | G4 clamp ≠ denial: effective_limit = min(plan.limit, cap.row_limit); cap_granted:true after clamp; row_limit_clamped:true records the clamp |
| B3 | G5 → kind:"query_error" (NOT "denied"): include_all is a plan field — malformed plan, fix before retry |
| B4 | query_error ≠ denied invariant confirmed throughout integrated pipeline across all 73 checks |
| B5 | QueryPlan.limit and StorageCapability row_limit are orthogonal: G4 clamp runs before G6 evaluation; must not be conflated |
| B6 | Collection[FilterPredicate] from record-field context — 5th confirmation across fixtures (LAB-TC-ARRAY-P2) |
| B7 | `message` is a Ruby parser keyword — use `deny_reason` / `reason` for input names in denied/query_error contracts |

---

## Key v0 pipeline semantics proved

### Gate routing

| Gate | Fires when | Result |
|------|-----------|--------|
| G1 | `source.table` not in `cap.allowed_sources` | `denied` |
| G2 | `"read"` not in `cap.allowed_ops` | `denied` |
| G3 | `cap.read_allowed == false` | `denied` |
| G4 | `plan.limit > cap.row_limit` | clamp only (NOT denied) |
| G5 | `projection.include_all && !cap.allow_include_all` | `query_error` |
| G6 | evaluate filter → order → limit | `rows`/`empty`/`query_error` |

### Filter operators

| Op | Semantics | Bad op result |
|----|-----------|---------------|
| `eq` | exact match | — |
| `neq` | not equal | — |
| `contains` | substring | — |
| `prefix` | starts with | — |
| other | `query_error` | NOT `denied` |

### Order semantics

| Direction | Result |
|-----------|--------|
| `"asc"` | Ascending lexicographic |
| `"desc"` | Descending lexicographic |
| `""` | Preserve input order |
| other | `query_error` (NOT `denied`) |

### Limit semantics

| Limit | Result |
|-------|--------|
| `> 0` | First `effective_limit` rows after filter+order |
| `== 0` | `empty` |
| `< 0` | `query_error` (NOT `denied`) |

---

## Next authorized

- Production integrated query execution: IntegratedQuerySim is PROOF-LOCAL only; separate card required
- Multi-column ordering: `order: Collection[OrderBy]` — separate card required
- Numeric/date ordering: string → typed coercion or typed Row record — deferred v0
- Joins / aggregates: single-source only in v0; separate card required
- Write execution: closed for this track; separate card required
