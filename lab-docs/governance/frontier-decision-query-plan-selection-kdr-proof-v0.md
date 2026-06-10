# Lab Governance Doc: Query-Plan Selection Decision KDR Proof

**Track:** frontier-decision-query-plan-selection-kdr-proof-v0
**Card:** FRONTIER-DECISION-P2
**Category:** governance
**Date:** 2026-06-10
**Route:** LAB PROOF / DECISION HONESTY / GAP-J PRESSURE
**Status:** CLOSED — 72/72 PASS; DecisionReceipt KDR produced, carried, and routed in the lab VM; no promotion authorized

---

## Purpose

First lab pressure on **Gap-J** (Covenant P24/P25 — the Decide stage). FRONTIER-DECISION-P1 drew
the design boundary; **P2 proves the `DecisionReceipt` KDR surface is executable today**: a
decision between QueryPlans under resource (`row_budget`) and policy/safety (`no_include_all`)
constraints is produced as a typed record in the lab Rust VM, carries all seven P24 exposures, and
drives consumer routing — with every forbidden collapse (FC-D1..FC-D9) behaviorally rejected.

KDR convention only. No `constraints {}` grammar, no `StrategyDecision` canon type, no
variant/match, no real storage/SQL/DB/network I/O, no PROP. Lab-only evidence toward a future
Gap-J PROP; not authority over it.

---

## What Was Built

| Artifact | Path |
|----------|------|
| Fixture (6 types, 7 contracts) | `igniter-view-engine/fixtures/frontier_decision/query_plan_decision.ig` |
| Proof runner (72 checks) | `igniter-view-engine/proofs/verify_frontier_decision_p2.rb` |
| This doc | `lab-docs/governance/frontier-decision-query-plan-selection-kdr-proof-v0.md` |
| Card | `.agents/work/cards/governance/FRONTIER-DECISION-P2.md` |

**Types** (exactly the P1 shapes): `DecisionReceipt` (12 fields — KDR `kind` + nested
`ChosenAction` + 4 collections + `Map` metadata), `ChosenAction` (with P24 exposures 6+7:
`expected_outcome`, `uncompensatable`), `RejectedAlternative`, `ConstraintApplication`,
`AuthorityLink`, `EvidenceRef` (with `evidence_kind`).

**Contracts:** `MakeDecisionReceipt` (producer — proves nested-record + multi-collection
construction in VM), `DecideKindGuard` (the P1 kind rules as in-VM branching), `WaiverGuard`,
`JustificationGuard`, `ClassifyOption` (capability-vs-decision split), `RouteDecision` (consumer),
`ReceiptInspector` (map chain).

**Proof architecture** — the established three layers (same documented Ruby/Rust `==` divergence
as LAB-EPISTEMIC-OUTCOME-P4): Layer A Ruby TC proves the 6 record types + producer/inspector
accepted (guards Ruby-blocked, Rust-executed); Layer B Rust compiler+VM executes construction,
guard logic, and routing; Layer C checks the FC-D rules over VM outputs.

---

## What the VM Proved

### The decided path (P24 seven exposures, end-to-end)

A full 12-field receipt constructed in the VM: `plan_filtered` chosen (with `expected_outcome` and
`uncompensatable`), **two** constraint-driven rejections (`plan_include_all` ←
`no_include_all`; `plan_broad` ← `row_budget`, each with non-empty `rejection_reason`, own
evidence refs, closed-set disposition), **satisfied constraints recorded** (not only violated —
the receipt shows the normative field it operated in), authority chain with agent
`recommended` + system `approved`, mixed real/model `EvidenceRef`s preserved, non-empty rationale,
explicit `decided_at` (no ambient time), opaque `assumption_refs`, `audit_obligation:"pending"`
carrier. (FDEC-DECIDED-01..08, FDEC-REJECT-01..05.)

### The two authorities, separated (FC-D3)

`ClassifyOption`: capability-denied option → `denied_upstream` (denial-as-data, excluded from the
viable set) and **absent from `rejected`**; meanwhile a capability-*permitted* option
(`plan_broad`) is decision-rejected. Capability authority ("may it be done") and decision
authority ("who chose among the permitted") are demonstrably different gates.
(FDEC-AUTHORITY-01..05.)

### The kind guard (P1 rules as executable VM logic)

| inputs | VM kind |
|--------|---------|
| viable_count=0 (even with pending evidence) | `no_viable_option` |
| pending evidence | `decision_deferred` |
| no approval at all | `decision_escalated` (**FC-D1: chosen ≠ authorized**) |
| model evidence + agent approval | `decision_escalated` (**FC-D6**) |
| model evidence + system approval | `decision_escalated` (v0-conservative; human-gate future) |
| model evidence + **human** approval | `decided` (the sanctioned upgrade path) |
| real evidence + agent approval | `decided` (escalation rule scoped to model evidence) |

### Routing, waiver, score (FC-D4/5/7/8/9)

`RouteDecision` in VM: `decided→execute_plan`, `decision_deferred→wait`,
`decision_escalated→human_review`, `no_viable_option→stop`, unknown→`hold` (fail closed); the
output is data, not an execution (FC-D7). `no_viable_option` receipt has an **empty chosen** — no
default pick (FC-D9) — and is neither `failed` nor `deferred`. Waiver: valid waiver recorded with
named authority, **still present** in the constraints list (FC-D4), waiver actor also in the
authority chain; waiver with empty authority → `invalid_waiver_escalate` (an authority question
escalates; the constraint is never silently dropped). `JustificationGuard`: top score with empty
rationale → `insufficient_justification` (FC-D5 — argmax is not an account).

---

## Acceptance Checklist (card-required)

| Requirement | Result |
|-------------|--------|
| PASS runner, ~60–90 checks | ✅ **72/72** |
| DecisionReceipt KDR produced and VM-routed | ✅ (FDEC-DECIDED, FDEC-ROUTE) |
| chosen/rejected/constraints/authority/evidence represented | ✅ |
| P24 seven exposures present | ✅ (incl. expected_outcome + uncompensatable) |
| Satisfied constraints recorded, not only violated | ✅ FDEC-DECIDED-04 |
| no_viable_option proven | ✅ FDEC-NVO-01..04 (empty chosen; ≠failed; ≠deferred) |
| model-recommendation escalation proven | ✅ FDEC-EVIDENCE-03, FDEC-KINDGUARD-04 |
| waiver behavior proven (incl. invalid-waiver fail-closed) | ✅ FDEC-WAIVER-01..06 — invalid waiver **escalates** (justification: a waiver with no named authority is an authority question; silently dropping the constraint would be FC-D4, silently proceeding would forge a waiver) |
| capability-denied NOT collapsed into rejected | ✅ FDEC-AUTHORITY-03 |
| no implementation/canon/PROP authority claimed | ✅ FDEC-CLOSED-01..08 |
| regression | EPISTEMIC-P2 54/54, EPISTEMIC-P4 46/46 green; only new files added |

---

## Findings & Notes

1. **The Gap-J surface is VM-executable today with zero new substrate.** The 12-field receipt with
   a nested record and four collections of records constructed and round-tripped cleanly — the
   LAB-TC-ARRAY-P1/P2 + LAB-RECORD-VM groundwork made this a first-run pass (72/72 with no fixture
   iteration).
2. **Decision kinds and outcome kinds coexist without collision** (PROP-047 axis-10 analog held:
   the fixture uses no `failed`/`succeeded`/`unknown_external_state` literals; FDEC-CLOSED-08).
3. **The v0-conservative escalation rule is now behavioral law in the lab:** over model-kind
   evidence only a human approval decides; agent **and system** approvals escalate. Whether
   pre-authorized system policy may decide over model evidence is explicitly deferred to
   FRONTIER-HUMAN-GATE.
4. **Known divergence carried forward, not hidden:** guard/router contracts are Ruby-TC-blocked
   (String `==`) and Rust-VM-executed — same STAB-P4-flagged operator drift as P4. A future
   variant/match lowering (Path B, now unblocked by LAB-VARIANT-RUST-P1) would route these on arms.

---

## Next Route Recommendation

P2 found **no gaps in the KDR surface itself** — every required positive, negative, and
forbidden-collapse case passed, first run. Therefore:

- **Recommended: FRONTIER-DECISION-PROP-READINESS** — the surface is clean; map what a Gap-J PROP
  needs (canon naming: `StrategyDecision` vs lab `DecisionReceipt`; constraints{} grammar
  requirements; relationship to PROP-047 namespaces and to the variant/match substrate; what
  stays convention vs what needs grammar).
- **FRONTIER-DECISION-P3 (VM hardening)** — *not needed now*; no multi-branch edge gaps surfaced.
  Reopen only if PROP-readiness work finds behavioral holes.
- **FRONTIER-HUMAN-GATE-P1** — the model→human approval seam is now load-bearing in two arcs
  (epistemic P4 + this proof); it is the natural parallel track, and the system-over-model
  question is parked on it.

**Closed (unchanged):** grammar; `constraints{}` syntax; `StrategyDecision` canon type;
compiler/parser/VM changes; PROP authoring; automatic ethical reasoning; agent autonomy; audit
closure beyond the carrier field; real storage I/O; public/stable API.

---

## Gap Packet

```
proof:      frontier-decision-query-plan-selection-kdr-proof / v0
status:     CLOSED — 72/72 PASS (first full run; no fixture iteration needed)
authority:  governance / lab_only
date:       2026-06-10
domain:     query-plan selection under row_budget (resource) + no_include_all (policy/safety)

surface:    DecisionReceipt KDR 12-field (nested ChosenAction + 4 Collections + Map) — VM-constructed
kinds:      decided | decision_deferred | decision_escalated | no_viable_option (≠ outcome kinds)
exposures:  P24 all seven (incl. expected_outcome + uncompensatable)

vm_proved:
  decided path w/ satisfied constraints recorded + agent-recommended/system-approved chain
  constraint-driven rejections (no_include_all, row_budget) w/ reasons + dispositions
  capability-denied → denied_upstream, EXCLUDED from rejected (FC-D3); permitted-yet-rejected shown
  kind guard: nvo | deferred | none→escalated (FC-D1) | model+agent/system→escalated (FC-D6) |
              model+human→decided | real+agent→decided | nvo wins over pending
  routing: execute_plan/wait/human_review/stop + unknown→hold fail-closed; output=data (FC-D7)
  nvo: empty chosen (FC-D9), ≠failed, ≠deferred
  waiver: recorded w/ named authority, still listed (FC-D4); empty authority→escalate
  score: argmax+empty rationale→insufficient_justification (FC-D5)

layering:   Ruby TC accepts types+producer/inspector; guards Ruby-blocked (== divergence, STAB-P4),
            Rust VM executes — same documented split as LAB-EPISTEMIC-OUTCOME-P4
regression: EPISTEMIC-P2 54/54 | EPISTEMIC-P4 46/46 | git: only new files
closed:     grammar | constraints{} | StrategyDecision canon | compiler/VM | PROP | ethics-engine |
            agent autonomy | audit semantics | real IO | public API
next:       FRONTIER-DECISION-PROP-READINESS (surface clean; P3 hardening not needed)
            parallel: FRONTIER-HUMAN-GATE-P1 (system-over-model question parked there)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only; no grammar,
no `constraints{}` syntax, no `StrategyDecision` canon type, no compiler/parser/VM changes, no PROP
authored, no automatic ethical reasoning, no agent autonomy, no audit-closure semantics beyond the
carrier field, no real storage/SQL/DB/network I/O, no public/stable API. Gap-J remains open; this
proof is evidence toward it. Lab behavior not accepted as canon. This doc informs future gate
decisions; it does not make them.
