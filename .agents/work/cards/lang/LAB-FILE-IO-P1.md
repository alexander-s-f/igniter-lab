# LAB-FILE-IO-P1 - File/Text Capability Shape and Mocked Read Snapshot Proof

**Card:** LAB-FILE-IO-P1
**Track:** file-text-io-capability-and-mocked-read-snapshot-boundary-v0
**Status:** CLOSED - PROOF COMPLETE (78/78)
**Route:** LAB PROOF / FILE IO MOCK BOUNDARY / NO REAL FILE WRITES
**Authority:** lab-only evidence
**Date:** 2026-06-10

## Goal

Prove a proof-local File/Text IO boundary for mocked reads:

`FileCapability-shaped record + FileReadRequest + explicit MockFileRegistry`
`-> FileReadResult + FileReadReceipt`

This card does not open real filesystem reads or writes.

## Decision

File IO is not Storage IO. File IO authority is path/root/encoding/size/symlink
and traversal oriented, not table/source/query-plan oriented.

The P1 mock registry is explicit fixture data. Receipts are evidence only and
do not re-authorize file access.

## Delivered

| Artifact | Path | Status |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/file_io/file_text_mocked_read_snapshot.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_file_io_p1.rb` | DONE - 78/78 PASS |
| Lab doc | `lab-docs/lang/lab-file-text-capability-mocked-read-snapshot-proof-v0.md` | DONE |
| Portfolio update | `.agents/portfolio-index.md` | DONE |

## Proof Results

| Section | Checks |
|---|---:|
| FILEIO-COMPILE | 8/8 |
| FILEIO-SHAPE | 8/8 |
| FILEIO-GATES | 12/12 |
| FILEIO-RESULT | 10/10 |
| FILEIO-RECEIPT | 9/9 |
| FILEIO-DETERMINISM | 8/8 |
| FILEIO-TAXONOMY | 8/8 |
| FILEIO-VM | 5/5 |
| FILEIO-CLOSED | 10/10 |

Total: **78/78 PASS**.

## Explicit Answers

1. File/Text IO boundary distinct from Storage IO? YES.
2. Mock snapshot registry explicit fixture data? YES.
3. Real filesystem read/write opened? NO.
4. Denied vs not_found vs size_error vs decode_error separated? YES.
5. Receipt mirrors result facts? YES.
6. Receipt re-authorizes file access? NO.
7. Repeated mocked reads deterministic? YES.
8. `unknown_external_state` used? NO.
9. `partial_success` used for single-file read? NO.

## Gate Coverage

- G1 root allowlist failure -> `denied`
- G2 op allowlist failure -> `denied`
- G2 `read_allowed=false` -> `denied`
- G3 parent traversal disallowed -> `denied`
- G4 symlink disallowed -> `denied`
- G5 missing / `exists=false` snapshot -> `not_found`
- G6 byte length over `max_bytes` -> `size_error`
- G7 requested encoding disallowed -> `denied`
- G7 snapshot encoding mismatch / invalid decode -> `decode_error`
- G8 all gates pass -> `content`

## Taxonomy Alignment

- `denied` != `not_found`
- `denied` != `size_error`
- `denied` != `decode_error`
- `not_found` is not `system_error`
- `size_error` is policy/data-bound, not capability denial
- `decode_error` is observed encoding/content failure, not capability denial
- no `unknown_external_state` in mocked read P1
- no `partial_success` in single-file read P1

## Closed Surfaces

- no real filesystem reads
- no real filesystem writes
- no directory listing
- no symlink following
- no parent traversal
- no ambient cwd
- no OS permission claim
- no parser/compiler/VM changes
- no public/stable File API
- no canon `IO.FileCapability` schema authority

## Next Route

Recommended next File IO route:

**LAB-FILE-IO-P2 - mocked write attempt / atomicity boundary**

Parallel IO routes:
- **LAB-CLOCK-P1**
- **LAB-HOST-IPC-P1**

Real filesystem reads/writes remain **HOLD**.
