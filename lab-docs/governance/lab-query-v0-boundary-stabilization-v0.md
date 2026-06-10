# LAB-QUERY-V0-STABILIZATION-P1 - Governance Doc
# Query v0 Boundary Stabilization

**Track:** query-v0-typed-intent-capability-mocked-execution-stabilization  
**Route:** GOVERNANCE / DESIGN STABILIZATION / NO NEW FEATURE WORK  
**Authority:** lab_evidence_only  
**Date:** 2026-06-10  
**Status:** CLOSED - stabilization packet authored  
**Predecessors:** LAB-QUERY-P1/P2/P3, LAB-STORAGE-CAPABILITY-P1/P2, LAB-EXECUTE-QUERY-P1/P2/P3, LAB-FILTER-EVAL-P1, LAB-QUERY-ORDER-LIMIT-P1, LAB-QUERY-MULTI-ORDER-P1, LAB-QUERY-PROJECTION-P1, LAB-TC-ARRAY-P1/P2, LAB-TC-NESTED-RECORD-CONTEXT-P1

---

## Purpose

Stabilize the Query track as a coherent v0 layer.

This packet defines the boundary that has now been proved by lab evidence:

```text
Query v0 =
  typed query intent AST
  + StorageCapability gates
  + deterministic mocked execution
  + QueryResult / QueryExecutionReceipt
  + denial-as-data and query_error separation
```

This is not a canon proposal, not a public API, and not a real IO implementation. It is a governance/design stabilization packet over existing evidence.

---

## 1. Definition of Query v0

Query v0 is a typed intent-and-receipt layer for read-shaped, single-source query work.

### QueryPlan as typed intent data

`QueryPlan` and its unified proof-local successor shape (`QueryPlanUnified`) are typed data, not execution authority. The v0 intent shape is:

| Type | v0 role |
|------|---------|
| `QuerySource` | Identifies the intended source, with table/schema-like strings. It is capability-checked later. |
| `Projection` | Describes row shaping: `fields:String` plus `include_all:Bool`. v0 field lists are stringly. |
| `FilterPredicate` | Describes one predicate: `field:String`, `op:String`, `value:String`. |
| `OrderBy` | Describes one order key: `field:String`, `direction:String`. |
| `QueryPlan` / `QueryPlanUnified` | Combines source, projection, filters, order, limit, kind, and metadata as typed Records. |

Plan construction is pure CORE. A plan does not connect to a database, open storage, execute SQL, or authorize itself.

### QueryResult as KDR outcome record

`QueryResult` is a kind-discriminated result record. The stable query-domain kind vocabulary is:

| Kind | Meaning | Consumer action |
|------|---------|-----------------|
| `rows` | Mocked execution produced rows. | Consume rows. |
| `empty` | Mocked execution completed with no matching rows. | Show empty state / continue. |
| `denied` | StorageCapability gate rejected access. | Do not retry the same plan as-is; fix authority. |
| `query_error` | Plan is malformed or unsupported. | Fix the plan. |
| `system_error` | Mocked execution reports infrastructure-style failure. | Treat as external/system fault. |

`denied` and `query_error` are separate and must not be collapsed. Capability denial is not malformed-plan feedback; malformed plan feedback is not access denial.

### QueryExecutionReceipt as evidence, not authority

`QueryExecutionReceipt` records what was checked and what happened in the proof-local execution path. It is evidence only. It does not re-authorize a later execution and does not create runtime authority.

The stabilized receipt role is:

- record capability gate facts (`cap_checked`, `cap_granted`, `denial_gate`, `deny_reason`);
- record limit facts (`plan_limit`, `row_limit_cap`, `effective_limit`, `row_limit_clamped`);
- record outcome facts (`rows_returned`, `result_kind`);
- preserve source/op/capability identifiers and metadata;
- mirror the final `QueryResult`, after filter/order/limit/projection.

---

## 2. Evidence Chain

| Proof | Role in Query v0 |
|-------|------------------|
| LAB-QUERY-P1 | Research boundary. Established the core formula: Query v0 = typed intent AST + capability boundary + mocked execution. Permanently closed ORM, ActiveRecord compatibility, DB connection, persistence runtime, and migration claims. |
| LAB-QUERY-P2 | Basic `QueryPlan` and KDR proof. Proved query records as pure typed Records, `QueryResult{kind:"denied"}`, Map metadata, C1 map chain, and all-CORE plan building. 42/42 PASS. |
| LAB-QUERY-P3 | Nested records and `Collection[FilterPredicate]`. Proved richer `QueryPlan` shape with `QuerySource`, `Projection`, `OrderBy`, `Collection[FilterPredicate]`, chained field access, and denial-as-data. 44/44 PASS. |
| LAB-STORAGE-CAPABILITY-P1 | StorageCapability design. Locked schema, six gate model, row-limit clamp rule, include_all policy rule, and `QueryExecutionReceipt` shape. No proof runner; design-locked. |
| LAB-STORAGE-CAPABILITY-P2 | StorageCapability gate proof. Proved G1/G2/G3 denial, G4 clamp as non-denial, G5 `query_error`, mocked G6 outcomes, KDR routing, receipt invariants, and no DB/SQL/ORM/persistence. 51/51 PASS. |
| LAB-EXECUTE-QUERY-P1 | First `ExecuteQuery` effect-contract boundary proof. Proved the two-fixture effect/pure separation, capability injection shape, receipt builders, and ESCAPE boundary. 57/57 PASS. |
| LAB-FILTER-EVAL-P1 | Filter evaluation over mocked rows. Proved AND-only v0 filters, eq/neq/contains/prefix, missing field -> empty, bad op -> `query_error`, and in-memory proof-local row evaluation. 50/50 PASS. |
| LAB-QUERY-ORDER-LIMIT-P1 | Single-order and limit semantics. Proved lexicographic asc/desc, stable sort, order-then-limit, zero limit -> empty, negative limit -> `query_error`, and separation from StorageCapability row_limit. 54/54 PASS. |
| LAB-EXECUTE-QUERY-P2 | First integrated mocked pipeline. Proved gates + filter + order + limit + receipt in one proof-local simulator; confirmed gate short-circuit and `query_error != denied`. 73/73 PASS. |
| LAB-QUERY-MULTI-ORDER-P1 | Multi-column order. Proved `Collection[OrderBy]`, stable priority ordering, per-key asc/desc, empty order list no-op, malformed order -> `query_error`, and proof-local-only runtime. 64/64 PASS. |
| LAB-QUERY-PROJECTION-P1 | Projection semantics. Proved `Projection{fields:String,include_all:Bool}`, field parsing, include_all identity projection, missing/empty fields -> `query_error`, de-duplication, projection final step, and row-count invariant. 62/62 PASS. |
| LAB-EXECUTE-QUERY-P3 | Unified v0 pipeline. Proved complete order: G1 -> G2 -> G3 -> G4 -> G5 -> filter -> multi-order -> limit -> projection -> receipt. Confirmed receipt mirrors final result facts. 68/68 PASS. |
| LAB-TC-ARRAY-P1 | Array literal support for typed `Collection[T]` contexts. Closed the Rust TC array-literal gap needed for inline filter/order collections. 27/27 PASS. |
| LAB-TC-ARRAY-P2 | Record-field `Collection[T]` context propagation. Confirmed `BuildUnifiedPlan.filters:Collection[FilterPredicate]` and repeated collection typing through Query proofs. 19/19 PASS. |
| LAB-TC-NESTED-RECORD-CONTEXT-P1 | Nested record literal context support. Closed the Projection B9 gap for natural inline nested records in Rust TC; no query semantics change. 42/42 PASS. |

Evidence status: sufficient to stabilize Query v0 as a lab evidence boundary. Not sufficient to claim canon authority, public API stability, or real IO execution.

---

## 3. Stable v0 Semantics

| Semantics | Stabilized rule |
|-----------|-----------------|
| Plan building | Pure CORE. QueryPlan construction has no capability and no IO authority. |
| Execution boundary | Effect/capability-shaped. Real execution remains outside v0; mocked execution is proof-local. |
| Capability denial | Returns `QueryResult{kind:"denied"}`. No exception/raise path. |
| Malformed plan | Returns `QueryResult{kind:"query_error"}`. This includes bad filter op, bad order direction, negative limit, empty projection fields, and missing projected field. |
| Denied vs query_error | Separate recovery axes. Do not collapse. |
| `row_limit` | Clamps `effective_limit`; does not deny. Receipt records `row_limit_clamped:true`. |
| `include_all` policy | If capability disallows include_all, result is `query_error`, not `denied`. |
| Pipeline order | Gates first; then filter; then multi-order; then limit; then projection; then receipt. |
| Projection | Happens after filter/order/limit. It shapes columns only and does not change row count. |
| Gate short-circuit | G1/G2/G3 denial stops before filter/order/limit/projection. |
| Receipt | Records gates and result facts only. It is evidence, not authority. |

---

## 4. Closed Surfaces

The following are explicitly closed by Query v0 stabilization:

| Surface | Status |
|---------|--------|
| SQL execution | CLOSED |
| SQL SELECT generation as stable surface | CLOSED |
| Database connection | CLOSED |
| ORM compatibility claim | CLOSED |
| ActiveRecord compatibility claim | CLOSED |
| Arel compatibility claim | CLOSED |
| Persistence runtime | CLOSED |
| Migrations | CLOSED |
| Transactions | CLOSED |
| Joins | CLOSED in v0 |
| Aggregates | CLOSED in v0 |
| Writes | CLOSED |
| Query optimizer | CLOSED |
| Index hints / index-backed semantics | CLOSED |
| Public/stable API | CLOSED |
| Production unified query runtime | CLOSED |
| StorageCapability live execution authority | CLOSED |
| Canon language change | CLOSED by this packet |

---

## 5. Known v0 Limits

| Limit | Current v0 position |
|-------|---------------------|
| Rows | Mocked rows only. |
| Row value typing | Stringly row values: `Map[String,String]`. |
| Typed rows | No typed `Row[T]`. |
| Joins | None. Single-source only. |
| Aggregates | None. |
| Writes | None. Read-shaped only. |
| Predicate language | Limited: AND-only in proof-local filter evaluation; no OR/NOT; no typed value operators. |
| Ordering | Lexicographic String ordering only; numeric/date/locale/collation authority absent. |
| Projection field list | `fields:String`, comma-split in v0; no `Collection[String]` grammar/public surface. |
| DB adapter | None. |
| Runtime authority | None. Mocked simulators are proof-local only. |
| Ruby/Rust divergence | Rust TC has the stabilized array and nested-record fixes. Ruby TC nested-record-literal parity remains documented as a separate divergence where relevant; it does not change the Query v0 semantics boundary. |

---

## 6. Boundary with IO

Query v0 is ready to hand off into IO research because it now defines the intent and receipt side of the boundary.

Query owns:

- typed intent data (`QueryPlan`, `QuerySource`, `Projection`, `FilterPredicate`, `OrderBy`);
- query-domain outcome data (`QueryResult`);
- proof-local execution semantics over mocked rows;
- receipt facts (`QueryExecutionReceipt`) that describe gates and outcomes.

IO owns:

- adapter/substrate authority;
- live capability injection;
- real storage execution;
- connection/session lifecycle;
- substrate-specific safety and failure behavior.

Storage IO should not be silently equated with Network/File/Clock IO. Storage has table/source authority, read/write split, row-limit clamp, projection policy, adapter semantics, and persistence-specific failure modes. Those must be researched as an IO family/substrate problem, not smuggled in through Query v0.

Real execution therefore requires a separate IO boundary and capability adapter proof. Query v0 gives IO a stable intent/receipt contract to reason about; it does not implement IO.

---

## 7. Recommended Next Route

### Primary

`LAB-IO-BOUNDARY-P1` - IO family taxonomy and substrate readiness

Purpose:

- classify IO families without collapsing Storage into Network/File/Clock;
- define what "substrate readiness" means for each family;
- decide what a Storage adapter must prove before any real execution path opens;
- keep Query v0 intent/receipt evidence separate from IO authority.

### Optional later

| Route | When to open |
|-------|--------------|
| `LAB-STORAGE-ADAPTER-P1` - mocked adapter contract hardening | After IO taxonomy identifies the storage adapter contract shape. |
| StorageCapability PROP | Only if governance decides grammar/public surface is needed. This packet does not authorize it. |

---

## Decision

Query v0 is stabilized as a lab evidence boundary:

- concise enough to route future work;
- complete enough to stop feature-first expansion;
- explicit enough to prevent accidental DB/ORM/API authority claims;
- ready to hand off to IO boundary research.

No code changes were made by this packet. No proof runner was required.
