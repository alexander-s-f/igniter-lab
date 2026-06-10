# Card: LAB-EPISTEMIC-OUTCOME-P1
**Category:** governance
**Track:** lab-epistemic-outcome-model-and-unknown-state-boundary-v0
**Status:** CLOSED — research/design complete
**Gate result:** N/A — design/research card (no proof runner)
**Date closed:** 2026-06-10
**Route:** GOVERNANCE / DESIGN / LAB-ONLY

---

## Goal

Research and design the epistemic outcome model for Igniter's open-world surfaces:
distinguish observed success, observed failure, denial, timeout, unknown external
state, partial observation, cancellation, and compensation as **states of knowledge**
rather than flattening them into `Result[T,E]` or `Option[T]`. Produce a taxonomy and
promotion boundary without implementing types, parser/typechecker/runtime changes, or
public/stable API authority.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-RESULT-ENVELOPE-P1 | ✅ DONE — taxonomy baseline; 5 reusable patterns |
| LAB-RESULT-ENVELOPE-P2 | ✅ DONE — 3rd domain; kind-discriminant generalises (50/50) |
| PROP-044-P1 | ✅ DONE — KDR convention doc; grammar gap enumerated |
| PROP-044-P5 | ✅ DONE — variant+match TypeChecker; OOF-KIND1..5 active (75/75) |
| PROP-045-P2 | ✅ DONE — intent descriptor parser + metadata (53/53) |
| LAB-STORAGE-CAPABILITY-P1 | ✅ DONE — storage boundary design; commit-ack unmodeled in v0 |
| LAB-STDLIB-NET-P8 | ✅ DONE — HttpResult + RetryEnvelope (50/50) |
| LAB-STDLIB-NET-P9 | ✅ DONE — ContractResult 6-kind; upstream_unavailable=budget exhaustion (55/55) |
| LAB-QUERY-P3 | ✅ DONE — QueryResult 5-kind; system_error folds timeout (44/44) |
| STAB-P4 | ↗ gov Mode-A — P0 governance fixes (PROP numbering/status/hash/fragment) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Governance/design doc | `lab-docs/governance/lab-epistemic-outcome-model-and-unknown-state-boundary-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Headline Finding

**Igniter already has an epistemic outcome model — at the canon design layer — but it is
unimplemented, and the lab proofs do not honor it.**

- **Canon declares it:** Ch12 Effect Surface enumerates 7 outcomes incl.
  `unknown_external_state` ("not a failure… signals reconciliation", ch12:131); Covenant
  P11/P13/P15/P16/P17 + the Epistemic State Machine (No Upward Coercion) give the basis.
  P15: timeout = `UnknownExternalOutcome`, not `ObservedFailure`.
- **Not implemented:** `UnknownExternalOutcome`/`ObservedFailure` are named, not spec'd;
  Covenant registry lists P15 as a `planned PROP` (covenant:680).
- **Lab flattens it:** `QueryResult` folds timeout/connection-loss into `system_error`;
  `ContractResult.upstream_unavailable` asserts unavailability from mere budget exhaustion
  (an unknown→failure upward coercion the Covenant forbids); storage commit-ack loss
  "not modeled in v0".
- **Grammar blocker lifted:** PROP-044-P3/P5 landed variant+match at parser+typechecker
  (OOF-KIND1..5). An enforced `Outcome[T,E]` variant is typecheck-expressible now;
  VM/runtime execution of match remains unproved.

---

## Three Orthogonal Axes (key factoring)

| Axis | Question | Canon surface |
|------|----------|--------------|
| Outcome | did the effect happen, do we know? | Ch12 enum; UnknownExternalOutcome (P15) |
| Observation | world / model / human provenance? | `Obs[kind,T]` (ch3:29); P13 |
| Estimation | how certain is the quantity? | `~T`/Uncertain (PROP-026); P11 |

Epistemic outcome = the **Outcome** axis. Probabilistic uncertainty = **separate** track.

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Adequate model for unknown external state today? | **Partially** — declared in canon, unimplemented, not honored by lab |
| `Result[T,E]` sufficient? | **No** — closed-world CORE only; P15 says timeout ≠ failure |
| `Option[T]` sufficient? | **No** — presence/absence cannot express denial/timeout/unknown |
| KDR convention models v0 outcomes? | **Yes** — `kind:String` can carry unknown/timeout/denied today; unenforced |
| variant/match prerequisite for stronger model? | **For enforced model yes — now substantially landed** (PROP-044-P5); not for the v0 convention |
| Probabilistic uncertainty same track? | **No** — separate `~T`/Uncertain track |
| Blocks StorageCapability execution? | **Yes for writes** (lost commit-ack); reads lower-risk |
| Blocks real network execution? | **Yes for non-idempotent/effectful** (P15+P16); idempotent reads lower-risk |
| Changes Query/Rack/Sidekiq proofs? | **No retroactively** — valid as proved; reclassified epistemically-incomplete |
| Implementation open now? | **No** — research/design, lab-only |
| Exact next route? | KDR unknown-state convention proof → reconciliation note → failure-taxonomy PROP on PROP-044 substrate |

---

## Next Route

1. **Immediate (no gate):** LAB-EPISTEMIC-OUTCOME-P2 — unknown-state KDR convention proof
   (add `unknown_external_state`/`timed_out`/`partial`/`cancelled`/`denied` to a `kind:String`
   envelope in a lost-confirmation domain; consumer branches fail-closed).
2. **Short-term (no gate):** reconciliation-consumer design note (how a DAG node consumes
   unknown state: fail-closed, route to reconciliation, no upward coercion).
3. **Medium-term (PROP + gate):** failure-taxonomy PROP turning Ch12 enum +
   UnknownExternalOutcome/ObservedFailure into a sealed `Outcome[T,E]` variant on the PROP-044
   substrate. Typecheck-unblocked; **runtime-sequenced** after variant/match VM execution.
4. **Governance (STAB-P4):** resolve the P15→PROP-035 number collision (Covenant uses PROP-035
   for failure taxonomy; portfolio index uses it for capability/effect_binding grammar).

**Closed:** any `Outcome` implementation in production files; real storage write / effectful
network execution; VM authority for variant/match; redefining `Result`/`Option`; `~T` inside the
outcome type.

---

## Gap Packet

```
analysis:   lab-epistemic-outcome-model-and-unknown-state-boundary / v0
status:     CLOSED — design/research; no promotions authorized
authority:  governance / lab_only
date:       2026-06-10

model_in_canon:        YES (Ch12 + Covenant P11/P13/P15/P16/P17 + state machine)
model_implemented:     NO  (UnknownExternalOutcome/ObservedFailure named not spec'd; P15=planned PROP)
lab_honors_model:      NO  (timeout/lost-ack flattened to system_error/upstream_unavailable)
grammar_blocker:       LIFTED at typecheck (PROP-044-P3/P5); CLOSED at runtime (match VM unproved)

result_option:         INSUFFICIENT (closed-world only)
kdr_convention:        SUFFICIENT as v0 (unenforced)
variant_outcome:       enforced; typecheck-expressible; runtime-blocked
probabilistic:         SEPARATE track (~T / Uncertain)

blocks_storage_write:  YES   blocks_network_effectful: YES
blocks_idempotent_read: lower-risk (timeout still = unknown)
existing_proofs:       not retroactively changed; reclassified epistemically-incomplete
implementation_now:    NO

next:
  immediate:   LAB-EPISTEMIC-OUTCOME-P2 (unknown-state KDR convention proof)
  short_term:  reconciliation-consumer design note
  medium_term: failure-taxonomy PROP on PROP-044 variant substrate (runtime-sequenced)
  governance:  STAB-P4 P15→PROP-035 number resolution
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. No production files changed.
No types/parser/typechecker/runtime modified. No PROP authored. `Result`/`Option` semantics
untouched. No variant/match runtime authority claimed. Old Ruby framework surfaces not used as
language authority. External ecosystem report treated as evidence, not authority. Lab behavior
not accepted as canon. This card informs future gate decisions; it does not make them.
