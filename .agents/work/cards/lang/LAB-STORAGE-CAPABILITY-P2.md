# LAB-STORAGE-CAPABILITY-P2

**Card:** LAB-STORAGE-CAPABILITY-P2
**Track:** lab-storage-capability-policy-gates-and-query-execution-receipt-v0
**Status:** CLOSED — PROOF COMPLETE (51/51)
**Route:** LAB PROOF / NO REAL DB / NO RUNTIME STORAGE
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Prove IO.StorageCapability as a mocked query execution boundary:
capability gates, row-limit clamp, include_all query_error, denial-as-data,
QueryExecutionReceipt shape, and separation from TBackend/TEMPORAL.

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P3 | QueryPlan v1 nested records (44/44) |
| LAB-STORAGE-CAPABILITY-P1 | IO.StorageCapability schema + 6-gate design |
| PROP-035 | `capability`/`effect_binding` grammar (experiment-pass) |
| PROP-046-P1 | IO.StorageCapability boundary proposal (authored) |
| STAB-P4 | Mode A closed; route authorized |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Exec fixture | `igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig` | DONE |
| Receipts fixture | `igniter-view-engine/fixtures/storage_capability/storage_capability_receipts.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_storage_capability_p2.rb` | DONE (51/51) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-storage-capability-policy-gates-and-query-execution-receipt-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P2.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (51/51)

| Section | n | Checks |
|---------|---|--------|
| SCAP2-COMPILE  | 4  | Rust compiler accepts effect + pure contracts; Layer A 8/8 accepted |
| SCAP2-SCHEMA   | 6  | QueryExecutionReceipt 15-field type shape (cap_id, cap_granted, denial_gate, effective_limit, row_limit_clamped, result_kind) |
| SCAP2-G1       | 4  | Source not in allowlist → kind:"denied", denial_gate:"G1", rows_returned:0 |
| SCAP2-G2       | 3  | Op not in allowed_ops → kind:"denied", denial_gate:"G2" |
| SCAP2-G3       | 3  | read_allowed:false → kind:"denied", denial_gate:"G3" |
| SCAP2-G4       | 4  | plan.limit > row_limit → clamp; NOT denial; row_limit_clamped:true |
| SCAP2-G5       | 3  | include_all + !allow_include_all → kind:"query_error" (not "denied"), gate:"G5" |
| SCAP2-G6       | 4  | Mocked execution: rows/empty/system_error |
| SCAP2-RECEIPT  | 6  | cap_granted:false iff {denied,query_error}; rows_returned:0 when denied; effective_limit==row_limit_cap when clamped |
| SCAP2-KDR      | 4  | 5-kind routing: denied→deny, query_error→invalid, system_error→error, empty→empty-state |
| SCAP2-COMPOSE  | 5  | plan.source.table→G1; plan.projection.include_all→G5; plan.limit→G4; source_table preserved in receipt |
| SCAP2-CLOSED   | 5  | No DB/SQL/ORM/raise/persistence at any layer |
| **Total**      | **51** | **PASS** |

---

## Key boundary findings

| Code | Finding | Impact |
|------|---------|--------|
| B1 | Effect contract passport gap: Layer B VM requires capability injection for effect contracts in same igapp. Resolved by fixture split. | ESCAPE class enforcement working correctly. Stage 2+ infrastructure required for live VM execution. |
| B2 | Rust classifier effect name vocabulary is closed: {read_file, read_json, read, write_file, write_json, write}. `read_from_storage` rejected. Used `read_file`. | Vocabulary expansion requires future card. |
| B3 | `read` is Ruby parser keyword — `parse_effect_binding_decl` calls `name_token!(%i[ident])`. Used `read_file`. | Surface constraint; `read` unusable as effect binding name. |
| B4 | `message` is Ruby parser keyword — `parse_input_decl` calls `name_token!(%i[ident])`. Renamed to `reason`. | Surface constraint; affects any contract using `message` as input. |

---

## Reusable patterns confirmed

- **Denial-as-data**: 9th proof domain (StorageCapability). G1/G2/G3 → "denied"; G5 → "query_error"; G6-error → "system_error". All return typed results; no exceptions.
- **Kind-discriminated result (KDR)**: 5th domain (QueryResult with 5 kinds).
- **QueryExecutionReceipt**: 15-field evidence record; 6 invariants proved. Evidence-only; does not confer authority.
- **ESCAPE class boundary**: Effect contracts compile clean; VM execution requires capability injection. Correct behavior.

---

## Next authorized routes

| Route | Priority | Description |
|-------|----------|-------------|
| LAB-EXECUTE-QUERY-P1 | Medium | Stage 2+ execution proof with capability injection (ch4 amendment required) |
| LAB-TC-ARRAY-P1 | Medium | Fix Rust typechecker array_literal gap (B1 from LAB-QUERY-P3) |
| Effect vocab card | Low | Add storage effect names to Rust classifier recognized list |

---

## Closed surfaces (this proof)

- Real database connection: PERMANENTLY CLOSED
- SQL execution: PERMANENTLY CLOSED
- ORM / ActiveRecord: PERMANENTLY CLOSED
- Migrations / transactions: PERMANENTLY CLOSED
- Persistence runtime: PERMANENTLY CLOSED
- Write ops: CLOSED in v0; deferred
- TBackend / TEMPORAL: NOT TOUCHED

---

*LAB-ONLY. No canon claim. No stable surface. No public API.*
