# LAB-FILE-IO-P1
## File/Text Capability Shape and Mocked Read Snapshot Proof - v0

**Track:** file-text-io-capability-and-mocked-read-snapshot-boundary-v0
**Status:** CLOSED - PROOF COMPLETE (78/78)
**Route:** LAB PROOF / FILE IO MOCK BOUNDARY / NO REAL FILE WRITES
**Date:** 2026-06-10
**Authority:** lab-only evidence

## Core Thesis

File/Text IO is not Storage IO. Storage authority is source/table/query-plan
oriented; File/Text authority is root/path/encoding/size/symlink/traversal
oriented.

P1 proves a proof-local mocked read boundary:

`FileReadRequest + FileCapability-shaped record + explicit MockFileRegistry`
`-> FileReadResult + FileReadReceipt`

The mock registry is explicit fixture data. It is not ambient host filesystem
state, not current working directory authority, and not a real file adapter.

## Files

| Layer | Path | Purpose |
|---|---|---|
| Fixture | `igniter-view-engine/fixtures/file_io/file_text_mocked_read_snapshot.ig` | Type-shape evidence for capability, request, snapshot, result, and receipt records |
| Proof runner | `igniter-view-engine/proofs/verify_lab_file_io_p1.rb` | 78 checks across 9 sections |
| Lab doc | `lab-docs/lang/lab-file-text-capability-mocked-read-snapshot-proof-v0.md` | This file |
| Agent card | `.agents/work/cards/lang/LAB-FILE-IO-P1.md` | Work card |
| Portfolio | `.agents/portfolio-index.md` | Index entry |

## Model

P1 models:
- `FileCapability`
- `FileReadRequest`
- `MockFileSnapshot`
- `MockFileRegistry`
- `FileReadResult`
- `FileReadReceipt`

The capability shape includes:
- root allowlist
- operation allowlist
- read/write flags
- byte-size limit
- encoding allowlist
- symlink policy
- parent-traversal policy
- denial reason and metadata

The receipt records:
- request and capability ids
- requested and normalized path
- gate facts
- requested and observed encoding
- bytes read
- maximum allowed bytes
- content digest
- snapshot / fixture facts
- symlink and traversal observations
- result kind
- ambient-state marker

Receipts remain evidence, not authority. They do not grant future path access
and do not authorize replay against a host filesystem.

## Result Vocabulary

P1 proves these `FileReadResult.kind` values:
- `content`
- `not_found`
- `denied`
- `file_error`
- `decode_error`
- `size_error`

The proof uses `decode_error` for encoding mismatch or invalid mocked decode
evidence. `file_error` is reserved in the type vocabulary for future
file-family failures, but P1 does not require it for the required cases.

## Gate Semantics

| Gate | Rule | Result |
|---|---|---|
| G1 | request root not in `allowed_roots` | `denied` |
| G2 | op not in `allowed_ops` or read not allowed | `denied` |
| G3 | parent traversal detected while disallowed | `denied` |
| G4 | symlink snapshot encountered while disallowed | `denied` |
| G5 | snapshot missing or `exists=false` | `not_found` |
| G6 | snapshot byte length exceeds `max_bytes` | `size_error` |
| G7 | requested encoding disallowed | `denied` |
| G7 | snapshot encoding mismatch or invalid decode | `decode_error` |
| G8 | all gates pass | `content` |

## Proof Results

| Section | Checks | Purpose |
|---|---:|---|
| FILEIO-COMPILE | 8 | Fixture compiles, typechecks, and emits contracts |
| FILEIO-SHAPE | 8 | Capability/request/snapshot/result/receipt field types |
| FILEIO-GATES | 12 | Required gate and failure behavior |
| FILEIO-RESULT | 10 | KDR vocabulary and result data |
| FILEIO-RECEIPT | 9 | Receipt mirrors result facts and remains evidence |
| FILEIO-DETERMINISM | 8 | Stable repeated reads and canonical digests |
| FILEIO-TAXONOMY | 8 | PROP-047 alignment |
| FILEIO-VM | 5 | Pure shape contracts VM-execute |
| FILEIO-CLOSED | 10 | Closed authority surfaces stay closed |

Total: **78/78 PASS**.

## Required Cases Covered

P1 proves:
- happy path content read
- root denied
- op denied
- `read_allowed=false` denied
- parent traversal denied
- symlink denied
- missing file -> `not_found`
- `exists=false` snapshot -> `not_found`
- oversized file -> `size_error`
- disallowed requested encoding -> `denied`
- encoding mismatch -> `decode_error`
- invalid decode -> `decode_error`
- empty file -> `content`, not `not_found`
- stable content digest
- deterministic repeated read
- receipt mirrors `result_kind` and `bytes_read`
- mock registry declares `ambient_state_used=false`

## Failure Taxonomy Alignment

P1 aligns with PROP-047 by keeping these distinctions explicit:
- `denied` != `not_found`
- `denied` != `size_error`
- `denied` != `decode_error`
- `not_found` is not `system_error`
- `size_error` is policy/data-bound failure, not capability denial
- `decode_error` is observed content/encoding failure, not capability denial
- mocked read has no `unknown_external_state`
- single-file read P1 has no `partial_success`

## Authority Boundary

`FileReadReceipt` is evidence only. It records the gate and snapshot facts for
the mocked read. It does not contain root allowlist authority, write authority,
OS permission authority, or a host file handle.

`MockFileRegistry` is explicit fixture data. The mocked adapter does not read
from the host filesystem, does not list directories, does not follow symlinks,
and does not use ambient cwd.

## Closed Surfaces

This card does not authorize:
- real filesystem reads
- real filesystem writes
- directory listing
- symlink following
- parent traversal
- ambient cwd
- OS permission claims
- parser/compiler/VM changes
- public/stable File API
- canon `IO.FileCapability` schema authority

## Next Route

Recommended next File IO route:

**LAB-FILE-IO-P2 - mocked write attempt / atomicity boundary**

Parallel IO family routes remain available:
- **LAB-CLOCK-P1 - deterministic clock observation boundary**
- **LAB-HOST-IPC-P1 - host dispatch seam and mocked IPC receipt boundary**

File/Text real filesystem reads/writes remain **HOLD** until real-substrate
readiness is separately designed.
