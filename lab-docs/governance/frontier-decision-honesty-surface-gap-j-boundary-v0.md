# Lab Governance Doc: Decision Honesty Surface — Gap-J Research Boundary

**Track:** frontier-decision-honesty-surface-gap-j-boundary-v0
**Card:** FRONTIER-DECISION-P1
**Category:** governance
**Date:** 2026-06-10
**Route:** GOVERNANCE / DESIGN NOTE / NO IMPLEMENTATION
**Status:** CLOSED — design boundary authored; minimal Decision KDR proposed; P2 proof route recommended; nothing implemented, no PROP authored

---

## 1. Problem Statement

Igniter can already be honest about **what it knows** (typed observations, evidence chains,
uncertainty fields, the epistemic state machine) and is becoming honest about **what happened**
(the seven effect outcomes, `unknown_external_state`, reconciliation receipts — the
LAB-EPISTEMIC-OUTCOME arc). It cannot yet be honest about **what it chooses**.

Today a consequential choice in an Igniter program is invisible: the program produces the chosen
action's *effects*, but the choice itself — the alternatives that were viable, why they were
rejected, which constraints shaped the selection, and who or what had the authority to select —
leaves no typed artifact. The Covenant forbids exactly this: *"the language forbids pretending
the choice was simple"* (P24, covenant:226-246), and names the missing shapes —
`StrategyDecision.rejected` (covenant:468), `constraints {}` with `constraint_hash`
(covenant:254-273) — but both are `spec_candidate` under **Gap-J**, with no PROP and zero lab
pressure (LAB-FRONTIER-EXPEDITION-P1, white-space matrix).

This is the **Decide** stage of the accountability loop
`Observe → Estimate → Plan → Decide → Approve → Act → Audit` — the loop's unbuilt center. This
note draws the first design boundary: what a decision artifact must contain *before* any proof or
proposal opens. It implements nothing, adopts no grammar, and authors no PROP.

**Alignment note.** The card's core thesis lists six required exposures. Covenant P24 lists
**seven** (covenant:231-238), adding *expected consequences* and *what cannot be compensated if
wrong*. This boundary follows the canon seven — the design must not be more lenient than the
Covenant it serves.

---

## 2. Terminology

Following PROP-047's discipline (stable terms, forbidden collapses), the decision vocabulary:

| Term | Definition | NOT to be confused with |
|------|------------|--------------------------|
| **option / candidate action** | A concrete action that was *viable at decision time*: permitted by capability, evaluable against constraints | an idea never evaluated (not an option — not recorded) |
| **chosen action** | The single option selected by the decision | the *executed* action (execution is the Act stage; choosing ≠ doing) |
| **rejected alternative** | An option that was viable and was *not* chosen, with a recorded reason | an impossible action (capability-denied options are denials, not rejections) |
| **constraint** | A declared normative or resource boundary (named, kinded, prioritized) that the decision must respect | a preference or scoring weight (constraints bound; scores rank) |
| **constraint application** | The record of *how* a specific constraint bore on *this* decision: satisfied, violated, or waived | the constraint declaration itself (declaration is reusable; application is per-decision) |
| **authority / approver** | The human/agent/system that had the *right to select* among permitted options | capability authority (the right for the action to be *performable* at all — see §6) |
| **evidence basis** | The set of observations/estimates available *at decision time*, each with its epistemic kind (real/model/human) | evidence gathered later (that belongs to audit, not to the decision) |
| **rationale** | The human-readable account of why the chosen option won | a score (a number is an input to rationale, not a substitute for it) |
| **decision receipt** | The typed artifact recording all of the above; evidence, not authority | a permission, a command, or an execution record |
| **audit obligation** | The decision's declared relationship to its future audit (pending / deferred / impossible) — P26 territory | audit itself (Gap-N; out of scope here, carried as an obligation marker only) |

---

## 3. Minimal Decision KDR Shape (proof-local convention; not grammar)

KDR `kind: String` record, in the established convention (PROP-044-P1; same discipline as
`OutcomeEnvelope` / `ReconciliationReceipt`). All field types are already VM-proven in the lab
corpus (String, Integer, `Map[String,String]`, `Collection[Record]` per LAB-TC-ARRAY-P1/P2).

```
DecisionReceipt {
  kind:             String   — "decided" | "decision_deferred" | "decision_escalated" | "no_viable_option"
  decision_id:      String   — stable id; correlates to receipts of the Act stage (required)
  chosen:           ChosenAction        — the selected option; empty-marker when kind ≠ "decided"
  rejected:         Collection[RejectedAlternative]   — MAY be empty only with recorded reason
  constraints:      Collection[ConstraintApplication] — every constraint consulted, incl. satisfied ones
  authority_chain:  Collection[AuthorityLink]         — who proposed / recommended / approved / vetoed
  evidence_refs:    Collection[EvidenceRef]           — what was known at decision time, with epistemic kind
  assumption_refs:  Collection[String]  — opaque refs to declared assumptions (P24 exposure 2; Gap-H semantics NOT adopted)
  rationale:        String   — why the chosen option won (required for kind="decided")
  decided_at:       String   — explicit time input (no ambient now() — Covenant Law 6)
  audit_obligation: String   — "pending" | "deferred" | "impossible"  — carrier only; semantics are Gap-N
  metadata:         Map[String, String]
}

ChosenAction {
  option_id:          String
  expected_outcome:   String   — P24 exposure 6: expected consequences
  uncompensatable:    String   — P24 exposure 7: what cannot be compensated if wrong; "" if none claimed
  evidence_refs:      Collection[String]
}

RejectedAlternative {
  option_id:           String
  expected_outcome:    String   — or score, stringified; what choosing it was predicted to yield
  rejection_reason:    String   — required, never ""
  conflicting_constraint: String — constraint name if rejection was constraint-driven; "" otherwise
  evidence_refs:       Collection[String]
  disposition:         String   — "final" | "deferred" | "escalated"
}

ConstraintApplication {
  name:             String
  kind:             String   — "ethical" | "resource" | "policy" | "safety" | "legal"
  priority:         String   — decimal 0.0–1.0 as string (canon shape, covenant:254-266)
  constraint_hash:  String   — content address of the constraint statement (P25)
  status:           String   — "satisfied" | "violated" | "waived"
  waiver_authority: String   — required non-"" iff status="waived"
  statement:        String
}

AuthorityLink {
  actor_kind: String   — "human" | "agent" | "system"
  actor_id:   String
  role:       String   — e.g. "operator", "reviewer", "policy_engine"
  action:     String   — "proposed" | "recommended" | "approved" | "vetoed"
  basis:      String   — what entitled this actor to this action (role grant, escalation, profile)
}

EvidenceRef {
  ref:           String   — opaque evidence/observation id
  evidence_kind: String   — "real" | "model" | "human"  (P13; same field proven load-bearing in LAB-EPISTEMIC-OUTCOME-P4)
}
```

**The four decision kinds** (mirroring PROP-047 naming discipline):

| kind | meaning | honesty rule |
|------|---------|--------------|
| `decided` | one option chosen | `chosen` populated; `rationale` non-empty; ≥1 approval in `authority_chain` |
| `decision_deferred` | choice postponed | reason in rationale; NOT a failure; NOT silently re-enterable without new evidence |
| `decision_escalated` | sent to a higher authority | target authority recorded; the escalating actor did NOT choose |
| `no_viable_option` | every option constraint-blocked or capability-denied | honest fail-closed terminal — **not** an error and **not** a default selection |

`no_viable_option` is the decision analog of denial-as-data: the absence of a permissible choice is
itself a first-class, typed outcome — never an exception, never a silent fallback to "least bad."

---

## 4. Constraint Surface (minimum proof-local representation)

`ConstraintApplication` above is the per-decision record. Boundary rules:

1. **Declaration ≠ application.** A constraint declaration (name, kind, priority, statement —
   the canon `constraints {}` shape) is reusable context; the *application* (status against this
   decision) is what the receipt records. v0 carries applications only; declarations stay outside
   the receipt, referenced by `name` + `constraint_hash`.
2. **Satisfied constraints are recorded too.** A decision that only records violated constraints
   hides the normative field it operated in. Every *consulted* constraint appears, status
   `satisfied` included. (This is what makes `constraint_hash` audit-meaningful.)
3. **Waiver is explicit and owned.** `status: "waived"` requires `waiver_authority` — a waived
   constraint with no named waiver authority is malformed (fail closed). Waiving is itself an
   exercise of decision authority and must also appear as an `AuthorityLink`.
4. **Priority is data, not arbitration.** v0 records priorities; it does **not** define an
   automatic resolution rule for conflicting constraints. Conflict resolution that overrides a
   higher-priority constraint is representable only as an explicit waiver. No "ethics solver" is
   designed or implied (see §10).
5. **`constraint_hash`** is the content address of the constraint statement (P25:
   "auditable, replayable, content-addressed"). v0 may compute it proof-locally (e.g. SHA-256 of
   the canonical statement string); no canon hashing authority is claimed.

The canon `constraints {}` **grammar is not adopted** — this is record-shape convention only.

---

## 5. Rejected Alternatives (what must be recorded)

Per `RejectedAlternative`: identity, predicted outcome, an always-non-empty `rejection_reason`,
the conflicting constraint when the rejection was constraint-driven, the evidence consulted, and a
`disposition`:

- **`final`** — rejected for this decision; resurrecting it requires a *new* decision.
- **`deferred`** — viable but postponed (e.g. pending evidence); explicitly re-enterable.
- **`escalated`** — this authority could not choose it; routed upward.

Boundary rules:

1. **Rejected means evaluated.** Only options that were *viable and considered* appear. An option
   blocked by capability is a **denial** (the existing denial-as-data law), recorded upstream —
   mixing denials into `rejected` would collapse capability authority into decision authority.
2. **Empty `rejected` demands a reason.** A `decided` receipt with zero rejected alternatives is
   legitimate only when the option space genuinely had one member — and the receipt must say so in
   `rationale`. "We only looked at one option" is itself decision-relevant information.
3. **Scores do not justify.** `expected_outcome`/score is recorded *input*; `rejection_reason` is
   the *account*. A bare "scored lower" is a smell the P2 proof should treat as a degenerate case,
   not a norm (see FC-D5).

---

## 6. Authority Chain — decision authority ≠ capability authority

The two authorities answer different questions and live at different loop stages:

| | **Capability authority** | **Decision authority** |
|---|---|---|
| Question | *may this action be performed at all?* | *who/what may select among permitted options?* |
| Loop stage | gates **Act** (and pre-filters the option space) | constitutes **Decide** (and feeds **Approve**) |
| Existing surface | capabilities, passports, delegation algebra, denial-as-data (built, 10+ proofs) | **nothing** (this boundary) |
| Failure mode | `denied` — option never viable | `vetoed` / `decision_escalated` / `no_viable_option` |
| Receipt role | evidence the gate ran | evidence the *choice* was owned |

`AuthorityLink.action` separates the four roles a participant can play: `proposed` (put an option
on the table), `recommended` (ranked/suggested — **this is where a model output lives**),
`approved` (exercised decision authority), `vetoed` (exercised blocking authority).

**Actor-kind rule (the agent-era seam).** Consistent with P13 and No-Upward-Coercion, and with the
LAB-EPISTEMIC-OUTCOME-P4 proof that `evidence_kind:"model"` cannot reach `accept`:

- an `agent` actor may `propose` and `recommend`;
- a `decided` receipt whose **only** approval links have `actor_kind:"agent"` is permissible *only
  when* the decision's evidence basis contains no `model`-kind upgrade requirement — in v0,
  conservatively: **an agent-only approval over model-kind evidence routes to
  `decision_escalated`, not `decided`**. The human-review gate that would relax this is
  FRONTIER-HUMAN-GATE territory, not designed here;
- `system` approval represents pre-authorized policy (e.g. a profile-bound rule) and must name its
  `basis`.

This boundary **does not** claim agent autonomy semantics; it only ensures the receipt cannot
*hide* who chose.

---

## 7. Relationship to Existing Arcs

| Arc | Composition |
|-----|-------------|
| **Epistemic outcome / unknown state** (LAB-EPISTEMIC-OUTCOME-P1..P4) | A decision consumes evidence with epistemic states. Deciding *as if* an `unknown_external_state` were resolved is an upward coercion — the receipt makes it visible (`evidence_kind` on every ref, the proven P4 mechanism). Conversely, the reconciliation consumer's `needs_human_review` terminal is precisely a `decision_escalated` waiting for this surface. |
| **Failure taxonomy (PROP-047)** | Decision kinds occupy a **separate namespace** from outcome kinds (analog of PROP-047 axis 10: a decision record is not a failure outcome). `no_viable_option` ≠ `failed`. Naming here follows PROP-047 conventions (lower_snake, observed-vs-unknown discipline). |
| **Receipt-as-evidence design law** | `DecisionReceipt` is the law's next instance: it *records* the choice, it does not *authorize* execution. Approval inside the chain is evidence that authority was exercised — the Act stage still passes capability gates independently. |
| **Deterministic replay** (LAB-CONCURRENCY-P3, B4) | `constraint_hash` + `evidence_refs` + `decided_at` + `assumption_refs` make a decision **replayable in its original epistemic context**: "what did the system know and respect when it chose?" answered by re-evaluation, not by logs. The receipt is the unit of decision replay. |
| **Query/Storage receipts** (`QueryExecutionReceipt`, 15-field) | Those receipts prove *gates ran*; a DecisionReceipt proves *a selection was owned*. The P2 domain (below) deliberately stacks them: capability receipts upstream, decision receipt at the center. |
| **Audit closure (Gap-N, future)** | `audit_obligation` is the forward hook: P26 says a decision is incomplete until audited or explicitly excused. v0 carries the marker; FRONTIER-AUDIT owns its semantics. A `PostAuditReceipt` will reference `decision_id` and compare `chosen.expected_outcome` against observed outcome — the fields are shaped for that join. |

---

## 8. Forbidden Collapses (FC-D1..FC-D9)

In PROP-047 style — each collapse names a dishonesty the shape must make impossible to hide:

| # | Rule | Why |
|---|------|-----|
| FC-D1 | **chosen ≠ authorized** | selection and approval are different acts; a receipt with `chosen` but no `approved` link is incomplete, not implicitly approved |
| FC-D2 | **authorized ≠ executed** | approval is Decide/Approve-stage evidence; execution is Act-stage with its own capability gates and outcome receipt |
| FC-D3 | **rejected ≠ impossible** | rejected = viable-but-not-chosen; impossible = capability-denied (upstream denial-as-data); merging them hides either the denial or the choice |
| FC-D4 | **constraint waived ≠ constraint absent** | a waiver is a recorded act with a named authority; deleting the constraint from the receipt is falsification |
| FC-D5 | **highest score ≠ justified choice** | a score is input; `rationale` + constraint applications are the justification; "argmax" alone is not an account |
| FC-D6 | **model recommendation ≠ human approval** | an `agent`/`recommended` link can never be read as an `approved` link (P13 / No-Upward-Coercion, §6) |
| FC-D7 | **receipt evidence ≠ authority** | the design law: recording a decision grants nothing |
| FC-D8 | **deferred ≠ decided** | `decision_deferred` must not flow into Act; consuming a deferred receipt as if chosen is forbidden |
| FC-D9 | **no_viable_option ≠ failure, ≠ default pick** | the empty-choice terminal is honest data; silently selecting "least bad" under it is the collapse this whole surface exists to prevent |

---

## 9. Candidate Proof Route — FRONTIER-DECISION-P2

**Recommended domain: query-plan selection under cost/safety constraints.**

Shape: two viable `QueryPlan`s for the same question (e.g. a broad scan vs a filtered, limited
plan). Constraints: `row_budget` (kind `resource`, from `row_limit` semantics), `no_include_all`
(kind `policy`/`safety`, from the `allow_include_all` gate). A chooser produces a `DecisionReceipt`:
one plan `chosen` with rationale, the other `rejected` with `conflicting_constraint`; constraint
applications include the *satisfied* ones; authority chain has a `system` policy approval. Negative
paths: both plans violate → `no_viable_option`; waiver path → `waived` + `waiver_authority`;
model-recommended plan with agent-only approval → `decision_escalated` (FC-D6 behaviorally proved).

**Why this domain (over the alternatives):**
- **Builds on the densest existing corpus** — `QueryPlan`/`QueryResult` records are VM-proven
  (LAB-QUERY-P1..P3, LAB-EXECUTE-QUERY-P1..P3, LAB-TC-ARRAY-P1/P2 give `Collection[Record]`); the
  fixture is pure CORE contracts + the established three-layer proof pattern — no new I/O, no new
  runtime surface.
- **It separates the two authorities sharply** — StorageCapability (capability authority) already
  exists in this exact domain, so the proof can *show* a capability-permitted option being
  decision-rejected, and a capability-denied option correctly *not* appearing in `rejected` (FC-D3).
- **Constraints are real, not staged** — row budgets and include-all policy are genuine, already-
  proven gates, recast as decision constraints rather than invented ethics examples.
- The **agent/human review** domain is the most strategically interesting (B3) but depends on the
  human-gate primitive that FRONTIER-HUMAN-GATE has not designed — premature here, and §6's
  escalation rule covers the seam until then. The **retry decision** domain is largely proven
  inside the epistemic arc already (P16-gated routing). The **storage adapter policy** domain is a
  thinner twin of query-plan selection.

P2 proof expectations (sketch): Layer A Ruby TC type shapes; Layer B Rust VM — receipt produced,
carried, routed (the four kinds drive consumer branching as in P4); Layer C consumer sim for the
FC-D rules; regression: existing proofs untouched.

---

## 10. Closed Surfaces (no route opens these here)

- **No grammar adoption** — no `constraints {}` syntax, no decision syntax, no parser changes.
- **No `StrategyDecision` canon type** — the KDR shape is proof-local convention; the canon name
  stays reserved to the Covenant until a Gap-J PROP (not authored here) claims it.
- **No compiler / typechecker / VM / runtime changes.**
- **No public/stable API**; all shapes are lab-volatile.
- **No automatic ethical reasoning claim** — recording `kind: "ethical"` constraints is honesty
  bookkeeping; no solver, no arbitration rule, no moral semantics are designed or implied.
- **No agent autonomy claim** — §6 restricts what receipts can *hide*; it grants agents nothing.
- **No audit closure** — `audit_obligation` is a carrier field; Gap-N semantics belong to
  FRONTIER-AUDIT.
- **No Gap-H adoption** — `assumption_refs` are opaque strings; assumption semantics stay in Gap-H.
- **No PROP authored**; Gap-J remains open; this note is evidence toward it, not authority over it.

---

## Gap Packet

```
note:       frontier-decision-honesty-surface-gap-j-boundary / v0
status:     CLOSED — design boundary; nothing implemented; no PROP
authority:  governance / lab_only
date:       2026-06-10

problem:    Igniter honest about knowing + (increasingly) about outcomes; NOT yet about choosing.
            Gap-J (P24/P25) = the Decide stage; spec_candidate, zero lab pressure.
canon_alignment: follows P24's SEVEN exposures (card listed six; added expected_consequences +
            uncompensatable via ChosenAction fields)

kdr_shape:  DecisionReceipt (kind: decided|decision_deferred|decision_escalated|no_viable_option;
            decision_id, chosen:ChosenAction, rejected:[RejectedAlternative],
            constraints:[ConstraintApplication], authority_chain:[AuthorityLink],
            evidence_refs:[EvidenceRef w/ evidence_kind], assumption_refs, rationale,
            decided_at, audit_obligation(carrier), metadata) — all field types VM-proven in corpus

constraint_rules: declaration≠application; satisfied constraints recorded; waiver requires named
            waiver_authority + AuthorityLink; priority=data not arbitration; hash=content address
rejected_rules:   rejected=evaluated (denied options excluded); empty-rejected needs reason;
            disposition final|deferred|escalated; score≠justification
authority:  capability authority (may it be done) ≠ decision authority (who chose);
            actions proposed|recommended|approved|vetoed; agent may propose/recommend;
            agent-only approval over model evidence → decision_escalated (human gate = future card)

forbidden_collapses: FC-D1 chosen≠authorized | FC-D2 authorized≠executed | FC-D3 rejected≠impossible
            | FC-D4 waived≠absent | FC-D5 score≠justification | FC-D6 recommendation≠approval
            | FC-D7 receipt≠authority | FC-D8 deferred≠decided | FC-D9 no_viable_option≠failure/default

p2_route:   FRONTIER-DECISION-P2 = query-plan selection under cost/safety constraints
            (densest corpus; capability-vs-decision authority shown sharply; real constraints;
            negative paths: no_viable_option, waiver, model-recommendation escalation)

closed:     grammar | constraints{} syntax | StrategyDecision canon type | compiler/VM |
            public API | ethical-reasoning claim | agent-autonomy claim | audit closure (Gap-N) |
            Gap-H semantics | PROP authoring
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Design note only: no code,
grammar, parser, typechecker, VM, or runtime changes; no PROP authored; Gap-J remains open. The
`StrategyDecision` and `constraints {}` canon names remain the Covenant's; this note proposes
proof-local KDR conventions only. No automatic ethical reasoning and no agent autonomy are claimed
or implied. Ch12 and other proposed surfaces phrased as proposed, not accepted canon. Lab behavior
not accepted as canon. This note informs future gate decisions; it does not make them.
