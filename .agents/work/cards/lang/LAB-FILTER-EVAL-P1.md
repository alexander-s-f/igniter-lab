# LAB-FILTER-EVAL-P1

**Card:** LAB-FILTER-EVAL-P1
**Track:** lab-query-filter-predicate-evaluation-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (50/50)
**Route:** LAB PROOF / QUERY SEMANTICS / IN-MEMORY MOCKED ROWS / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Prove the first semantic evaluation layer for `QueryPlan.filters`:
a `Collection[FilterPredicate]` can be applied to mocked in-memory rows and
produce deterministic `QueryResult` data, without SQL, database access, ORM,
or storage runtime authority.

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); chained field access |
| LAB-TC-ARRAY-P2 | Collection[FilterPredicate] record-field-context (19/19) |
| LAB-EXECUTE-QUERY-P1 | Inline filter array in QueryPlan (57/57); denial-as-data vocabulary |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/filter_eval.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_filter_eval_p1.rb` | DONE (50/50) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-filter-predicate-evaluation-over-mocked-rows-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-FILTER-EVAL-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (50/50)

| Section | n | Checks |
|---------|---|--------|
| FEVAL-COMPILE  | 5  | Fixture compiles; 9 contracts; Ruby TC all accepted; zero type_errors |
| FEVAL-SHAPE    | 7  | FilterPredicate.field/op/value; QueryPlan.filters=Collection[FilterPredicate]; QueryResult.count/kind/metadata |
| FEVAL-ARRAY    | 4  | Rust SIR: filters=Collection[FilterPredicate]; plan=QueryPlan; output port; inline empty array |
| FEVAL-SEMANTICS| 7  | Layer C: eq/neq/contains/prefix; AND narrows; empty list=all rows; missing field=no match |
| FEVAL-RESULT   | 6  | rows/empty/query_error result kinds; count==length invariant; AND narrows count (3<4) |
| FEVAL-VM       | 8  | 6 contracts VM-executed: filter shapes, plan with filters, rows/empty/query_error, metadata chain |
| FEVAL-CLOSED   | 5  | No SQL/DB/ORM/StorageCapability/write at any layer |
| FEVAL-GAP      | 8  | In-memory only; AND-only v0; OR/NOT deferred; unknown op=query_error; G1–G6 absent; query_error≠denied |

---

## Closed surfaces (permanently in effect)

- Real DB / SQL execution / ORM / ActiveRecord: CLOSED
- StorageCapability live execution: CLOSED
- Transactions / persistence runtime: CLOSED
- Write ops: CLOSED
- OR / NOT / JOIN / aggregates: DEFERRED (v0 AND-only)
- Production filter runtime: CLOSED (FilterEvalSim is PROOF-LOCAL ONLY)
- Stable / public API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Igniter VM has no iteration opcodes — Layer C (FilterEvalSim) is required for row evaluation semantics; not a workaround but the correct boundary |
| B2 | Empty filter array → `Collection[FilterPredicate]` from record-field context — third confirmation of P2 mechanism |
| B3 | Unknown field ≠ unknown operator: field absence → `kind:"empty"`; bad op → `kind:"query_error"` — must not be collapsed |
| B4 | StorageCapability G1–G6 gate sequence is orthogonal to filter evaluation — filter semantics run after gates pass |

---

## Next authorized

- OR / NOT composition: requires explicit card + KNOWN_OPS extension
- Numeric operators (gt_integer, lt_integer): requires typed value variant card
- Production filter evaluation runtime: requires separate card (VM iteration opcodes or compiled-to-host)
- rows field in QueryResult: requires separate card (Collection[Map[String,String]] or typed Row)
