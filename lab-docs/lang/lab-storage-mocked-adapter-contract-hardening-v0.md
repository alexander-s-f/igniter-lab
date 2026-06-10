# LAB-STORAGE-ADAPTER-P1
## Mocked Storage Adapter Contract Hardening - v0

**Track:** storage-io-mocked-adapter-contract-hardening-v0
**Status:** CLOSED - PROOF COMPLETE (80/80)
**Route:** LAB PROOF / STORAGE IO MOCK ADAPTER / NO REAL DB
**Date:** 2026-06-10
**Authority:** lab-only evidence

## Core Formula

```text
StorageAdapterMock v0
  = QueryPlanUnified
  + StorageCapability-shaped record
  + explicit MockStorageSource fixture data
  + request/execution metadata
  -> QueryResult
  + QueryExecutionReceipt
  + StorageAdapterReceipt
```

This card introduces an explicit mocked adapter boundary around the already
stabilized Query v0 semantics. It does not redefine Query v0. It wraps source
registry selection, adapter/substrate metadata, deterministic mocked fixture
data, and replay evidence around the existing gate and row pipeline.

## Files

| Layer | Path | Purpose |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/storage_adapter/storage_adapter_mocked.ig` | Type-shape evidence for adapter input/output records |
| Proof runner | `igniter-view-engine/proofs/verify_lab_storage_adapter_p1.rb` | 80 checks across 10 sections |
| Lab doc | `lab-docs/lang/lab-storage-mocked-adapter-contract-hardening-v0.md` | This file |
| Agent card | `.agents/work/cards/lang/LAB-STORAGE-ADAPTER-P1.md` | Work card |
| Portfolio | `.agents/portfolio-index.md` | Index entry |

## Model

Adapter input:
- `QueryPlanUnified`
- `StorageCapability` record shaped like `IO.StorageCapability`
- `MockStorageSource`
- explicit fixture rows under `MockStorageSource.tables`
- `request_id`
- `execution_id`

Adapter output:
- `QueryResult`
- `QueryExecutionReceipt` - the existing 15-field Query v0 receipt
- `StorageAdapterReceipt` - adapter boundary facts only

`StorageAdapterReceipt` is intentionally small. It records `adapter_id`,
`mocked_source_id`, `request_id`, `execution_id`, `substrate_kind`,
`fixture_digest`, `source_table`, `result_kind`, and `ambient_state_used`.
It does not duplicate capability gate fields such as `cap_checked`,
`cap_granted`, `denial_gate`, `effective_limit`, or `rows_returned`.

## Pipeline

```text
1. G1 source allowlist        -> denied
2. G2 op allowlist            -> denied
3. G3 read_allowed            -> denied
4. mock registry lookup       -> system_error if allowed source fixture missing
5. G4 row_limit clamp         -> rows/empty, not denied
6. G5 include_all policy      -> query_error
7. filter                     -> rows/empty/query_error
8. multi-order                -> rows/query_error
9. limit                      -> rows/empty/query_error
10. projection                -> rows/empty/query_error
11. receipts                  -> QueryExecutionReceipt + StorageAdapterReceipt
```

The proof keeps G1 before registry lookup so a denied caller does not learn
whether a source exists in the mocked registry. If a source is allowed by
capability but missing from the mocked registry, the result is `system_error`.
That is an adapter substrate fixture failure, not an empty table and not a
malformed query plan.

## Proof Results

| Section | Checks | Purpose |
|---|---:|---|
| SADAPT-COMPILE | 6 | Rust compiler and Ruby TypeChecker accept the fixture; 9 pure contracts |
| SADAPT-SHAPE | 9 | QueryPlan, capability, mock source, request, and receipt type shapes |
| SADAPT-BOUNDARY | 8 | Adapter wraps source selection; QueryPlan remains intent data |
| SADAPT-GATES | 8 | G1/G2/G3 denial, G4 clamp, G5 query_error, registry system_error |
| SADAPT-PIPELINE | 8 | Reused Query v0 filter -> multi-order -> limit -> projection semantics |
| SADAPT-ERRORS | 9 | denied/query_error/system_error separation |
| SADAPT-RECEIPT | 8 | Query receipt plus adapter receipt facts |
| SADAPT-DETERMINISM | 6 | Stable replay digest, explicit rows, no mutation, no ambient state |
| SADAPT-VM | 5 | Pure fixture contracts VM-execute as typed boundary artifacts |
| SADAPT-CLOSED | 13 | No real IO or implementation authority |

Total: **80/80 PASS**.

## Key Findings

### Adapter vs Query v0

The adapter does not change Query v0 semantics. The proof reuses:

```text
filter -> multi-order -> limit -> projection
```

The adapter adds only source registry lookup, explicit mocked source fixture
data, request/execution metadata, adapter receipt facts, and no-ambient-state
evidence.

### Failure Taxonomy

The proof aligns with PROP-047:
- `denied` is capability denial at G1/G2/G3.
- `query_error` is malformed plan or policy violation after capability checks.
- `system_error` is adapter substrate failure, such as an allowed source missing from the mocked registry.
- `row_limit` clamp is not denial.
- missing mocked source is never silently treated as empty rows.
- `unknown_external_state` never appears because the mocked adapter performs no external side effect.

### Determinism

Repeated adapter runs with identical inputs produce identical result and receipt
data. The proof also computes a canonical digest over the adapter output and
proves it is stable. Mocked source rows are explicit fixture data; no host
database, filesystem storage, network, process, clock, or random source is used
as storage substrate.

## Closed Surfaces

This card does not authorize:
- real database execution
- SQL execution or SQL generation
- ORM / ActiveRecord / Arel compatibility
- migrations
- transactions
- writes
- joins
- aggregates
- query optimizer
- public/stable API
- parser/compiler/VM changes
- StorageCapability canon authority beyond existing proposal/lab evidence

## Next Route

Recommended next storage route:

**LAB-STORAGE-ADAPTER-P2 - adapter receipt / replay hardening**

P2 should harden receipt/replay details, tamper checks, fixture digest
requirements, and adapter result reproducibility without opening real storage.

Parallel IO family routes remain available:
- **LAB-FILE-IO-P1**
- **LAB-HOST-IPC-P1**

Real storage adapter / real DB remains **HOLD** until stricter readiness gaps
close.
