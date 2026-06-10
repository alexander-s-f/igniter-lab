# LAB-STORAGE-ADAPTER-P1 - Mocked Storage Adapter Contract Hardening

**Card:** LAB-STORAGE-ADAPTER-P1
**Track:** storage-io-mocked-adapter-contract-hardening-v0
**Status:** CLOSED - PROOF COMPLETE (80/80)
**Route:** LAB PROOF / STORAGE IO MOCK ADAPTER / NO REAL DB
**Authority:** lab-only evidence
**Date:** 2026-06-10

## Goal

Harden the Storage IO adapter boundary with a proof-local mocked adapter
contract. The adapter consumes Query v0 intent, StorageCapability-shaped policy,
and explicit mock source fixture data, then produces `QueryResult`,
`QueryExecutionReceipt`, and a small `StorageAdapterReceipt`.

## Decision

`StorageAdapterMock` is not the Query v0 simulator. It wraps the already
stabilized Query v0 semantics with:
- mocked source registry selection
- adapter/source metadata
- request_id and execution_id
- fixture digest evidence
- no-ambient-state evidence

Query v0 semantics remain unchanged:

```text
G1/G2/G3/G4/G5 -> filter -> multi-order -> limit -> projection -> receipt
```

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/storage_adapter/storage_adapter_mocked.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_storage_adapter_p1.rb` | DONE - 80/80 PASS |
| Lab doc | `lab-docs/lang/lab-storage-mocked-adapter-contract-hardening-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

## Proof Results

| Section | Checks |
|---|---:|
| SADAPT-COMPILE | 6/6 |
| SADAPT-SHAPE | 9/9 |
| SADAPT-BOUNDARY | 8/8 |
| SADAPT-GATES | 8/8 |
| SADAPT-PIPELINE | 8/8 |
| SADAPT-ERRORS | 9/9 |
| SADAPT-RECEIPT | 8/8 |
| SADAPT-DETERMINISM | 6/6 |
| SADAPT-VM | 5/5 |
| SADAPT-CLOSED | 13/13 |

Total: **80/80 PASS**.

## Explicit Answers

1. Adapter boundary explicit? YES - `StorageAdapterRequest` and `StorageAdapterReceipt` model the boundary.
2. Query v0 semantics reused, not redefined? YES - proof reuses filter -> multi-order -> limit -> projection semantics.
3. Source not allowed? `denied`.
4. Source allowed but missing from mock registry? `system_error`.
5. Bad filter/order/projection/limit/include_all? `query_error`.
6. Row-limit clamp? `rows`/`empty` with `row_limit_clamped:true`, not denied.
7. Empty result? `QueryResult{kind:"empty"}`.
8. Deterministic replay? YES - repeated runs and canonical output digest match.
9. Ambient host state? NO - rows are explicit fixture data and adapter receipt records `ambient_state_used:false`.
10. Real DB/SQL/ORM? CLOSED.

## Finding: Missing Mock Source

The proof chooses `system_error` for an allowed source missing from the mock
registry. The QueryPlan can be well-formed and the capability can grant access;
the failure is that the adapter substrate fixture is absent. Treating this as
`empty` would hide an adapter setup error, and treating it as `query_error`
would incorrectly blame the query plan.

## Closed Surfaces

- no real database
- no SQL execution or generation
- no ORM / ActiveRecord / Arel compatibility
- no migrations
- no transactions
- no writes
- no joins
- no aggregates
- no query optimizer
- no public/stable API
- no parser/compiler/VM changes
- no StorageCapability canon authority

## Next Route

Recommended next storage route:

**LAB-STORAGE-ADAPTER-P2 - adapter receipt / replay hardening**

Parallel IO family routes:
- **LAB-FILE-IO-P1**
- **LAB-HOST-IPC-P1**

Real storage adapter / real DB remains **HOLD**.
