# LAB-FAILURE-TAXONOMY-P2 — Network Timeout / Unknown External State Proof

**Card:** LAB-FAILURE-TAXONOMY-P2  
**Track:** lab-failure-taxonomy-network-timeout-unknown-state-proof-v0  
**Route:** LAB PROOF / FAILURE TAXONOMY EVIDENCE / NO TAXONOMY PROP  
**Status:** CLOSED  
**Authority:** lab_only  
**Date:** 2026-06-10  
**Predecessor:** LAB-FAILURE-TAXONOMY-P1 (HOLD recommendation)

---

## Goal

Provide the second-domain evidence requested by LAB-FAILURE-TAXONOMY-P1: prove in the HTTP client / upstream-call domain that timeout and lost acknowledgement **after** dispatch routes to `unknown_external_state`, not `system_error` or any other failure kind.

---

## Result

**51/51 PASS**

Proof runner: `igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p2.rb`  
Fixture: `igniter-lab/igniter-view-engine/fixtures/failure_taxonomy/network_timeout_unknown_state.ig`  
Governance doc: `igniter-lab/lab-docs/governance/lab-failure-taxonomy-network-timeout-unknown-state-proof-v0.md`

---

## Core Result

```
dispatch_started == true  AND  ack_received == false
  => kind: "unknown_external_state"    ← Covenant P15, proven in HTTP client domain

dispatch_started == false
  => NOT "unknown_external_state"
```

The `transport_kind: "timeout"` signal **alone** does not determine the outcome kind. Pre-dispatch timeout (`dispatch_started=false`) routes to `"upstream_unavailable"`; post-dispatch timeout (`dispatch_started=true, ack_received=false`) routes to `"unknown_external_state"`. Same `transport_kind` value; different epistemic meaning.

---

## Proof Sections

| Section | Checks | Result |
|---------|--------|--------|
| FTAX2-COMPILE | 6 | ALL PASS |
| FTAX2-SHAPE | 7 | ALL PASS |
| FTAX2-CLASSIFY | 8 | ALL PASS |
| FTAX2-NOT-UNKNOWN | 6 | ALL PASS |
| FTAX2-METADATA | 7 | ALL PASS |
| FTAX2-RECONCILE | 5 | ALL PASS |
| FTAX2-CROSSDOMAIN | 6 | ALL PASS |
| FTAX2-CLOSED | 7 | ALL PASS |
| **Total** | **51** | **51/51 PASS** |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Does post-dispatch timeout → `unknown_external_state`? | **YES** |
| Does pre-dispatch timeout → `unknown_external_state`? | **NO** — routes to `upstream_unavailable` |
| Can `transport_kind: "timeout"` alone classify the outcome? | **NO** — `dispatch_started` + `ack_received` required |
| Does `unknown_external_state` carry reconciliation data? | **YES** — `request_id`, `idempotency_key`, metadata preserved |
| Is `unknown_external_state` the right term (not `system_error`)? | **YES** — epistemically distinct; different recovery path |
| Does this open a formal taxonomy PROP? | **NO** — lab evidence only; HOLD extended |
| What is still missing for a PROP? | Axis 6 (partial_success) is still single-domain only; or scope PROP without it |

---

## Axes Status After This Proof

| Axis | Before P2 | After P2 |
|------|-----------|----------|
| capability_denial | ≥2 domains ✓ | unchanged |
| malformed_plan | ≥2 domains ✓ | unchanged |
| external_unavailable | ≥2 domains ✓ | unchanged |
| timeout | reconciliation only | **now cross-domain ✓** |
| unknown_external_state | reconciliation only | **now cross-domain ✓** |
| partial_success | reconciliation only | still single-domain |
| validation_invalid | ≥2 domains ✓ | unchanged |
| compensation | 1 domain | unchanged |
| retryable_vs_not | ≥2 domains ✓ | unchanged |
| type_error_vs_domain_outcome | ≥2 domains ✓ | unchanged |

7/10 axes proven cross-domain before P2. **9/10 after P2.**

---

## Closed Surfaces

- No formal taxonomy PROP opened
- No global FailureKind enum defined
- No Outcome[T,E] implemented
- No compiler diagnostics added
- No VM/runtime behavior changed
- No real network I/O (all contracts pure; SIR effects: [])
- No retry scheduler introduced
- No variant values serialized
- Canon not modified

---

## Deliverables

| Artifact | Path |
|----------|------|
| Fixture | `igniter-lab/igniter-view-engine/fixtures/failure_taxonomy/network_timeout_unknown_state.ig` |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_failure_taxonomy_p2.rb` |
| Governance doc | `igniter-lab/lab-docs/governance/lab-failure-taxonomy-network-timeout-unknown-state-proof-v0.md` |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-FAILURE-TAXONOMY-P2.md` |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` |

---

## Predecessor Chain

LAB-RESULT-ENVELOPE-P1/P2 → LAB-EPISTEMIC-OUTCOME-P1..P4 → LAB-OUTCOME-VARIANT-P1 → PROP-044-P8 → PROP-044-P9 → LAB-FAILURE-TAXONOMY-P1 → **LAB-FAILURE-TAXONOMY-P2** (this card)

---

## Recommended Next Route

**LAB-FAILURE-TAXONOMY-P3** — Taxonomy proposal readiness decision.

9/10 axes are now proven cross-domain. P3 should decide:
- (A) Open naming-convention PROP for axes 1–5 + 7–10 (exclude partial_success)
- (B) One more domain proof for axis 6 (partial_success), then open full PROP
- (C) Continue HOLD

Can run in parallel with LAB-OUTCOME-VARIANT-P2.
