# Lab Report: Frontier Expedition — Insights & Breakthrough-Concept Candidates

**Track:** lab-frontier-expedition-insights-and-breakthrough-concepts-v0 (out-of-track research)
**Card:** LAB-FRONTIER-EXPEDITION-P1
**Category:** governance
**Date:** 2026-06-10
**Route:** REPORT / RESEARCH ANALYSIS / LAB-ONLY / NO CODE CHANGES / NO IMPLEMENTATION AUTHORITY
**Status:** CLOSED — analysis complete; 7 insights, 6 breakthrough-concept candidates, 5 proposed expeditions; nothing authorized

---

## Method

Three parallel sweeps over the corpus, read-only: (1) every canon spec chapter
(`igniter-lang/docs/spec/ch1..ch13`), (2) the full Covenant including the complete P1–P28
enforcement registry, Gap registry (Gap-H/J/N), and OQ list, (3) the lab corpus white-space scan
(what canon declares that the lab has never pressed). Grounded against the live arcs this
governance track already closed (LAB-EPISTEMIC-OUTCOME-P1..P4, PROP-044-P7-READINESS,
LAB-DEBUGGER-FEASIBILITY-P1). No code or canon was changed; this is a map, not a route order.

---

## Insight 1 — The language's identity is already a breakthrough, and it is *underclaimed*

Ch1 names it plainly: Igniter is an **Epistemic Contract Language** — "every computation is a
declared, observable, time-aware dependency graph." The Covenant operationalizes this as the
**Four Axes of Honesty** (epistemic / effect / constraint / audit, covenant:349-372) and the
**Honest Computing Doctrine**: "the compiler is not only a correctness checker; it is an honesty
checker," with a 13-row table of things the language refuses to let a program hide (consequence,
uncertainty, authority, simulation, mutation, irreversibility, ambiguity, provenance, assumptions,
synthetic worlds, constraints, rejected alternatives, audit gaps).

**The insight:** mainstream language design competes on *expressiveness, performance, safety-from-
crashes*. Igniter competes on a fourth axis almost nobody occupies: **safety-from-dishonesty** —
legibility of consequence, certainty, and authority. That is not a feature list; it is a different
*genre* of language. Every frontier expedition below should be selected by one question: *does it
deepen the honesty moat?*

## Insight 2 — The Accountability Loop is half-built, and the missing half is the point

The Covenant's canonical pipeline is `Observe → Estimate → Plan → Decide → Approve → Act → Audit`
(covenant:283-285, 361-372). Mapping the P1–P28 enforcement registry onto that loop exposes a
sharp asymmetry:

| Loop stage | Honesty axis | Enforcement today |
|------------|--------------|-------------------|
| Observe / Estimate / Plan | epistemic | **largely built** — P1/P2/P3/P5/P13/P18 `enforced`; P22 assumptions syntax `experiment-pass` |
| **Decide** (constraints, rejected alternatives) | constraint | **spec_candidate only** — P24/P25, Gap-J, no PROP exists |
| **Approve** (authority as typed value) | effect | `planned PROP` — P9 declared, unenforced |
| **Act** (effect surface, outcomes, compensation) | effect | `planned PROP` — P15/P16/P17/P21 (our epistemic-outcome arc is the live pressure here) |
| **Audit** (PostAuditReceipt, audit: deferred/impossible) | audit | **spec_candidate only** — P26, Gap-N, no PROP exists |

**The insight:** *Igniter can currently be honest about what it knows, but not yet about what it
chooses or what happened afterwards.* The three named architectural holes — **Gap-H** (assumptions
semantics + synthetic worlds), **Gap-J** (constraints + choice exposure), **Gap-N** (audit
closure) — are precisely the back half of the loop. This is an **enforcement inversion**: the
postulates most central to the language's reason-to-exist (P22–P26) are the least built, while the
mechanical ones (P1/P2/P5) are fully enforced. The frontier is not at the edge of the language —
it is at its center.

## Insight 3 — Igniter is accidentally(?) the first *agent-era accountability substrate*

Assemble what canon already declares about models and humans:

- **P13 (enforced):** observations are typed `real | model | human` — a model observation cannot be
  used as a real one without explicit conversion.
- **P11:** a model output is "an observation, not a fact"; `uncertainty_m`/`confidence` are
  *required, not optional* fields; uncertainty cannot be silently discarded.
- **No-Upward-Coercion (covenant:391-403):** `estimated → known` and `inferred → fact` are
  forbidden without explicit typed conversion **or human review**.
- **P24 choice exposure:** every consequential decision must expose *who authorized it* and *what
  alternatives were rejected*.
- And this lab has the first **executable** evidence: LAB-EPISTEMIC-OUTCOME-P4 ran
  `evidence_kind:"model"` → `needs_human_review` (never `accept`) **in the VM**, and the
  variant/match arc made that routing a typed arm rather than a string convention.

**The insight:** read together, this is a language where **an LLM/agent output is epistemically
quarantined by the type system** — it enters as a typed `model` observation with mandatory
uncertainty, cannot be promoted to fact without a typed conversion or a human gate, and any
consequential action it triggers must carry an authority chain and rejected alternatives. No
mainstream language or agent framework offers this *in the semantics* (they offer it, at best, in
process). In 2026 this is arguably Igniter's single most marketable breakthrough — and it is
~70% declared, ~20% built. The missing piece is the **human-review gate as a language primitive**
(today `needs_human_review` is a routing destination with no contract surface behind it).

## Insight 4 — "Receipt is evidence, not authority" has quietly become a design law

The same invariant now appears independently across at least five domains: capability decisions
(denial-as-data, 10 proofs), `QueryExecutionReceipt` ("receipt is evidence only; does not
re-authorize"), scheduling receipts (LAB-CONCURRENCY-P3: deterministic, replay-verifiable,
"evidence-only, not a production mechanism"), `JobReceipt`, and our `ReconciliationReceipt`. This
mirrors how denial-as-data was recognized: a pattern repeated without coordination across domains
is a design-law candidate.

**The insight + latent breakthrough:** LAB-CONCURRENCY-P3 proved **receipt determinism with
re-execution parity** — a receipt of a scheduled run can be *replayed and verified* (10-gate
validation incl. graph digest, policy digest, wave correctness, result digest). Combine that with
`program_id`/`source_hash` identity (ch6), explicit time (no ambient `now()`), and the bitemporal
TBackend (which *actually exists*: WAL, 128 shards, `as_of` reads) — and Igniter is most of the way
to **deterministic, auditable, replayable execution** as a platform property. That is the
substrate for: time-travel debugging (cf. LAB-DEBUGGER-FEASIBILITY-P1), reproducible distributed
scheduling, and *audit-grade replay of any past decision in its original epistemic context* —
"what did the system know when it decided?" answered by re-execution, not by logs.

## Insight 5 — Shadow production is a third verification mode, and it is the go-to-market

`igniter-sparkcrm-shadow.md` defines the pattern: shadow store captures real production facts
fire-and-forget; the same `.ig` contracts that served as lab fixtures execute against real data;
accuracy is measured against production truth. The doc's own phrasing: *"when shadow accuracy
reaches 99% — this is the moment when igniter stops being an experiment and becomes an
alternative."*

**The insight:** this is neither unit testing nor integration testing — it is **production
evidence collection**, the same epistemology the lab already uses (proofs as evidence, not
authority) extended to deployment. It composes with the epistemic-outcome arc directly: a shadow
system is *the* place where `unknown_external_state`, reconciliation, and audit receipts earn
their keep against reality. Strategically: the shadow path turns adoption itself into an
evidence-gathering exercise — perfectly aligned with the Covenant.

## Insight 6 — The white-space matrix: declared, shaped, and never once pressed

The lab corpus has **zero fixtures** exercising these canon-declared constructs:

| Construct | Canon status | Lab pressure |
|-----------|-------------|--------------|
| `constraints {}` (kind `:ethical`/`:resource`, priority, `constraint_hash`) | spec_candidate (Gap-J) | **ABSENT** |
| `StrategyDecision` with `rejected` alternatives (P24) | spec_candidate (Gap-J) | **ABSENT** |
| `SimulationReceipt` (`mode: :synthetic`, `honesty_statement`, `assumption_hash`) (P23) | spec_candidate (Gap-H) | **ABSENT** |
| `PostAuditReceipt` / `audit: :deferred | :impossible` (P26) | spec_candidate (Gap-N) | **ABSENT** |
| `assumptions {}` flowing through `evidence []` chains (P22) | syntax experiment-pass; carrying unbuilt | **ABSENT in fixtures** |
| `History[T]` / `BiHistory[T]` as types (vs TBackend queries) | Stage-2 reserved | **ABSENT** |
| Convergence loops; cancellation profile prop | proposed | **ABSENT** |
| Human-review gate behind `needs_human_review` | implied by P13/P24 | **ABSENT** (routing arm only) |
| `~T` probabilistic types | Stage-3 reserved (PROP-026) | **ABSENT** (uncertainty modeled as variant arms instead) |

Meanwhile several "exotic" features are **further along than canon admits**: `fold_stream` is fully
implemented through parser/classifier/typechecker/VM (`OP_MAP_REDUCE`); the bitemporal TBackend
runs with WAL and `as_of`; the forms system closed all 6 open questions with auditable
`form_resolution_trace` artifacts; checkpoint/resume exists in the machine image.

**The insight:** the cheapest high-value frontier moves are not inventions — they are **first
pressure** on already-shaped constructs, using the now-proven expedition template:
*design note → KDR convention proof → VM proof → readiness map* (the exact arc
LAB-EPISTEMIC-OUTCOME-P1→P4 + P7-READINESS just executed, which also de-risked the method itself).

## Insight 7 — Unique-concept shortlist (things ~no other language has)

From the full spec sweep, the constructs with no mainstream analog, ranked:

1. **Epistemic state machine with No-Upward-Coercion as a type rule** (observed/inferred/estimated/
   assumed/simulated/decided/executed/audited).
2. **Choice honesty** — `StrategyDecision.rejected`: the receipt must contain the alternatives that
   were *not* taken, with rationale and authority chain (P24).
3. **Declarative normative constraints** — `constraint { kind :ethical, priority 0.95 }` entering
   receipts via `constraint_hash` (P25): ethics as a typed, hashable, auditable artifact.
4. **Audit debt as a language concept** — a decision is incomplete until audited or explicitly
   `audit: :deferred/:impossible` (P26): "a decision that produces no feedback is an
   accountability debt."
5. **Reversibility scale as effect algebra** (reversible < compensatable < refundable < append_only
   < irreversible < destructive) with profile-declared maxima.
6. **Bitemporal types + temporal cache-key algebra** (`BiHistory[vt,tt]`, freshness as
   `fresh|stale|unknown|provisional` — note: *the cache itself speaks our epistemic vocabulary*).
7. **Synthetic-world quarantine** — a simulation must carry an `honesty_statement` and can never
   type-check where reality is expected (P23).

Numbers 2–4 and 7 are entirely unbuilt — they are the frontier.

---

## Breakthrough-Concept Candidates (B1–B6)

| # | Concept | One-line formulation | Builds on | Status |
|---|---------|----------------------|-----------|--------|
| **B1** | **Decision honesty surface** | `constraints {}` + `StrategyDecision.rejected` + authority chain: the first language where *the road not taken* is a typed, mandatory part of the artifact | Gap-J, P24/P25 | declared, zero pressure |
| **B2** | **Audit-closure semantics** | decisions carry their future audit as a typed obligation (`audit:` ref / deferred / impossible) — accountability debt visible at compile time | Gap-N, P26 | declared, zero pressure |
| **B3** | **Agent accountability substrate** | LLM/agent outputs epistemically quarantined: typed `model` observations + mandatory uncertainty + human-review gate as a contract primitive | P11/P13 + our P4 `evidence_kind` proof | ~70% declared, gate missing |
| **B4** | **Deterministic replay platform** | receipts + program identity + explicit time + bitemporal store ⇒ any past run re-executable in its original epistemic context (debugger, audit, distributed scheduling) | LAB-CONCURRENCY-P3, ch6/ch7, TBackend, LAB-DEBUGGER-FEASIBILITY-P1 | parts proven separately, never composed |
| **B5** | **Synthetic-world quarantine** | simulations/generated data carry `honesty_statement` + `assumption_hash` and cannot type as reality — the training-data/simulation provenance problem, solved in the semantics | Gap-H, P23 | declared, zero pressure |
| **B6** | **Shadow-production epistemology** | adoption = evidence collection: shadow contracts vs production truth, accuracy as the promotion gate | sparkcrm-shadow, TBackend | pattern defined, Phase 2 |

---

## Proposed Expeditions (none authorized — candidates for the next походы)

Ordered by (honesty-moat value × readiness), each using the proven P1→P4 template:

1. **FRONTIER-DECISION (B1, Gap-J):** the decision-honesty arc — taxonomy note → KDR
   `StrategyDecision`/`constraints` convention proof → VM routing proof → Gap-J PROP-readiness.
   *Why first: it is the loop's missing center, the most "no other language has this" candidate,
   and structurally identical to the epistemic-outcome arc we just completed.*
2. **FRONTIER-AUDIT (B2, Gap-N):** audit-closure arc — `PostAuditReceipt` KDR + the
   expected-vs-actual comparison contract + `audit: deferred/impossible` honesty terminal.
   *Natural sequel: P4's reconciliation receipts are already half of an audit receipt.*
3. **FRONTIER-HUMAN-GATE (B3):** design the human-review gate behind `needs_human_review` — a
   typed approval contract (who, on what evidence, upgrading what to what) that operationalizes
   No-Upward-Coercion's "or human review" clause. *Smallest scope, highest agent-era relevance.*
4. **FRONTIER-REPLAY (B4):** composition probe — can a recorded scheduling receipt + TBackend
   `as_of` + (future) trace/srcmap actually re-execute a past decision bit-identically? Readiness
   map first (the LAB-DEBUGGER G-SRCMAP/G-TRACE gaps are on this critical path).
5. **FRONTIER-SYNTHETIC (B5, Gap-H):** synthetic-world quarantine KDR proof — a
   `SimulationReceipt` that flows through the VM and *fails closed* when offered where a real
   receipt is expected (the simulation analog of denial-as-data).

**Recommended first move: FRONTIER-DECISION.** It converts the language's sharpest unbuilt idea
into lab evidence with a methodology that is now proven four times over.

---

## Gap Packet

```
report:     igniter-frontier-expedition-insights-and-breakthrough-concepts / v0
status:     CLOSED — analysis complete; nothing authorized
authority:  governance / lab_only
date:       2026-06-10
method:     3 read-only sweeps (spec ch1..ch13 full; Covenant P1–P28 + Gap-H/J/N + OQ; lab white-space)

insights:
  I1  identity = Epistemic Contract Language; competes on safety-from-dishonesty (4th axis)
  I2  Accountability Loop half-built: front (observe/estimate) enforced, back (decide/audit) spec-only
      — enforcement inversion: the central postulates (P22–P26) are the least built
  I3  agent-era substrate: model obs typed+quarantined+human-gated — ~70% declared, gate missing
  I4  "receipt = evidence not authority" repeated in 5 domains → design-law candidate;
      + receipt determinism (CONCURRENCY-P3) + program identity + TBackend ⇒ deterministic replay latent
  I5  shadow production = third verification mode; adoption as evidence collection
  I6  white space: constraints{}/StrategyDecision/SimulationReceipt/PostAuditReceipt/History[T]/
      convergence/cancellation/human-gate = ZERO lab pressure; fold_stream/TBackend/forms ahead of canon
  I7  unique-concept shortlist: choice honesty, audit debt, ethical constraints, synthetic quarantine

breakthrough_candidates: B1 decision-honesty | B2 audit-closure | B3 agent-accountability |
                         B4 deterministic-replay | B5 synthetic-quarantine | B6 shadow-epistemology

expeditions_proposed (NONE authorized):
  1 FRONTIER-DECISION (Gap-J, recommended first) | 2 FRONTIER-AUDIT (Gap-N) |
  3 FRONTIER-HUMAN-GATE | 4 FRONTIER-REPLAY | 5 FRONTIER-SYNTHETIC (Gap-H)
  template: design note → KDR proof → VM proof → readiness map (proven by EPISTEMIC-OUTCOME P1→P4)

code_changed: NO   canon_changed: NO   implementation_authorized: NO
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Research analysis only: no code,
parser, typechecker, VM, or canon/Covenant changes; no PROP authored; no expedition authorized.
Ch12/proposed surfaces phrased as proposed, not accepted canon. Lab behavior not accepted as canon.
The external ecosystem report treated as evidence, not authority. This report informs future gate
decisions; it does not make them.
