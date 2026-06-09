# Card: LAB-QUERY-P1

**Category:** lang  
**Track:** lab-query-arel-like-data-access-pressure-boundary-v0  
**Status:** CLOSED — RESEARCH COMPLETE  
**Gate result:** boundary defined; design doc authored  
**Date closed:** 2026-06-09  
**Route:** RESEARCH / DESIGN / LAB-ONLY

---

## Goal

Research and define the first Igniter data-access pressure boundary inspired by
Arel/ORM use cases: what Igniter can express today as typed `QueryPlan` records,
what requires StorageCapability and mocked execution, what must remain permanently
closed, and what the exact v0 proof scope is.

**Core formula established:**  
Query v0 = typed intent AST + capability boundary + mocked execution.  
Query v0 ≠ ORM ≠ database connection ≠ ActiveRecord compatibility ≠ persistence runtime.

---

## Depends On

| Card | Status |
|------|--------|
| PROP-043-P5 (Map[String,String] production) | ✅ DONE |
| LAB-RESULT-ENVELOPE-P2 (KDR pattern 3 domains) | ✅ DONE |
| LAB-STDLIB-NET-P9 (ContractResult, capability model) | ✅ DONE |
| LAB-RACK-P14 (FullRackResponse reference) | ✅ DONE |
| LAB-SIDEKIQ-P5 (JobReceipt reference) | ✅ DONE |
| LAB-CONCURRENCY-P4 (pure DAG scheduling model) | ✅ DONE |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Research/design doc | `lab-docs/lang/lab-query-arel-like-data-access-pressure-boundary-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/lang/LAB-QUERY-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Arel/ORM Concept Classification (Summary)

### Adopt from Arel
- Query as composable data (AST-as-record)
- Delayed execution (plan separate from execution)
- Predicate composition (`Collection[FilterPredicate]`)
- Projection as explicit data (no implicit `SELECT *` in typed path)
- Renderer/executor separation (PlanSerializer ≠ production API)
- Source table as typed, auditable node
- Direction/order as data

### Permanently Closed (not "deferred" — excluded)
- ORM, ActiveRecord compatibility, lazy relation magic
- Global connection state
- Callbacks (`before_/after_`)
- Object identity persistence (`save!`)
- Implicit transactions
- Dynamic column access (`OOF-MAP2`)
- N+1 query generation
- Schema migration DSL

### Deferred to v1
- Joins (cross-source type complexity, N+1 risk)
- Aggregates (new projection node kind needed)
- Write operations (mutation capability not designed)
- OR/NOT predicate composition (variant grammar needed)
- Typed row projection `Row[T]` (variant grammar needed)

---

## QueryPlan v0 Type Shapes (Key Findings)

| Type | Fields | Fragment | Notes |
|------|--------|----------|-------|
| `QuerySource` | table:String, schema:String | CORE | Capability-checked at execution |
| `Projection` | fields:Collection[String], include_all:Bool | CORE | Explicit; never implicit |
| `FilterPredicate` | field:String, op:String, value:String | CORE | op: eq/neq/gt/gte/lt/lte/is_null |
| `OrderBy` | field:String, direction:String | CORE | direction: asc/desc |
| `QueryPlan` | source, projection, filters:Collection[FilterPredicate], order:Collection[OrderBy], limit:Integer, kind:String | CORE | kind: "select" in v0 |
| `QueryResult` | kind:String, rows:Collection[Map[String,String]], count:Integer, message:String, metadata:Map[String,String] | CORE | KDR convention |
| `StorageDenied` | table:String, op:String, reason:String, kind:String | CORE | kind always "denied" |

**No new grammar needed for v0.** All types expressible as named Records today.

---

## QueryResult Kind Vocabulary

| Kind | Meaning | Consumer action |
|------|---------|----------------|
| `"rows"` | Query executed; rows returned | Iterate and process |
| `"empty"` | Query executed; zero rows matched | Show empty state |
| `"denied"` | StorageCapability rejected source/op | Do not retry; denial-as-data |
| `"query_error"` | Malformed plan (bad field, bad op) | Fix the query |
| `"system_error"` | Infrastructure failure | Retry later |

---

## Capability Boundary

- Plan-building contracts: `pure` → CORE; no capability needed
- Plan execution (future v1+): `effect` → requires `IO.StorageCapability`
- StorageCapability carries: `allowed_sources`, `allowed_ops`, `row_limit`, `allow_include_all`
- Denial-as-data: `QueryResult { kind: "denied" }` — never exception/raise
- v0: execution is mocked only (Layer C simulation)

---

## Fragment Classification

| Contract | Class | Reason |
|----------|-------|--------|
| BuildSelectQuery, BuildFilteredQuery | CORE | Pure; no IO |
| QueryRouter, QueryMetadataReader | CORE | Pure; kind-discriminant; no IO |
| ExecuteQuery (future v1+) | ESCAPE → STORAGE | IO.StorageCapability required |

A future **STORAGE** fragment class (ch4 extension) would be needed for the
execution path — analogous to TEMPORAL for TBackend reads. This is Stage 2+.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Query/Arel-like pressure should open now? | **YES** — typed QueryPlan as Records; no grammar needed; real application pressure |
| ORM implementation too early? | **YES and permanently incompatible** for ORM patterns |
| Query intent expressible as typed records today? | **YES** — all v0 types are named Records in Stage 1 subset |
| SQL/string generation proof-local only? | **YES** — PlanSerializer is Layer C sim only |
| Execution mocked only for v0 proof? | **YES** — Layer C sim; pure contracts in VM |
| StorageCapability required before execution? | **YES** — pure plan-building needs none; effect execution needs it |
| Joins deferred? | **YES** — v1 |
| Aggregates deferred? | **YES** — v1 |
| ActiveRecord compatibility closed? | **YES — permanently** |
| Database runtime closed? | **YES** — no DB connections in any lab version without auth |
| Exact next route? | **LAB-QUERY-P2** — see below |

---

## Next Route: LAB-QUERY-P2

**Fixture:** `fixtures/query_plan/query_plan.ig`  
Module: `Lab.Query.PlanBuilder`  
Contracts (5): `BuildSelectQuery`, `BuildFilteredQuery`, `BuildProjection`, `QueryMetadataReader`, `QueryMapper`

**Proof runner:** `proofs/verify_lab_query_p2.rb`  
Sections: QPLAN-COMPILE(4) + QPLAN-TYPES(5) + QPLAN-BUILD(6) + QPLAN-DENIED(4) + QPLAN-MAP(4) + QPLAN-VM(5) + QPLAN-ROUTE(5) + QPLAN-COMPARE(4) + QPLAN-CLOSED(5) = **42 checks**

**Gate:** 42/42 PASS → LAB-QUERY-P2 closed → optional IO.StorageCapability design

---

## Authority

Lab-only — no canon claim, no stable surface, no framework compat.  
No production files changed. No grammar added. No VM modified.  
No PROP opened. No SQL connection established.
