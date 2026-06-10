# LAB-QUERY-P3

**Card:** LAB-QUERY-P3
**Track:** lab-query-plan-nested-records-and-filter-collection-proof-v0
**Status:** CLOSED — PROOF COMPLETE (44/44)
**Route:** EXPERIMENTAL / LAB-ONLY
**Skill:** IDD Agent Protocol
**Agent:** [Igniter-Lang Implementation Agent]
**Role:** implementation-agent
**Category:** lang

---

## Goal

Prove that `QueryPlan` can carry richer pure query intent as nested typed data:
`Collection[FilterPredicate]`, nested `Projection`, nested `OrderBy`, `Map[String,String]`
metadata, and deterministic query-result mapping — without opening SQL execution,
real database access, ORM behavior, persistence runtime, StorageCapability execution,
joins, aggregates, writes, transactions, public API, or canon authority.

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P1 | Boundary research and closed surface map |
| LAB-QUERY-P2 | Flat QueryPlan proof (42/42), C1 chain, KDR |
| LAB-STORAGE-CAPABILITY-P1 | IO.StorageCapability design + denial-as-data |
| LAB-RECORD-VM-P3 | Nested field access (chained OP_GET_FIELD) |
| PROP-043-P5 | Map[String,String] production surface + C1 fix |
| LAB-VM-MAP-P1 | map_get + or_else VM runtime |

---

## Scope

### Prototype and prove
- `QueryPlan` v1 with 4 nested typed record fields (`QuerySource`, `Projection`, `Collection[FilterPredicate]`, `OrderBy`)
- `Collection[FilterPredicate]` as input type — Layer A + Layer B
- `[filter1, filter2]` array literal inference — Layer A (QPLAN3-ARRAY section)
- Chained field access: `plan.source.table`, `plan.order.direction` (two-hop OP_GET_FIELD)
- `Map[String,String]` metadata on richer QueryPlan shape (map_get + or_else)
- `QueryResult{kind:"denied"}` denial-as-data (no raise)
- Five-kind KDR routing in proof-local simulation (Layer C)

### Do not open
- SQL execution, real database, ORM, ActiveRecord
- StorageCapability execution (Stage 2+, ExecuteQuery effect contract)
- Joins, aggregates, writes, transactions
- Migrations, persistence runtime
- Public / stable / canon API

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture | `igniter-view-engine/fixtures/query_plan/query_plan_nested.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_query_p3.rb` | DONE — 44/44 |
| Lab doc | `lab-docs/lang/lab-query-plan-nested-records-and-filter-collection-proof-v0.md` | DONE |
| Card | `.agents/work/cards/lang/LAB-QUERY-P3.md` | DONE |
| Portfolio | `.agents/portfolio-index.md` | DONE |

---

## Proof results summary

**44/44 PASS** across 9 sections:

| Section | n | Summary |
|---------|---|---------|
| QPLAN3-COMPILE | 4 | Rust: 0 diagnostics, 8 contracts; Ruby TC: all 8 accepted, 0 type_errors |
| QPLAN3-TYPES | 6 | QueryPlan nested type env (source/projection/filters/order/limit/metadata) |
| QPLAN3-NESTED | 5 | BuildRichSelectPlan accepted + all nested input types typed correctly |
| QPLAN3-BUILD | 4 | All 4 builder contracts accepted |
| QPLAN3-ARRAY | 4 | Layer A: `[f1,f2]` → `Collection[FilterPredicate]` inferred, 0 type_errors |
| QPLAN3-VM | 8 | All VM runs succeed; nested records preserved through VM round-trip |
| QPLAN3-CHAIN | 4 | `plan.source.table`="users"; map_get hit="web"; or_else miss="unknown_source" |
| QPLAN3-KDR | 4 | kind="denied" denial-as-data; "empty"≠"denied"≠"query_error" |
| QPLAN3-CLOSED | 5 | No SQL, no DB conn code, no ORM, all pure CORE, no stable API claim |

---

## Key boundary findings

**B1 — Rust typechecker array_literal gap (v0 limitation)**
Array literal construction `[f1, f2]` accepted by Layer A (Ruby TC infers `Collection[FilterPredicate]`) but blocked by Rust typechecker `_ =>` catch-all in `igniter-compiler/src/typechecker.rs`. Resolution: pass `filters: Collection[FilterPredicate]` as input. Candidate next card: `LAB-TC-ARRAY-P1`.

**B2 — Chained field access confirmed on v1 shape**
`plan.source.table` (two OP_GET_FIELD hops) works via LAB-RECORD-VM-P3 recursive `compile_expr` fix. No regression.

**B3 — C1 chain portable across domain shapes**
`map_get(plan.metadata, key)` + `or_else(opt, default)` proved on richer QueryPlan v1. Chain is domain-shape-independent.

**B4 — Denial-as-data invariant holds in query domain**
`QueryResult{kind:"denied"}` constructed cleanly; no exception/raise. Consumer branches on `kind`. Same pattern as NetworkCapability denial.

---

## Next authorized routes

| Card | Route |
|------|-------|
| `LAB-TC-ARRAY-P1` | Add `ArrayLiteral` to Rust typechecker; prove `[f1,f2]` compiles |
| `LAB-EXECUTE-QUERY-P1` | ExecuteQuery effect contract form; mocked StorageCapability execution |
| `LAB-FILTER-EVAL-P1` | In-memory predicate evaluation over `Collection[FilterPredicate]` |

---

*LAB-ONLY. No canon claim. No framework compat. No public API. No stable surface.*
