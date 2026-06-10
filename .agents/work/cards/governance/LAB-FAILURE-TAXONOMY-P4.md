# Card: LAB-FAILURE-TAXONOMY-P4

**Track:** failure-taxonomy-partial-success-cross-domain-pressure-v0  
**Route:** LAB PROOF / GOVERNANCE EVIDENCE  
**Status:** CLOSED — 54/54 PASS  
**Category:** governance  
**Date closed:** 2026-06-10  
**Authority:** lab_only — not canon, not production  
**Predecessor:** LAB-FAILURE-TAXONOMY-P3  

---

## Goal

Close the `partial_success` evidence gap identified by LAB-FAILURE-TAXONOMY-P1
(axis 6 of 10, HOLD status). Prove that `partial_success` is independently
meaningful in at least one non-reconciliation domain and is distinct from all
five adjacent outcome kinds.

---

## Domain Chosen: Batch Job Processing

A bounded batch of N items is submitted for processing. The batch runner observes
per-item outcomes (each item either succeeds or fails with a typed error). The
`BatchSignal` record carries `succeeded_count`, `failed_count`, `total_count`, and
a `signal_kind` discriminant for pre-run failure modes.

Secondary confirmation: multi-upstream HTTP fan-out (A=ok, B=error → `partial_success`).

---

## Required Proof Questions

| # | Question | Answer |
|---|----------|--------|
| 1 | Independently meaningful outside reconciliation? | **YES** — batch + network domains |
| 2 | Separation from total success? | `succeeded_count < total_count` |
| 3 | Separation from `system_error`? | `system_error` = NO per-item evidence; partial = typed counts for every item |
| 4 | Separation from `unknown_external_state`? | `unknown` = dispatched, unconfirmed; partial = all outcomes observed |
| 5 | Distinct recovery action? | `retry_failed_items` (not `retry_batch`, `reconcile`, etc.) |
| 6 | Typed data, not exception? | YES: `BatchOutcome` record with Integer count fields |
| 7 | No global `Outcome[T,E]`? | YES |
| 8 | No canon/public/runtime claim? | YES |

---

## Proof Result

**54/54 PASS**

| Section | Checks | Description |
|---------|--------|-------------|
| TAXP4-COMPILE | 5 | Fixture compiles; 11 contracts; no OOF diags |
| TAXP4-SCENARIO | 7 | Scenario contracts produce correct kinds |
| TAXP4-CLASSIFY | 6 | Classifier routes all 6 signal_kind cases |
| TAXP4-PARTIAL | 6 | Count variants + boundary conditions |
| TAXP4-BOUNDARY | 8 | Explicit distinctions vs all 5 adjacent kinds |
| TAXP4-MULTIUP | 6 | Multi-upstream network cross-domain proof |
| TAXP4-ACTION | 6 | Action router; partial has distinct action |
| TAXP4-EVIDENCE | 5 | Typed evidence: count fields + metadata |
| TAXP4-CLOSED | 5 | No global enum, no Outcome[T,E], closed surfaces |

---

## Key Invariants Proved

**All six outcome kinds are mutually distinct:**

| Kind | Per-item evidence | Items ran |
|------|-------------------|-----------|
| `ok` | Yes — `succeeded == total` | Yes |
| `partial_success` | Yes — typed counts for both succeeded + failed | Yes |
| `failed` | Yes — `failed == total` | Yes |
| `denied` | No | No |
| `system_error` | No | No (infra failure) |
| `unknown_external_state` | No | Unknown (Covenant P15) |

**Cross-domain confirmation:** Multi-upstream network independently produces
`partial_success` (A=ok + B=error) — the axis is not reconciliation-specific.

---

## Governance Recommendation

**PROMOTE** `partial_success` into PROP-047 stable terms.

Conditions on promotion:
1. `partial_success` requires **observed per-item evidence** — if outcomes are unknown, use `unknown_external_state`
2. `partial_success` requires at least one success AND at least one failure
3. Domain vocabularies may rename arms; taxonomy-level kind remains `partial_success`

---

## Files Changed

| File | Change |
|------|--------|
| `igniter-lab/igniter-view-engine/fixtures/failure_taxonomy/batch_partial_success.ig` | New fixture (11 contracts) |
| `igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p4.rb` | New proof runner |
| `igniter-lab/lab-docs/governance/lab-failure-taxonomy-partial-success-cross-domain-proof-v0.md` | New governance doc |
| `igniter-lab/.agents/work/cards/governance/LAB-FAILURE-TAXONOMY-P4.md` | This card |
| `igniter-lab/.agents/portfolio-index.md` | Updated (entry prepended) |

---

## Closed Surfaces (Unchanged)

- `igniter-vm/src/instructions.rs` — no new opcodes
- `igniter-vm/src/vm.rs` — no VM changes
- `igniter-vm/src/value.rs` — no new value types
- `igniter-compiler/src/typechecker.rs` — no compiler changes
- Ruby canon — no changes

---

## Predecessor Chain

| Card | Status | What it proved |
|------|--------|----------------|
| LAB-FAILURE-TAXONOMY-P1 | CLOSED | 7/10 axes proved; partial_success on HOLD |
| LAB-FAILURE-TAXONOMY-P2 | CLOSED | network timeout/unknown_state cross-domain |
| LAB-FAILURE-TAXONOMY-P3 | CLOSED | naming-convention PROP can open without P4 |
| **LAB-FAILURE-TAXONOMY-P4** | **CLOSED** | **partial_success cross-domain proof + PROMOTE recommendation** |

---

## What This Proves

- `partial_success` is independently meaningful outside reconciliation
- Two independent domains (batch processing + multi-upstream network) produce the same axis
- Typed per-item evidence distinguishes it from `system_error` and `unknown_external_state`
- Distinct recovery action (`retry_failed_items`) confirms separate taxonomy slot
- No global enum, Outcome[T,E], or VM/compiler/canon changes required

## What This Does NOT Prove

- Production batch scheduler execution (no Redis, no worker daemon)
- `partial_success` in streaming or incremental-write domains
- The full PROP-047 vocabulary (other axes not in scope here)
