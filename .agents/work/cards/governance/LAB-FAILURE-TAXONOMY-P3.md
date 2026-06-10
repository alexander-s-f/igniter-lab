# LAB-FAILURE-TAXONOMY-P3 — Taxonomy Proposal Readiness Decision

**Card:** LAB-FAILURE-TAXONOMY-P3  
**Track:** lab-failure-taxonomy-proposal-readiness-decision-v0  
**Route:** GOVERNANCE / READINESS DECISION / NO IMPLEMENTATION  
**Status:** CLOSED  
**Authority:** lab_only  
**Date:** 2026-06-10  
**Predecessor:** LAB-FAILURE-TAXONOMY-P1 (HOLD), LAB-FAILURE-TAXONOMY-P2 (51/51 PASS)

---

## Decision: A — Open Narrow Naming-Convention PROP Now

The P1 HOLD condition has been satisfied. LAB-FAILURE-TAXONOMY-P2 delivered the required cross-domain proof for timeout and `unknown_external_state` in a non-reconciliation domain (HTTP client, 51/51 PASS). The evidence base is sufficient for a narrowly scoped naming-convention proposal.

---

## Evidence Summary

| Axes | P1 status | P3 status |
|------|-----------|-----------|
| capability_denial | ✓ cross-domain (7+ proofs) | unchanged |
| malformed_plan | ✓ cross-domain | unchanged |
| external_unavailable | ✓ cross-domain | unchanged |
| **timeout** | reconciliation-only | **✓ NOW cross-domain (P2)** |
| **unknown_external_state** | reconciliation-only | **✓ NOW cross-domain (P2)** |
| partial_success | reconciliation-only | still single-domain — **explicitly deferred** |
| validation_invalid | ✓ cross-domain | unchanged |
| compensation | partial (canon + 1 domain) | unchanged |
| retryable_vs_not | ✓ cross-domain (pattern) | unchanged |
| type_error_vs_domain_outcome | ✓ very strong | unchanged |

9/10 axes cross-domain. Axis 6 deferred.

---

## PROP Scope Authorized by This Card

**PROP title (proposed):** "Failure Outcome Naming Convention and Recovery-Axis Guidance"

**Authorized:**
- 5 stable cross-domain terms: `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error`
- 2 patterns: `denial-as-data`, timeout-is-not-failure
- 7 forbidden-collapse rules (including `partial` ≠ `unknown` as guidance, without naming `partial` as a stable term)
- KDR/variant usage boundary rule
- Observation type guidance (real/model/human; No-Upward-Coercion)
- All 10 axes documented; axis 6 explicitly deferred
- Recovery guidance per axis

**Explicitly deferred in PROP:**
- `partial` stable cross-domain term — single-domain evidence; deferred to P4
- `compensation` stable cross-domain term — Ch12 + 1 domain; pattern only
- Retryable/non-retryable stable term — pattern authorized; arm names domain-local

**Permanently closed in PROP:**
- Global `FailureKind` enum
- `Outcome[T,E]` generic sealed type
- New OOF diagnostic codes
- Compiler / parser / VM / runtime changes
- Serialization ABI
- Production stability claims

---

## Why Not B or C

**Against B (hold for partial_success proof):**
P1 stated the exact HOLD condition: one non-reconciliation cross-domain proof for timeout and unknown_external_state. That condition was met by P2. Partial_success can be deferred explicitly in the PROP — this is stronger than silence. Further waiting delays value from 9 proven axes.

**Against C (continue HOLD):**
Evidence is not fragmented. The naming-convention PROP has no runtime consequences and can be amended cheaply if axis 6 is confirmed later. Risk is low; value is available now.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| 1. Are 9/10 cross-domain axes enough for proposal-authoring? | **YES** |
| 2. Does partial_success block the proposal? | **NO** — explicitly deferred in PROP scope |
| 3. Should the proposal exclude partial_success or wait? | **Exclude and defer explicitly** |
| 4. Is Outcome[T,E] still closed? | **YES — CLOSED** |
| 5. Is global FailureKind enum still closed? | **YES — CLOSED** |
| 6. Is Path B variant/match relevant to proposal scope? | **YES** — as substrate evidence for the KDR/variant boundary rule |
| 7. What exact next card? | Proposal authoring card (next available PROP number). Secondary: LAB-FAILURE-TAXONOMY-P4 (partial_success proof, not blocking). |

---

## Deliverables

| Artifact | Path |
|----------|------|
| Governance decision doc | `igniter-lab/lab-docs/governance/lab-failure-taxonomy-proposal-readiness-decision-v0.md` |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FAILURE-TAXONOMY-P3.md` |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` |

---

## Predecessor Chain

LAB-RESULT-ENVELOPE-P1/P2 → LAB-EPISTEMIC-OUTCOME-P1..P4 → LAB-OUTCOME-VARIANT-P1 → PROP-044-P8/P9 → LAB-FAILURE-TAXONOMY-P1 → LAB-FAILURE-TAXONOMY-P2 → **LAB-FAILURE-TAXONOMY-P3** (this card)

---

## Recommended Next Routes

1. **Primary:** Open proposal authoring card for "Failure Outcome Naming Convention and Recovery-Axis Guidance" (next available PROP number). This card authorizes that opening.

2. **Secondary (parallel, not blocking):** `LAB-FAILURE-TAXONOMY-P4` — partial_success cross-domain proof. If P4 passes before the PROP is authored, the PROP can include `partial` from the start. If P4 runs after, the PROP can be amended.

3. **Independent:** `LAB-OUTCOME-VARIANT-P2` (if not already closed) can continue in parallel.
