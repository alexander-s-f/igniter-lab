# LAB-QUERY-V0-STABILIZATION-P1 - Query v0 Boundary Stabilization

**Card:** LAB-QUERY-V0-STABILIZATION-P1  
**Track:** query-v0-typed-intent-capability-mocked-execution-stabilization  
**Route:** GOVERNANCE / DESIGN STABILIZATION / NO NEW FEATURE WORK  
**Status:** CLOSED - governance packet authored  
**Authority:** lab_evidence_only  
**Date:** 2026-06-10  
**Skill:** IDD Agent Protocol  
**Category:** governance

---

## Decision

Query v0 is now stabilized as:

```text
typed query intent AST
+ StorageCapability gates
+ deterministic mocked execution
+ QueryResult / QueryExecutionReceipt
+ denial-as-data and query_error separation
```

This is a lab evidence boundary, not canon authority, not a public API, and not a real IO implementation.

---

## Definition

Query v0 includes:

- `QueryPlan` / `QueryPlanUnified` as typed intent data;
- `QuerySource`, `Projection`, `FilterPredicate`, `OrderBy`;
- `QueryResult` as a KDR outcome record with `rows`, `empty`, `denied`, `query_error`, `system_error`;
- `QueryExecutionReceipt` as evidence-only gate/result receipt;
- StorageCapability-shaped gates over mocked execution only.

Plan building is pure CORE. Execution is effect/capability-shaped but proof-local only.

---

## Stable Semantics

| Rule | Stabilized result |
|------|-------------------|
| Capability denial | `QueryResult{kind:"denied"}` |
| Malformed plan | `QueryResult{kind:"query_error"}` |
| `row_limit` | Clamp only; not denial |
| Projection | Final step after filter/order/limit |
| Receipt | Mirrors final result facts; evidence only |
| G1/G2/G3 denial | Short-circuits before filter/order/limit/projection |

`denied` and `query_error` are distinct recovery axes and must not be collapsed.

---

## Evidence Chain

| Proof | Role |
|-------|------|
| LAB-QUERY-P1 | Research boundary; ORM/DB/public API closed |
| LAB-QUERY-P2 | Basic QueryPlan + QueryResult KDR, 42/42 |
| LAB-QUERY-P3 | Nested records + `Collection[FilterPredicate]`, 44/44 |
| LAB-STORAGE-CAPABILITY-P1/P2 | Gate model, receipt shape, denial/query_error/clamp semantics, 51/51 in P2 |
| LAB-EXECUTE-QUERY-P1/P2/P3 | Effect boundary and complete unified mocked pipeline; P3 68/68 |
| LAB-FILTER-EVAL-P1 | Filter semantics over mocked rows, 50/50 |
| LAB-QUERY-ORDER-LIMIT-P1 | Order/limit semantics, 54/54 |
| LAB-QUERY-MULTI-ORDER-P1 | Multi-column order, 64/64 |
| LAB-QUERY-PROJECTION-P1 | Projection/include_all semantics, 62/62 |
| LAB-TC-ARRAY-P1/P2 | Collection typing support, 27/27 + 19/19 |
| LAB-TC-NESTED-RECORD-CONTEXT-P1 | Nested record literal context support, 42/42 |

---

## Closed Surfaces

Explicitly closed:

- SQL execution
- database connection
- ORM / ActiveRecord / Arel compatibility claim
- persistence runtime
- migrations
- transactions
- joins
- aggregates
- writes
- query optimizer
- index hints
- StorageCapability live execution authority
- production unified query runtime
- public/stable API
- canon language change from this packet

---

## Known v0 Limits

- mocked rows only;
- stringly row values / `Map[String,String]`;
- no typed `Row[T]`;
- no joins;
- no aggregates;
- no writes;
- limited predicate language;
- no collation authority;
- no DB adapter;
- Rust TC nested/array support is ahead of Ruby TC nested-record parity where documented.

---

## Boundary With IO

Query v0 defines intent and receipts. IO must define adapter/substrate authority.

Storage IO must not be silently equated with Network/File/Clock IO. Real execution requires a separate IO boundary and capability adapter proof.

---

## Recommended Next Route

Primary:

- `LAB-IO-BOUNDARY-P1` - IO family taxonomy and substrate readiness

Optional later:

- `LAB-STORAGE-ADAPTER-P1` - mocked adapter contract hardening
- StorageCapability PROP only if governance decides grammar/public surface is needed

---

## Deliverables

| Artifact | Path |
|----------|------|
| Governance doc | `igniter-lab/lab-docs/governance/lab-query-v0-boundary-stabilization-v0.md` |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-QUERY-V0-STABILIZATION-P1.md` |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` |

---

## Acceptance

- No code changes.
- No proof runner required.
- Query v0 definition is concise and durable.
- Closed surfaces are explicit.
- Next IO route named without opening real IO implementation.
- Evidence is distinguished from authority.
