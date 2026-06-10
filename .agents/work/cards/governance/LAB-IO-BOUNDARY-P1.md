# LAB-IO-BOUNDARY-P1 — IO Family Taxonomy and Substrate Readiness

**Route:** GOVERNANCE / DESIGN BOUNDARY / NO IMPLEMENTATION  
**Track:** io-family-taxonomy-and-substrate-readiness-boundary-v0  
**Status:** CLOSED — governance packet authored  
**Authority:** lab/governance evidence only

## Purpose

Classify Igniter IO families and define substrate readiness before any real adapter or runtime IO path may open.

This card follows LAB-QUERY-V0-STABILIZATION-P1. Query v0 now defines typed query intent, StorageCapability gates, deterministic mocked execution, `QueryResult`, `QueryExecutionReceipt`, denial-as-data, and `query_error` separation. It does not define real IO authority.

## Decision

IO is not one thing. Storage IO, Network IO, File/Text IO, Clock/Time, Random/Entropy, Process/Command, and UI/Host IPC have different authority holders, capability shapes, deterministic proof modes, receipt requirements, failure vocabularies, replay properties, and security boundaries.

## Delivered

- Governance doc: `lab-docs/governance/lab-io-family-taxonomy-and-substrate-readiness-boundary-v0.md`
- Portfolio update: `.agents/portfolio-index.md`
- This card: `.agents/work/cards/governance/LAB-IO-BOUNDARY-P1.md`

## Evidence Used

- LAB-QUERY-V0-STABILIZATION-P1
- LAB-STORAGE-CAPABILITY-P1/P2
- PROP-046-P1
- LAB-EXECUTE-QUERY-P1/P2/P3 and Query v0 supporting proofs
- LAB-STDLIB-NET-P6/P7/P8/P9
- LAB-FAILURE-TAXONOMY-P1/P2/P3/P4 and PROP-047
- LAB-APP-STATE-P1/P2
- LAB-IGV-TAILMIX-P1
- Canon language covenant rule for opaque `IO.*` names
- Canon Law 6: no ambient time; reads require `TemporalCtx`

## Readiness Outcome

| Family | Decision |
|---|---|
| Storage IO | READY for design-only adapter card and scoped mocked adapter proof; real adapter HOLD |
| Network IO | Mocked boundary evidence strong; real transport HOLD |
| File/Text IO | Needs LAB-FILE-IO-P1 before implementation |
| Clock/Time IO | Needs LAB-CLOCK-P1 before runtime authority |
| Random/Entropy IO | Needs LAB-RANDOM-P1 before runtime authority |
| Process/Command IO | HOLD; command authority threat model required first |
| UI/Host IPC | READY for design/mocked host dispatch proof; Tauri implementation HOLD |

## Substrate Readiness Checklist

Before any real IO adapter opens, the family must have:
- explicit capability/passport shape
- mock proof
- denial-as-data proof
- receipt schema
- deterministic/replay mode
- timeout/unknown-state classification
- no ambient authority
- no hidden host globals
- no public/stable API claim
- PROP-047 failure taxonomy alignment

## Closed Surfaces

No implementation authority opened:
- no parser changes
- no compiler changes
- no VM changes
- no real DB
- no SQL
- no ORM/ActiveRecord/Arel compatibility
- no real network
- no file writes
- no process execution
- no clock/random runtime authority
- no Tauri implementation
- no public/stable API
- no canon claim

## Recommended Route Map

Immediate next card:
- **LAB-STORAGE-ADAPTER-P1 — mocked storage adapter contract hardening**

Parallel safe cards:
- **LAB-FILE-IO-P1 — file/text capability shape and mocked read snapshot proof**
- **LAB-CLOCK-P1 — deterministic clock observation and deadline receipt boundary**
- **LAB-RANDOM-P1 — deterministic seed/nonce receipt boundary**
- **LAB-HOST-IPC-P1 — host dispatch seam and mocked IPC receipt boundary**

Hold cards:
- **Network real-transport HOLD card**
- **LAB-PROCESS-BOUNDARY-P1 — command authority threat model and mocked result shape**
- any real DB/file/network/process/clock/random/Tauri/public API/canon promotion route
