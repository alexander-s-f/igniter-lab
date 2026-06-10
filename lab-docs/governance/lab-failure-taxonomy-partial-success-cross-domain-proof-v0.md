# lab-failure-taxonomy-partial-success-cross-domain-proof-v0

**Track:** failure-taxonomy-partial-success-cross-domain-pressure-v0  
**Route:** LAB PROOF / GOVERNANCE EVIDENCE  
**Authority:** lab_only — not canon, not production  
**Proof result:** 54/54 PASS  
**Date:** 2026-06-10  
**Predecessor:** LAB-FAILURE-TAXONOMY-P3  

---

## Purpose

LAB-FAILURE-TAXONOMY-P1 put `partial_success` on HOLD (axis 6 of 10) because it
had only appeared in the reconciliation domain. This card provides the required
cross-domain proof: `partial_success` is independently meaningful in the batch job
processing domain and the network multi-upstream domain, and is explicitly distinct
from all five adjacent outcome kinds.

---

## Required Proof Questions

| # | Question | Answer |
|---|----------|--------|
| 1 | Is `partial_success` independently meaningful outside reconciliation? | **YES** — batch job processing and multi-upstream network both independently produce it |
| 2 | What concrete evidence separates it from total success? | `succeeded_count < total_count`: some items failed |
| 3 | What concrete evidence separates it from `system_error`? | `system_error` carries NO per-item evidence (`total_count=0`); partial carries typed counts for every item |
| 4 | What concrete evidence separates it from `unknown_external_state`? | `unknown` = dispatched, no acknowledgement (Covenant P15); `partial` = all outcomes observed and typed |
| 5 | Does it require retry, compensation, or degraded output? | YES: distinct action `retry_failed_items` (vs `retry_batch` for full failure, `reconcile` for unknown) |
| 6 | Is the partial result typed data, not an exception? | YES: `BatchOutcome` record with Integer count fields and preserved `idempotency_key` |
| 7 | Does the proof avoid global `Outcome[T,E]` authority? | YES |
| 8 | Does the proof avoid canon/public/runtime claims? | YES |

---

## Domain 1: Batch Job Processing

**Scenario**: A bounded batch of N items is submitted for processing. The batch
runner observes per-item outcomes (each item either succeeds or fails with a typed
error). The batch signal carries `succeeded_count`, `failed_count`, and `total_count`.

**Classification logic** (`BatchOutcomeClassifier`):

| Signal | Outcome kind | Recovery action |
|--------|-------------|-----------------|
| `signal_kind="ran"`, `succeeded == total` | `ok` | `consume` |
| `signal_kind="ran"`, `succeeded > 0`, `failed > 0` | `partial_success` | `retry_failed_items` |
| `signal_kind="ran"`, `failed == total` | `failed` | `retry_batch` |
| `signal_kind="denied"` | `denied` | `fix_policy` |
| `signal_kind="system_error"` | `system_error` | `investigate` |
| `signal_kind="unknown_external_state"` | `unknown_external_state` | `reconcile` |

**Explicit distinctions proved by VM execution:**

### partial_success vs ok (Q2)

`PartialSucceededThreeOfFive`: 3/5 succeed → `kind="partial_success"`, `failed_count=2`  
`AllSucceeded`: 5/5 succeed → `kind="ok"`, `failed_count=0`

The distinguishing evidence: `failed_count > 0` in `partial_success`; `failed_count = 0` in `ok`.

### partial_success vs system_error (Q3)

`PartialSucceededThreeOfFive`: `total_count=5`, `succeeded_count=3`, `failed_count=2`  
`SystemErrorBatch`: `total_count=0`, `succeeded_count=0`, `failed_count=0`

Infrastructure failure (`system_error`) carries **no per-item evidence** — the batch
never ran. `partial_success` carries typed evidence for every item. The consuming
system can act at item granularity for `partial_success`; it cannot for `system_error`.

### partial_success vs unknown_external_state (Q4)

`partial_success` via `signal_kind="ran"`: the batch ran and returned per-item outcomes.  
`unknown_external_state` via `signal_kind="unknown_external_state"`: the batch was
dispatched to the worker infrastructure but no acknowledgement was received (Covenant
P15 applies at the batch level). The external state is indeterminate.

Key difference: `partial_success` outcomes are **observed** (typed, confirmed);
`unknown_external_state` outcomes are **inferred** (the batch may have run, may not have).

### partial_success vs denied (Q5 by contrast)

`denied`: `total_count=0`, `succeeded_count=0`. Nothing was ever attempted.  
`partial_success`: `total_count=5`, `succeeded_count >= 1`. Items were attempted and results are known.

### partial_success vs failed

`AllFailed`: `succeeded_count=0` → `kind="failed"`. Every item failed.  
`PartialSucceededOneOfFive`: `succeeded_count=1` → `kind="partial_success"`. Even one success changes the classification — the consumer must handle the succeeded items.

---

## Domain 2: Multi-Upstream Network (Cross-Domain Confirmation)

**Scenario**: An HTTP fan-out calls two independent upstreams (A and B). Both must
succeed for the overall result to be `ok`. If one succeeds and one fails, the result
is `partial_success` — not `failed` (something did succeed), not `unknown` (we have
confirmed outcomes for both upstreams).

```
A=ok  + B=ok    → ok
A=ok  + B=error → partial_success  (cross-domain proof target)
A=err + B=ok    → partial_success  (symmetric)
A=err + B=err   → failed
A=ok  + B=unk   → unknown_external_state  (Covenant P15 per-upstream)
```

The `partial_success` outcome carries `upstream_a_kind` and `upstream_b_kind` as
typed evidence — the consumer knows *which* upstream failed, not just that something
did.

This domain is structurally independent of reconciliation. No reconciliation
vocabulary, no `ConfirmedSucceededReal`, no `ReconciliationOutcome`. The same
outcome axis emerges from a different physical pattern: multi-target dispatch with
heterogeneous results.

---

## Typed Evidence Requirement

`partial_success` is not an exception, not a flag, not a raised error. It is a
typed record (`BatchOutcome`) that carries:

- `kind: String` — the outcome classification
- `succeeded_count: Integer` — items with confirmed success
- `failed_count: Integer` — items with confirmed failure
- `total_count: Integer` — total items attempted
- `idempotency_key: String` — retry gate for failed items (Covenant P16)
- `metadata: Map[String,String]` — correlation context

The `EvidenceInspector` contract proves that for `partial_success`:
`succeeded_count + failed_count == total_count` — every item has a typed outcome.

---

## All Six Outcome Kinds Are Mutually Distinct

| Kind | What it means | Per-item evidence | Items ran |
|------|--------------|-------------------|-----------|
| `ok` | All N items succeeded | Yes — `succeeded_count = total_count` | Yes |
| `partial_success` | K succeeded, N-K failed (0 < K < N) | Yes — counts for both | Yes |
| `failed` | All N items failed | Yes — `failed_count = total_count` | Yes |
| `denied` | Capability gate refused; nothing attempted | No | No |
| `system_error` | Infrastructure failure; items not attempted | No | No (or unknown) |
| `unknown_external_state` | Batch dispatched; no acknowledgement | No | Unknown (Covenant P15) |

The recovery actions are all distinct: `consume / retry_failed_items / retry_batch / fix_policy / investigate / reconcile`.

Collapsing `partial_success` into `failed` would destroy the information that some
items succeeded, forcing unnecessary re-processing. Collapsing it into `ok` would
silently discard failure evidence.

---

## Governance Recommendation

**PROMOTE** `partial_success` into PROP-047 stable terms.

Evidence threshold met:
- **Two independent non-reconciliation domains**: batch processing + multi-upstream network
- **All 8 required proof questions** answered affirmatively
- **Explicit separation from all 5 adjacent kinds** proved by VM-executed contracts
- **Typed result record** with count-level evidence (not an exception)
- **Distinct recovery action** (`retry_failed_items`)
- **No global enum, no Outcome[T,E], no canon change**

Conditions on promotion:
1. The definition must specify that `partial_success` requires **observed per-item evidence** — if outcomes are unknown (Covenant P15 applies), use `unknown_external_state` instead.
2. The definition must specify that `partial_success` requires at least one of each: one success AND one failure — `0` successes → `failed`; `N` successes → `ok`.
3. Domain vocabularies may rename the underlying arms (e.g., `ConfirmedSucceededReal` + `ConfirmedFailed` in reconciliation), but the taxonomy-level kind remains `partial_success`.

---

## Fixture Location

`igniter-lab/igniter-view-engine/fixtures/failure_taxonomy/batch_partial_success.ig`

11 contracts:
- 7 scenario contracts (`AllSucceeded`, `PartialSucceededThreeOfFive`,
  `PartialSucceededOneOfFive`, `AllFailed`, `DeniedBeforeBatch`,
  `SystemErrorBatch`, `UnknownStateBatch`)
- `BatchOutcomeClassifier` — core classifier for all 6 signal kinds
- `BatchActionRouter` — maps kind → recovery action
- `MultiUpstreamClassifier` — network cross-domain proof
- `EvidenceInspector` — proves typed per-item evidence invariant

---

## What This Proves

- `partial_success` is independently meaningful outside reconciliation
- Two domains (batch, network) independently produce the same axis
- `partial_success` is separated from each of the 5 adjacent kinds by typed evidence
- The result is a typed record, not an exception
- The recovery action is distinct (`retry_failed_items`)
- No global enum, no Outcome[T,E], no VM/compiler/canon changes

## What This Does NOT Prove

- Production runtime behavior for batch job execution (no real scheduler, no Redis)
- `partial_success` in streaming or incremental-write domains (deferred)
- The full PROP-047 vocabulary (only the `partial_success` axis is closed here)
