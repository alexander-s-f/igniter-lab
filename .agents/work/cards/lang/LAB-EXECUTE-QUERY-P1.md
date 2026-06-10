# LAB-EXECUTE-QUERY-P1

**Card:** LAB-EXECUTE-QUERY-P1
**Track:** lab-execute-query-effect-contract-and-storage-capability-injection-v0
**Status:** CLOSED — PROOF COMPLETE (57/57)
**Route:** LAB PROOF / STAGE 2+ / MOCKED STORAGE EXECUTION / NO REAL DB
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Prove the first executable Stage 2+ query path: an `ExecuteQuery` effect contract
receives a `QueryPlan` plus an `IO.StorageCapability`-shaped authority object,
applies the LAB-STORAGE-CAPABILITY-P2 gate sequence, and returns a typed
`QueryResult` + `QueryExecutionReceipt` using mocked storage data only.

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44); chained field access |
| LAB-STORAGE-CAPABILITY-P1 | IO.StorageCapability schema + 6-gate design |
| LAB-STORAGE-CAPABILITY-P2 | Gate receipts proof (51/51); two-fixture architecture |
| LAB-TC-ARRAY-P2 | Collection[FilterPredicate] record-field-context (19/19) |
| PROP-035 | `capability`/`effect_binding` grammar (experiment-pass) |
| PROP-046-P1 | IO.StorageCapability boundary proposal (authored) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Capability fixture | `igniter-view-engine/fixtures/query_execution/execute_query_capability.ig` | DONE |
| Receipts fixture | `igniter-view-engine/fixtures/query_execution/execute_query_receipts.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_execute_query_p1.rb` | DONE (57/57) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-execute-query-effect-contract-and-storage-capability-injection-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |



---

## Proof results (57/57)

| Section | n | Checks |
|---------|---|--------|
| EXECQ-COMPILE  | 5  | Rust compiler accepts both fixtures (5+12 contracts); Ruby TC 5/5 accepted (zero type_errors) |
| EXECQ-SHAPE    | 8  | QueryExecutionReceipt (cap_id, cap_granted, denial_gate, effective_limit, row_limit_clamped, result_kind); QueryPlan.filters: Collection[FilterPredicate]; StorageCapability.allowed_sources: Collection[String] |
| EXECQ-GATES    | 6  | Layer C G1–G6; G4 clamp ≠ denial (cap_granted:true when clamped); G5 query_error ≠ denied |
| EXECQ-RECEIPT  | 7  | VM receipt builders; cap_granted:false iff {denied,query_error}; rows_returned:0 when denied |
| EXECQ-VM       | 8  | All 5 KDR result kinds; BuildStorageCapability; BuildQueryPlanInline; clamped receipt |
| EXECQ-MAP      | 4  | QueryMetadataChain hit + miss (or_else); ReadPlanMeta Layer A accepted; output type String |
| EXECQ-ARRAY    | 4  | Rust SIR: BuildQueryPlanInline.filters = Collection[FilterPredicate]; plan = QueryPlan; VM 2-elem |
| EXECQ-COMPOSE  | 5  | plan.source.table → G1; plan.projection.include_all → G5; plan.limit → G4 clamp |
| EXECQ-CLOSED   | 5  | No SQL/DB/ORM/raise/persistence at any layer; ExecuteQuery compile-only (no VM run) |
| EXECQ-GAP      | 5  | ESCAPE gap confirmed; TBackend absent; KDR routing; write ops CLOSED in v0 |

---

## Closed surfaces (permanently in effect)

- Real DB / SQL execution / ORM / ActiveRecord: CLOSED
- StorageCapability live execution: CLOSED (ESCAPE class; Stage 2+ required)
- Transactions / persistence runtime: CLOSED
- Write ops: CLOSED in v0
- TBackend / TEMPORAL: NOT TOUCHED
- Stable / public API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Effect contract passport gap — ExecuteQuery is ESCAPE class; two-fixture architecture is the correct separation (compile-only + VM-executable companion) |
| B2 | BuildQueryPlanInline.filters typed Collection[FilterPredicate] in Rust SIR (LAB-TC-ARRAY-P2 record-field-context confirmed in EXECQ fixture) |
| B3 | `deny_reason` used (not `message` — Ruby parser keyword) |
| B4 | `read_file` used in effect binding (not `read` — Ruby parser keyword) |
| B5 | TBackend / TEMPORAL absent from both fixtures — orthogonality confirmed |

---

## Next authorized

- Stage 2+ live execution: requires PROP-035 Stage 2+ auth + ch4 ExecuteQuery ESCAPE→STORAGE amendment
- Write operations: requires explicit write-execution card + PROP authorization
- LAB-FILTER-EVAL-P1: in-memory predicate evaluation over Collection[FilterPredicate]
