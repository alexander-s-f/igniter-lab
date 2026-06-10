# Card: FRONTIER-DECISION-P1
**Category:** governance
**Track:** frontier-decision-honesty-surface-gap-j-boundary-v0
**Status:** CLOSED — DESIGN BOUNDARY AUTHORED
**Gate result:** N/A — design note (no proof runner)
**Date closed:** 2026-06-10
**Route:** GOVERNANCE / DESIGN NOTE / NO IMPLEMENTATION

---

## Goal

First design boundary for the **Decision Honesty surface** (Gap-J — Covenant P24/P25, the Decide
stage of the accountability loop). Define what a decision artifact must contain before any proof or
proposal opens. No implementation, no PROP, no canon changes.

**Core thesis:** a consequential decision is incomplete unless it records the chosen action, the
viable alternatives, why they were rejected, which constraints were applied, who/what authorized
the choice, and the evidence available at decision time — plus (per canon P24's seven exposures,
stricter than the card's six) expected consequences and what cannot be compensated if wrong.

---

## Depends On

| Source | Used for |
|--------|----------|
| LAB-FRONTIER-EXPEDITION-P1 | the half-built-loop finding; Gap-J as the recommended first expedition |
| Covenant P24/P25/Gap-J (covenant:226-273, 689-690) | seven exposures; constraints{} shape; StrategyDecision.rejected; constraint_hash |
| LAB-EPISTEMIC-OUTCOME-P1..P4 | evidence_kind load-bearing (P4 VM proof); needs_human_review terminal; receipt KDR discipline |
| PROP-047 | naming conventions; forbidden-collapse style (FC-*); decision kinds ≠ outcome kinds namespace |
| LAB-CONCURRENCY-P3 | receipt-replay pattern → decision replayability via constraint_hash + evidence_refs + decided_at |
| LAB-QUERY / LAB-EXECUTE-QUERY / LAB-TC-ARRAY | P2 domain substrate (QueryPlan records, Collection[Record] VM-proven) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Design boundary doc | `lab-docs/governance/frontier-decision-honesty-surface-gap-j-boundary-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/FRONTIER-DECISION-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Key Design Decisions

| # | Decision |
|---|----------|
| D1 | **DecisionReceipt KDR** with four kinds: `decided` / `decision_deferred` / `decision_escalated` / `no_viable_option` — the last is the decision analog of denial-as-data (honest empty-choice terminal, never a default pick) |
| D2 | Canon-faithful **seven exposures** (P24): card's six + `expected_outcome` + `uncompensatable` on `ChosenAction` |
| D3 | **Declaration ≠ application**: receipt records `ConstraintApplication` (satisfied/violated/waived) per decision; satisfied constraints recorded too; waiver requires named `waiver_authority` + AuthorityLink |
| D4 | **Rejected = evaluated**: capability-denied options are denials (upstream), never `rejected` (FC-D3); `disposition: final|deferred|escalated` |
| D5 | **Decision authority ≠ capability authority** (who chose vs may-it-be-done); `AuthorityLink.action: proposed|recommended|approved|vetoed`; agents may propose/recommend; **agent-only approval over model-kind evidence → `decision_escalated`** (P13/No-Upward-Coercion; human gate deferred to FRONTIER-HUMAN-GATE) |
| D6 | `EvidenceRef.evidence_kind` (real/model/human) on every ref — reuses the P4-proven load-bearing mechanism |
| D7 | `audit_obligation` (pending/deferred/impossible) is a **carrier only**; semantics belong to Gap-N / FRONTIER-AUDIT |
| D8 | Decision kinds occupy a **separate namespace** from PROP-047 outcome kinds (axis-10 analog); `no_viable_option ≠ failed` |
| D9 | All field types restricted to the VM-proven set (String/Integer/Map/Collection[Record]) so P2 needs no new substrate |

## Forbidden Collapses

FC-D1 chosen≠authorized · FC-D2 authorized≠executed · FC-D3 rejected≠impossible ·
FC-D4 waived≠absent · FC-D5 score≠justification · FC-D6 model recommendation≠human approval ·
FC-D7 receipt≠authority · FC-D8 deferred≠decided · FC-D9 no_viable_option≠failure/default-pick

---

## Recommended P2 Route

**FRONTIER-DECISION-P2 — query-plan selection under cost/safety constraints.** Two viable
QueryPlans; `row_budget` (resource) + `no_include_all` (policy/safety) constraints; one chosen with
rationale, one rejected with conflicting constraint; satisfied constraints recorded; system-policy
approval in the chain. Negative paths: both-blocked → `no_viable_option`; waiver path; model-
recommended + agent-only approval → `decision_escalated` (FC-D6 behaviorally). Chosen over
agent/human-review (needs the undesigned human gate), retry decision (largely proven in the
epistemic arc), and storage-adapter policy (thinner twin). Densest corpus; shows
capability-vs-decision authority split sharply; constraints are real proven gates, not staged
ethics examples.

---

## Gap Packet

```
note:     frontier-decision-honesty-surface-gap-j-boundary / v0
status:   CLOSED — design boundary; no implementation; no PROP
authority: governance / lab_only
date:     2026-06-10

shape:    DecisionReceipt KDR (4 kinds) + ChosenAction + RejectedAlternative +
          ConstraintApplication + AuthorityLink + EvidenceRef(evidence_kind)
rules:    seven P24 exposures; declaration≠application; rejected=evaluated;
          decision-authority≠capability-authority; agent-only approval over model evidence→escalate
collapses: FC-D1..FC-D9 explicit
p2:       query-plan selection under cost/safety constraints (recommended + justified)
closed:   grammar | constraints{} syntax | StrategyDecision canon type | compiler/VM | public API |
          ethical-reasoning claim | agent-autonomy claim | audit closure | Gap-H semantics | PROP
next:     FRONTIER-DECISION-P2 (proof-local Decision KDR, query-plan domain)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Design note only; no code,
grammar, parser, typechecker, VM, runtime, or canon/Covenant changes; no PROP authored; Gap-J
remains open. No automatic ethical reasoning, no agent autonomy claimed. Lab behavior not accepted
as canon. This card informs future gate decisions; it does not make them.
