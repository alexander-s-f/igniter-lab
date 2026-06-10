# LAB-STORAGE-ADAPTER-P2
## Adapter Receipt Replay and Tamper Hardening - v0

**Track:** storage-io-mocked-adapter-receipt-replay-hardening-v0
**Status:** CLOSED - PROOF COMPLETE (89/89)
**Route:** LAB PROOF / STORAGE IO MOCK ADAPTER / RECEIPT HARDENING
**Date:** 2026-06-10
**Authority:** lab-only evidence

## Core Thesis

A storage adapter receipt is evidence, not authority. Replay must verify the
receipt against the original request, capability, mock source fixture, and
result path. It must not trust receipt fields blindly and must not re-authorize
execution from a receipt alone.

## Files

| Layer | Path | Purpose |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/storage_adapter/storage_adapter_replay.ig` | Type-shape evidence for replay result and digest bundle records |
| Proof runner | `igniter-view-engine/proofs/verify_lab_storage_adapter_p2.rb` | 89 checks across 10 sections |
| Lab doc | `lab-docs/lang/lab-storage-adapter-receipt-replay-hardening-v0.md` | This file |
| Agent card | `.agents/work/cards/lang/LAB-STORAGE-ADAPTER-P2.md` | Work card |
| Portfolio | `.agents/portfolio-index.md` | Index entry |

## Replay Model

Replay input:
- original `StorageAdapterRequest` materialized as request data
- `QueryResult`
- `QueryExecutionReceipt`
- `StorageAdapterReceipt`
- `MockStorageSource` fixture data
- replay schema/version context

Replay output:
- `StorageAdapterReplayResult`
- stable digest bundle

Replay verifier behavior:
- recomputes the adapter result from request + capability + fixture rows
- recomputes canonical JSON digests
- compares `QueryResult`, `QueryExecutionReceipt`, and `StorageAdapterReceipt`
- rejects tamper and drift with explicit KDR reasons
- fails closed when the original request or fixture is missing
- never treats a receipt as capability authority

## Digest Bundle

P2 derives stable proof-local digests for:
- `request_digest`
- `plan_digest`
- `capability_digest`
- `fixture_digest`
- `query_result_digest`
- `query_execution_receipt_digest`
- `adapter_receipt_digest`
- `replay_bundle_digest`

All digests use deterministic canonical JSON ordering in the proof code. Field
ordering is explicitly proved not to change the digest.

## Replay Result KDR

`StorageAdapterReplayResult` has:
- `kind`
- `reason`
- `request_id`
- `execution_id`
- `verified`
- `metadata`

P2 proves these `kind` values:
- `replay_ok`
- `tampered`
- `fixture_drift`
- `capability_drift`
- `plan_drift`
- `version_mismatch`
- `insufficient_evidence`

## Proof Results

| Section | Checks | Purpose |
|---|---:|---|
| SADAPT2-COMPILE | 6 | Replay fixture compiles and typechecks |
| SADAPT2-SHAPE | 8 | Replay result, digest bundle, and context shapes |
| SADAPT2-DIGEST | 9 | Canonical digest construction and field-order stability |
| SADAPT2-REPLAY | 8 | Same request + same fixture verifies as `replay_ok` |
| SADAPT2-TAMPER | 13 | Result/receipt/digest tamper rejected |
| SADAPT2-DRIFT | 7 | Fixture, capability, plan, and adapter version drift classified |
| SADAPT2-RESULT | 7 | Replay result KDR shape and vocabulary |
| SADAPT2-DETERMINISM | 8 | Stable replay result/digest; no ambient state |
| SADAPT2-VM | 5 | Pure replay types VM-execute as boundary artifacts |
| SADAPT2-AUTHORITY | 8 | Receipts remain evidence, not authority |
| SADAPT2-CLOSED | 10 | No real IO or stable API |

Total: **89/89 PASS**.

## Tamper Coverage

P2 rejects:
- `QueryResult.kind` tamper
- `rows_returned` tamper
- `effective_limit` tamper
- `row_limit_clamped` tamper
- `denial_gate` tamper
- `source_table` tamper
- `fixture_digest` tamper
- `mocked_source_id` tamper
- `ambient_state_used` tamper
- `request_id` tamper
- `execution_id` tamper
- `replay_bundle_digest` tamper

Every tamper case returns `kind:"tampered"` and `verified:false`.

## Drift Coverage

P2 classifies:
- same request + same fixture -> `replay_ok`
- changed fixture rows -> `fixture_drift`
- changed capability -> `capability_drift`
- changed plan -> `plan_drift`
- changed adapter code version / adapter id -> `version_mismatch`
- receipt-only replay -> `insufficient_evidence`

## Authority Boundary

`QueryExecutionReceipt` and `StorageAdapterReceipt` remain evidence records.
They do not carry `allowed_sources`, `allowed_ops`, `read_allowed`,
`write_allowed`, row-limit authority, or source fixture authority.

The verifier requires the original request and source fixture. Receipt-only
replay fails with `insufficient_evidence`; it never re-authorizes storage
execution.

## Closed Surfaces

This card does not authorize:
- real database execution
- SQL execution or SQL generation
- ORM / ActiveRecord / Arel compatibility
- writes
- joins
- aggregates
- query optimizer
- parser/compiler/VM changes
- public/stable receipt API
- canon claim
- real storage adapter

## Next Route

Recommended next storage route:

**LAB-STORAGE-ADAPTER-P3 - adapter versioning / schema evolution**

Parallel IO family routes remain available:
- **LAB-FILE-IO-P1**
- **LAB-HOST-IPC-P1**

Real storage adapter remains **HOLD** until real-substrate readiness is
separately designed.
