# LAB-QUERY-MULTI-ORDER-P1

**Card:** LAB-QUERY-MULTI-ORDER-P1
**Track:** lab-query-multi-column-order-over-mocked-rows-v0
**Status:** CLOSED — PROOF COMPLETE (64/64)
**Route:** LAB PROOF / QUERY SEMANTICS / NO DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Extend single-key ordering (`QueryPlan.order: OrderBy`) to multi-column ordering (`QueryPlanMultiOrder.order: Collection[OrderBy]`). Prove deterministic stable ordering over mocked rows with per-column asc/desc direction, priority key semantics, and stable-sort invariant for equal keys.

Core formula:
```
MultiOrder v0  =  mocked rows  +  Collection[OrderBy]  +  limit
               →  deterministic stable multi-column ordered rows + QueryResult
MultiOrder v0  ≠  sql order-by clause  ≠  DB runtime  ≠  ORM  ≠  index-backed sorting
MultiOrderSim  =  PROOF-LOCAL ONLY  ≠  production multi-order evaluation runtime
```

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-ORDER-LIMIT-P1 | Single-key order/limit semantics (54/54); order-then-limit invariant; stable sort |
| LAB-EXECUTE-QUERY-P2 | Integrated mocked pipeline (73/73); gate pipeline; MultiOrderQuerySim mirrors IntegratedQuerySim |
| LAB-FILTER-EVAL-P1 | Filter predicate evaluation (50/50); Layer C mocked row evaluation pattern |
| LAB-TC-ARRAY-P2 | `Collection[T]` from record-field context (19/19); 6th confirmation in this proof |
| LAB-TC-ARRAY-P1 | Empty array in Collection context (27/27) |
| PROP-043-P5 | `Map[String,String]` production TypeChecker (55/55) |
| LAB-VM-MAP-P1 | VM `map_get`/`or_else` (48/48) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_execution/multi_order_query.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_multi_order_p1.rb` | DONE (64/64) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-query-multi-column-order-over-mocked-rows-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-QUERY-MULTI-ORDER-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (64/64)

| Section | n | Checks |
|---------|---|--------|
| MORDER-COMPILE | 5 | Fixture compiles; 7 contracts; Ruby TC all accepted; zero type_errors |
| MORDER-SHAPE | 6 | Collection[OrderBy]; Collection[FilterPredicate]; limit Integer; OrderBy 2 fields; QueryResult 4 fields; Rust SIR type_tag |
| MORDER-SINGLE | 5 | Empty list preserves input order; single name asc; single name desc; P1 backward compat; empty list count |
| MORDER-MULTI | 8 | Two-key asc/asc; asc/desc; desc/asc; three-key; primary group boundary; secondary resolves ties; tertiary resolves secondary ties; count invariant |
| MORDER-STABLE | 5 | All-equal keys → input order; equal primary → secondary correct; equal primary+secondary → tertiary correct; equal all → input order; stable within group |
| MORDER-LIMIT | 4 | Limit 2 after three-key; limit==0 → empty; limit<0 → query_error; limit>rows → all |
| MORDER-ERROR | 5 | Unknown direction → query_error; missing field → query_error; empty direction → query_error; query_error≠denied; distinct messages |
| MORDER-INTEGRATED | 6 | Full pipeline rows; G1 denial short-circuits; filter before order; empty order; limit after order; G4 clamp |
| MORDER-VM | 7 | All 7 contracts VM-executed |
| MORDER-CLOSED | 8 | No SQL/DB/ORM/index-usage/joins/writes/capability-authority/persistence |
| MORDER-GAP | 5 | Proof-local only; numeric/date deferred; P1 backward compat; 6th P2 confirmation; no production runtime |

---

## Closed surfaces (permanently in effect)

- SQL query execution / DB runtime: CLOSED
- ORM / ActiveRecord / Arel: CLOSED
- StorageCapability live execution (IO authority): CLOSED
- Index hints / query optimizer usage: CLOSED
- Joins / aggregates: DEFERRED (v0 single-source)
- Write operations: CLOSED
- Numeric / date / locale-aware ordering: DEFERRED (v0 lexicographic String only)
- Collation-aware ordering: DEFERRED
- Production multi-order runtime: CLOSED (MultiOrderSim is PROOF-LOCAL ONLY)
- Public / stable API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Empty `Collection[OrderBy]` → preserve input order (no-op); valid, not an error |
| B2 | Empty direction in multi-order entry → `query_error`; differs from single-order P1 where empty direction = "no sort" |
| B3 | `ReverseComparable` pattern: desc values wrapped in class whose `<=>` reverses comparison; all positions have uniform type so `Array#<=>` is safe |
| B4 | Integer index tiebreaker in `sort_by` ensures stable sort for equal keys |
| B5 | `query_error` ≠ `denied` invariant confirmed for all malformed-order paths |
| B6 | `Collection[OrderBy]` from record-field context (LAB-TC-ARRAY-P2 — 6th confirmation) |
| B7 | `QueryPlanMultiOrder` is a new type — does not mutate existing `QueryPlan` |
| B8 | Order-then-limit invariant holds: limit applied AFTER all sort keys resolved |

---

## Key v0 multi-order semantics proved

### Order evaluation

| Input | Result |
|-------|--------|
| `order = []` | Preserve input order (no-op) |
| `direction: ""` in entry | `query_error` (explicit step, must have direction) |
| `direction: "unknown"` | `query_error` (NOT `denied`) |
| field absent in rows | `query_error` (NOT `denied`) |

### Priority order (3-key example: dept asc, level desc, name asc)

| Rows subset | Result |
|-------------|--------|
| `eng/senior/{charlie,bob}` | name asc resolves → bob, charlie |
| `eng/junior/{alice}` | alice |
| `mkt/senior/{dave}` | dave |
| `mkt/junior/{eve}` | eve |
| Final: | bob, charlie, alice, dave, eve |

### Stable sort (EQUAL_KEY_ROWS: dept=eng, level=senior, name=zoe for all 3)

All specified keys equal → input order preserved → idx=0, idx=1, idx=2.

---

## Next authorized

- Production multi-order runtime: separate card required
- Numeric/date ordering: deferred v0; separate card required
- Collation-aware ordering: separate card required
- Integrated multi-order + QueryExecutionReceipt: extend LAB-EXECUTE-QUERY-P2; separate card required
