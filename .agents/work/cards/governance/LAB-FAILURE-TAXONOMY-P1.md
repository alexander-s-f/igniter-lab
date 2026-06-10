# LAB-FAILURE-TAXONOMY-P1 — Failure Taxonomy Proposal-Planning

**Card:** LAB-FAILURE-TAXONOMY-P1  
**Track:** lab-failure-taxonomy-proposal-planning-v0  
**Route:** GOVERNANCE / TAXONOMY RESEARCH / NO IMPLEMENTATION  
**Status:** CLOSED  
**Authority:** lab_only  
**Date:** 2026-06-10  
**Predecessor:** PROP-044-P8, PROP-044-P9, LAB-OUTCOME-VARIANT-P1

---

## Goal

Research whether Igniter needs a formal failure taxonomy, using the existing outcome-envelope, epistemic-outcome, storage/query, network, Rack, Sidekiq, and variant proofs as evidence. Produce a governance recommendation only — no code, no OOF activations, no runtime behavior.

---

## Recommendation: HOLD

A shared failure taxonomy naming convention is **not yet ready for proposal authoring.**

7 of 10 required semantic axes are proven across ≥2 independent domains. Axes 4 (timeout), 5 (unknown external state), and 6 (partial success) are proven only in the reconciliation domain. One cross-domain proof is needed before a naming-convention PROP can open with confidence.

**When to open:** After LAB-FAILURE-TAXONOMY-P2 confirms that `unknown_external_state` (not `system_error`) is the correct term for a network timeout in at least one non-reconciliation domain.

---

## Evidence Sources (9 tracks)

| Source | Key vocabulary |
|--------|---------------|
| Ch12 (`ch12-effect-surface.md`) | 7 outcome kinds: succeeded/failed/partial/timed_out/unknown_external_state/compensated/cancelled |
| Covenant P11/P13/P15/P16/P17 | Uncertainty preservation, observation typing (real/model/human), timeout ≠ failure, idempotency key, compensation named |
| LAB-EPISTEMIC-OUTCOME-P2 | KDR 7 kinds including `unknown_external_state` |
| LAB-EPISTEMIC-OUTCOME-P4 | KDR routing: `still_unknown`, `partially_confirmed`, `reconciliation_denied`, `reconciliation_error` |
| LAB-OUTCOME-VARIANT-P1 | 11-arm `ReconciliationOutcome` variant; No-Upward-Coercion by arm name |
| LAB-EXECUTE-QUERY-P1/P2 | `rows`, `empty`, `denied`, `query_error`, `system_error`; G1–G3 vs G4 distinction |
| LAB-RESULT-ENVELOPE-P1/P2 | `valid`, `invalid`, `unauthorized`, `system_error`; Validation domain |
| Network proofs (LAB-STDLIB-NET-P8/P9) | `ok`, `denied`, `error`; E-HTTP-* codes; `found`/`created`/`not_found`/`upstream_error`/`capability_denied`/`upstream_unavailable` |
| PROP-044-P8, PROP-044-P9 | Path B semantics locked; OOF-KIND6 guards `__arm`/`__variant` |

---

## Stable Cross-Domain Terms (safe to name now)

| Term | Definition | Evidence (tracks) |
|------|-----------|------------------|
| `denied` / denial | Capability or authority refused the operation before it started. Deterministic. Do not retry same plan. | 7 proofs (strongest invariant) |
| `unknown_external_state` | Request sent; no confirmation received. Must reconcile. Not a failure. | Ch12, P2, P4, P1 (variant) |
| `timed_out` | Clock elapsed; outcome unknown. Not failed. P15: requires reconciliation, not retry. | Ch12, Covenant P15 |
| `system_error` | Infrastructure failure. Retry later with backoff. | Query-P2, Validation-P2 |
| `query_error` / malformed | Input or plan structurally/semantically invalid. Fix before retrying. | LAB-EXECUTE-QUERY-P1/P2, LAB-FILTER-EVAL-P1, LAB-QUERY-ORDER-LIMIT-P1 |
| denial-as-data (pattern) | Denial is a typed outcome, never an exception. | 7 independent proofs — zero contradictions |

---

## Domain-Local Terms (must stay local)

All 11 `ReconciliationOutcome` arms; `rows`/`empty`; `found`/`created`/`not_found`/`upstream_unavailable`; `non_retryable`; `valid`/`invalid`; E-HTTP-* codes. Each is precise within its domain and would lose meaning if promoted to a global taxonomy.

---

## Do Not Collapse

| Pair | Why distinct |
|------|-------------|
| `denied` vs `query_error` | Access control vs malformed plan — different consumer action |
| `timed_out` vs `unknown_external_state` | Clock expiry vs lost-ack — P15 names them separately |
| `unknown_external_state` vs `system_error` | Must reconcile vs retry later — different recovery paths |
| `partial` vs `unknown` | Some effects confirmed vs no confirmation — different reconciliation scope |
| `validation invalid` vs `capability denied` | Fix data vs fix credentials — different remediation |
| `retry budget exhausted` vs `upstream failure` | `still_unknown_no_budget` vs `upstream_unavailable` — distinct routing |
| observation types (real/model/human) | Different evidence authority; model cannot route to accept without human review |

---

## Closed Surfaces

| Surface | Status |
|---------|--------|
| `Outcome[T,E]` generic sealed type | **CLOSED** — 3 unsatisfied preconditions: generic type params, sealed variant across domains, cross-domain vocabulary consensus |
| Global `FailureKind` enum | **CLOSED** — 10-axis taxonomy cannot be faithfully collapsed to flat enum |
| New OOF diagnostic codes | **CLOSED** — none authorized by this card |
| Runtime/compiler/parser changes | **CLOSED** — naming convention only |
| Serialization policy | **CLOSED** — no stable ABI defined |
| Production runtime claim | **CLOSED** — lab only |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Is a shared failure taxonomy ready for proposal authoring? | HOLD — 7/10 axes proven cross-domain; 3 axes need one more proof |
| Which terms are stable enough to name? | `denied`, `unknown_external_state`, `timed_out`, `system_error`, `query_error`, `denial-as-data` pattern |
| Which terms must remain domain-local? | All 11 ReconciliationOutcome arms; all HTTP/Query/Validation success kinds |
| Is Outcome[T,E] required now? | **NO** — KDR + domain-local variants are sufficient for all proven use cases |
| Does Path B change the taxonomy decision? | Enables domain-specific variant adoption; does not change HOLD |
| Exact next route? | **LAB-FAILURE-TAXONOMY-P2** — one targeted cross-domain proof: timeout → unknown_external_state in a non-reconciliation domain (network or storage). Can run in parallel with LAB-OUTCOME-VARIANT-P2. |

---

## Deliverables

| Artifact | Path |
|----------|------|
| Governance doc | `igniter-lab/lab-docs/governance/lab-failure-taxonomy-proposal-planning-v0.md` |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FAILURE-TAXONOMY-P1.md` |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` |

---

## Predecessor Chain

LAB-RESULT-ENVELOPE-P1/P2 → LAB-EPISTEMIC-OUTCOME-P1..P4 → LAB-OUTCOME-VARIANT-P1 → PROP-044-P8 → PROP-044-P9 → **LAB-FAILURE-TAXONOMY-P1** (this card)
