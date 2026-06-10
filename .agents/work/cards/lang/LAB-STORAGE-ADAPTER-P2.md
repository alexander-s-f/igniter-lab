# LAB-STORAGE-ADAPTER-P2 - Adapter Receipt Replay and Tamper Hardening

**Card:** LAB-STORAGE-ADAPTER-P2
**Track:** storage-io-mocked-adapter-receipt-replay-hardening-v0
**Status:** CLOSED - PROOF COMPLETE (89/89)
**Route:** LAB PROOF / STORAGE IO MOCK ADAPTER / RECEIPT HARDENING
**Authority:** lab-only evidence
**Date:** 2026-06-10

## Goal

Harden mocked Storage adapter receipt replay before any real storage adapter
work can be considered.

## Decision

Receipts are evidence, not authority. The P2 replay verifier recomputes the
mocked adapter result from the original request, capability, and fixture rows;
then it compares `QueryResult`, `QueryExecutionReceipt`,
`StorageAdapterReceipt`, and canonical digests.

Receipt-only replay fails with `insufficient_evidence`.

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/storage_adapter/storage_adapter_replay.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_storage_adapter_p2.rb` | DONE - 89/89 PASS |
| Lab doc | `lab-docs/lang/lab-storage-adapter-receipt-replay-hardening-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

## Proof Results

| Section | Checks |
|---|---:|
| SADAPT2-COMPILE | 6/6 |
| SADAPT2-SHAPE | 8/8 |
| SADAPT2-DIGEST | 9/9 |
| SADAPT2-REPLAY | 8/8 |
| SADAPT2-TAMPER | 13/13 |
| SADAPT2-DRIFT | 7/7 |
| SADAPT2-RESULT | 7/7 |
| SADAPT2-DETERMINISM | 8/8 |
| SADAPT2-VM | 5/5 |
| SADAPT2-AUTHORITY | 8/8 |
| SADAPT2-CLOSED | 10/10 |

Total: **89/89 PASS**.

## Explicit Answers

1. Replay verifier rejects tampered receipts? YES.
2. Replay verifier detects fixture/capability/plan drift? YES.
3. Receipt-only replay fails? YES - `insufficient_evidence`.
4. Same input replay is deterministic? YES.
5. Field ordering changes digest? NO - canonical JSON ordering is stable.
6. Receipt re-authorizes storage execution? NO.
7. Real IO opened? NO.

## Tamper / Drift Coverage

Tamper rejected:
- `QueryResult.kind`
- `rows_returned`
- `effective_limit`
- `row_limit_clamped`
- `denial_gate`
- `source_table`
- `fixture_digest`
- `mocked_source_id`
- `ambient_state_used`
- `request_id`
- `execution_id`
- `replay_bundle_digest`

Drift classified:
- same request + same fixture -> `replay_ok`
- changed fixture -> `fixture_drift`
- changed capability -> `capability_drift`
- changed plan -> `plan_drift`
- changed adapter code version / adapter id -> `version_mismatch`
- receipt-only replay -> `insufficient_evidence`

## Closed Surfaces

- no real database
- no SQL execution or generation
- no ORM / ActiveRecord / Arel compatibility
- no writes
- no joins
- no aggregates
- no optimizer
- no parser/compiler/VM changes
- no public/stable receipt API
- no canon claim
- no real storage adapter

## Next Route

Recommended next storage route:

**LAB-STORAGE-ADAPTER-P3 - adapter versioning / schema evolution**

Parallel IO family routes:
- **LAB-FILE-IO-P1**
- **LAB-HOST-IPC-P1**

Real storage adapter remains **HOLD**.
