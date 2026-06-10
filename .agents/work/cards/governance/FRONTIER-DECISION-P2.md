# Card: FRONTIER-DECISION-P2
**Category:** governance
**Track:** frontier-decision-query-plan-selection-kdr-proof-v0
**Status:** CLOSED — PROVED
**Gate result:** 72/72 PASS (first full run; no fixture iteration)
**Date closed:** 2026-06-10
**Route:** LAB PROOF / DECISION HONESTY / GAP-J PRESSURE

---

## Goal

Prove the FRONTIER-DECISION-P1 `DecisionReceipt` KDR surface (Gap-J / P24/P25) is producible,
carriable, and routable in the lab VM, in the domain of query-plan selection under `row_budget`
(resource) and `no_include_all` (policy/safety) constraints. KDR only — no grammar, no
`StrategyDecision` canon type, no PROP.

---

## Depends On

| Source | Status |
|--------|--------|
| FRONTIER-DECISION-P1 | ✅ design boundary (shapes, FC-D1..D9, kind rules) |
| LAB-EPISTEMIC-OUTCOME-P4 | ✅ routing/guard proof pattern; evidence_kind mechanism; == divergence layering |
| LAB-QUERY-P3 / LAB-TC-ARRAY-P1/P2 / LAB-RECORD-VM | ✅ Collection[Record] + nested-record VM substrate |
| PROP-047 | ✅ namespace discipline (decision kinds ≠ outcome kinds) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (6 types, 7 contracts) | `igniter-view-engine/fixtures/frontier_decision/query_plan_decision.ig` | ✅ DONE |
| Proof runner (72 checks) | `igniter-view-engine/proofs/verify_frontier_decision_p2.rb` | ✅ DONE |
| Proof doc | `lab-docs/governance/frontier-decision-query-plan-selection-kdr-proof-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/FRONTIER-DECISION-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Proof Sections (72/72)

```
FDEC-COMPILE   (4)  — Ruby TC runs; Rust SIR 7 contracts; producers accepted; no variants
FDEC-TYPES     (8)  — DecisionReceipt 12 fields; nested ChosenAction; 4 collections; evidence_kind
FDEC-DECIDED   (8)  — full receipt VM-constructed; P24 SEVEN exposures; satisfied constraints recorded
FDEC-REJECT    (5)  — constraint-driven rejections (no_include_all / row_budget); reasons; dispositions
FDEC-AUTHORITY (5)  — capability-denied → denied_upstream, EXCLUDED from rejected (FC-D3);
                      capability-permitted yet decision-rejected; agent-recommended ≠ approved
FDEC-EVIDENCE  (4)  — evidence_kind preserved; model+agent→escalated (FC-D6); model+human→decided
FDEC-KINDGUARD (7)  — in-VM kind rules: nvo | deferred | none→escalated (FC-D1) |
                      model+system→escalated (v0-conservative) | real+agent→decided | nvo>pending
FDEC-ROUTE     (6)  — execute_plan/wait/human_review/stop; unknown→hold fail-closed; output=data (FC-D7)
FDEC-NVO       (4)  — empty chosen (no default pick, FC-D9); ≠failed; ≠deferred; consumer stops
FDEC-WAIVER    (6)  — valid waiver recorded+listed (FC-D4) w/ named authority + chain entry;
                      empty-authority waiver → invalid_waiver_escalate (fail closed)
FDEC-DEFER     (3)  — deferred→wait, never execute (FC-D8); ≠escalated
FDEC-SCORE     (4)  — argmax+empty rationale→insufficient_justification (FC-D5); no score field on receipt
FDEC-CLOSED    (8)  — no variant/match/constraints{}; no StrategyDecision type; no now(); carrier-only
                      audit field; no PROP-047 kind collision; lab-only
```

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Gap-J surface VM-executable today | 12-field receipt (nested record + 4 collections) constructed, carried, routed — first-run 72/72, zero new substrate needed |
| Two authorities demonstrably distinct | capability-denied excluded upstream; capability-permitted still decision-rejected |
| Escalation rule is behavioral law | model evidence: only human approval decides; agent AND system escalate (system-over-model parked on FRONTIER-HUMAN-GATE) |
| no_viable_option = denial-as-data analog | empty chosen, ≠failure, consumer stops — honest empty-choice terminal proven |
| Invalid waiver fails closed | empty waiver_authority → escalate (authority question), never silent drop/proceed |
| Namespaces clean | decision kinds never collide with PROP-047 outcome kinds |
| Known divergence carried | guards Ruby-TC-blocked (String ==), Rust-VM-executed — same STAB-P4 drift as P4, documented |

---

## Gap Packet

```
proof:     frontier-decision-query-plan-selection-kdr-proof / v0
status:    CLOSED — 72/72 PASS
authority: governance / lab_only
date:      2026-06-10
domain:    query-plan selection under row_budget + no_include_all

vm_proved: decided(7 exposures, satisfied constraints recorded) | constraint-driven rejections |
           FC-D1/D3/D4/D5/D6/D7/D8/D9 behaviorally | kind guard (7 rules) | routing fail-closed |
           waiver valid+invalid | nvo empty-chosen
regression: EPISTEMIC-P2 54/54 | EPISTEMIC-P4 46/46 | git only-new-files
closed:    grammar | constraints{} | StrategyDecision canon | compiler/VM | PROP | ethics-engine |
           agent autonomy | audit semantics | real IO | public API
next:      FRONTIER-DECISION-PROP-READINESS (surface clean; P3 hardening NOT needed — no gaps found)
           parallel: FRONTIER-HUMAN-GATE-P1 (model→human seam now load-bearing in two arcs)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only; no grammar,
no `constraints{}`, no `StrategyDecision` canon type, no compiler/parser/VM changes, no PROP, no
automatic ethical reasoning, no agent autonomy, no audit semantics beyond carrier, no real I/O, no
public API. Gap-J remains open; this proof is evidence toward it, not authority over it. Lab
behavior not accepted as canon. This card informs future gate decisions; it does not make them.
