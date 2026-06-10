# LAB-EXECUTE-QUERY-P3

**Card:** LAB-EXECUTE-QUERY-P3
**Track:** lab-execute-query-unified-filter-multiorder-projection-receipt-v0
**Status:** CLOSED — PROOF COMPLETE (68/68)
**Route:** LAB PROOF / INTEGRATED QUERY PIPELINE / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Unify the query semantics proven across P2 + MULTI-ORDER + PROJECTION into one complete proof-local ExecuteQuery pipeline:

```
StorageCapability-shaped gates
→ filters
→ multi-column order
→ limit / row-limit clamp
→ projection
→ QueryResult + QueryExecutionReceipt
```

This is the "complete mocked query execution story" for v0.

---

## Explicit answers (from card requirements)

1. **Is the full v0 pipeline order now proven?** YES — G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt; all 10 steps proved in Layer C UnifiedQuerySim
2. **Does projection happen after filter/order/limit?** YES — projection is step 9 (final pipeline step, after filter→multi-order→limit)
3. **Does G4 clamp remain non-denial?** YES — `cap_granted:true` after clamp; `effective_limit = min(plan.limit, cap.row_limit)` recorded in receipt
4. **Does G5 include_all remain query_error, not denied?** YES — G5 fires at step 5, before filter/order/limit/projection are evaluated
5. **Do all malformed plan errors remain query_error, not denied?** YES — unknown filter op, unknown order direction, empty projection fields, missing projection field, negative limit all → `query_error` (NOT `denied`); `query_error ≠ denied` invariant confirmed throughout
6. **Does receipt mirror the final pipeline result?** YES — `result_kind` and `rows_returned` in receipt reflect post-projection state; `cap_checked:true` in all cases; `cap_granted:false` iff denied/query_error
7. **Does this open production query runtime? Answer must be NO.** NO — `UnifiedQuerySim` is PROOF-LOCAL ONLY; no `IO.StorageCapability`; no `effect contract`; no DB; no SQL; `UnifiedQuery v0 ≠ production StorageCapability execution`
8. **What exact next route remains?** LAB-TC-NESTED-RECORD-CONTEXT-P1 (B9 TypeChecker nested-record-literal gap — separate card); LAB-QUERY-TYPED-ROW-P1 (Collection[String] field list / typed Row[T] — deferred until projection strings become limiting); production runtime — separate card required

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline (73/73); gate sequence; QueryExecutionReceipt 15-field shape |
| LAB-QUERY-MULTI-ORDER-P1 | Collection[OrderBy] semantics (64/64); ReverseComparable pattern; stable sort |
| LAB-QUERY-PROJECTION-P1 | Projection/include_all semantics (62/62); B9 TypeChecker boundary pattern |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50) |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics (54/54) |
| LAB-STORAGE-CAPABILITY-P2 | StorageCapability gate semantics (51/51) |
| LAB-TC-ARRAY-P2 | Collection[T] from record-field context (19/19); 8th confirmation in this proof |
| LAB-VM-MAP-P1 | VM map_get/or_else (48/48) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/execute_query_unified.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_execute_query_p3.rb` | DONE (68/68) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-execute-query-unified-filter-multiorder-projection-receipt-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (68/68)

| Section | n | Checks |
|---------|---|--------|
| EXECQ3-COMPILE | 5 | Fixture compiles; 8 contracts; Ruby TC all accepted; zero type_errors |
| EXECQ3-SHAPE | 8 | QueryPlanUnified types; Collection[FilterPredicate/OrderBy]; Projection; receipt 15 fields; Rust SIR 8th P2 |
| EXECQ3-GATES | 6 | G1/G2/G3 denial; G4 clamp≠denial; G5 query_error; gate short-circuit |
| EXECQ3-PIPELINE | 7 | Happy path; filter/order/limit before projection; empty; clamp; multi-desc; no-order |
| EXECQ3-PROJECTION | 7 | include_all; field list; dedup; row count invariant; shape; values; key order |
| EXECQ3-RECEIPT | 6 | cap_checked; cap_granted; denial_gate; effective_limit; rows_returned; result_kind |
| EXECQ3-ERROR | 8 | Filter/order/projection errors → query_error NOT denied; invariant; informative messages |
| EXECQ3-VM | 8 | All 8 contracts VM-executed |
| EXECQ3-CLOSED | 8 | No SQL/DB/ORM/index/optimizer/joins/writes/transactions/StorageCapability |
| EXECQ3-GAP | 5 | Proof-local only; production? NO; typed Row[T] deferred; B9 documented; 8th P2 |

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

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Full v0 pipeline order proven: G1→G2→G3→G4→G5→filter→multi-order→limit→projection→receipt |
| B2 | Projection is the final step — AFTER filter → multi-order → limit |
| B3 | G4 row-limit clamp remains NON-denial; cap_granted:true after clamp |
| B4 | G5 include_all policy → query_error (NOT denied); fires before projection |
| B5 | G1/G2/G3 short-circuit: filter/order/limit/projection NOT evaluated on denial |
| B6 | Projection does not change row count — column selector, not row filter |
| B7 | query_error ≠ denied throughout pipeline |
| B8 | Receipt mirrors result_kind and rows_returned after full pipeline (after projection) |
| B9 | TypeChecker nested-record-literal boundary (from PROJECTION-P1): projection passed as input; gap documented |
| B10 | LAB-TC-ARRAY-P2 8th confirmation: BuildUnifiedPlan.filters typed Collection[FilterPredicate] in Rust SIR |

---

## Next authorized

- TypeChecker nested-record-literal context propagation: separate card required (B9 boundary)
- Typed Row[T] / schema-aware projection: separate card required
- Collection[String] field list grammar: requires grammar change, separate card required
- Production unified query runtime: UnifiedQuerySim is PROOF-LOCAL ONLY — separate card required
- LAB-TC-NESTED-RECORD-CONTEXT-P1 is the clearest technical debt if TypeChecker shape pain remains
- Hold LAB-QUERY-TYPED-ROW-P1 until projection string encoding becomes the limiting issue
