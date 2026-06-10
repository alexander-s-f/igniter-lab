# Lab Governance Doc: Epistemic Outcome Model and Unknown-State Boundary

**Track:** lab-epistemic-outcome-model-and-unknown-state-boundary-v0
**Card:** LAB-EPISTEMIC-OUTCOME-P1
**Category:** governance
**Date:** 2026-06-10
**Route:** GOVERNANCE / DESIGN / LAB-ONLY
**Status:** CLOSED — research/design complete; taxonomy + promotion boundary authored; no promotion authorized

---

## Purpose

Design the epistemic outcome model needed for Igniter's open-world surfaces:
distinguish observed success, observed failure, denial, timeout, unknown external
state, partial observation, cancellation, and compensation as **states of knowledge**
rather than flattening them into binary `Result[T,E]` or `Option[T]`.

This doc produces a taxonomy and a promotion boundary. It does **not** implement
types, parser/typechecker/runtime changes, or any public/stable API authority. It
informs future gate decisions; it does not make them.

**Authority note.** This is lab/governance research. The canon authority for the
outcome model is `igniter-lang` (Ch12 Effect Surface + the Language Covenant). The
lab proofs (`igniter-lab`) are evidence, not authority. Where this doc quotes canon,
the canon file is named; where it quotes lab proofs, the lab proof is named. Nothing
here promotes a lab shape to canon.

---

## Headline Finding (read this first)

**Igniter already has an epistemic outcome model — at the canon design layer.** It is
not absent and does not need inventing. It is *declared but unimplemented*, and the
lab proofs *do not yet honor it*.

Two canon surfaces already name the model:

1. **Ch12 Effect Surface** (`igniter-lang/docs/spec/ch12-effect-surface.md:123-132`)
   enumerates seven effect outcomes — `succeeded`, `failed`, `partial`, `timed_out`,
   `unknown_external_state`, `compensated`, `cancelled` — and states explicitly:
   > "`unknown_external_state` is not a failure. It signals that a reconciliation pass
   > is required before retrying." (ch12:131-132)

2. **The Covenant** (`igniter-lang/docs/language-covenant.md`) gives the postulate basis:
   - **P11 — Uncertainty Is Preserved** (covenant:107-119): an estimate carries
     `uncertainty_m` / `confidence` as typed fields; uncertainty may not be silently discarded.
   - **P13 — Observation Is Typed** (covenant:127-131): real / model / human observation
     are different types; a model observation cannot be used as a real one without conversion.
   - **P15 — Timeout Is Not Failure** (covenant:145-149): "A timeout waiting for an external
     system is `UnknownExternalOutcome`, not `ObservedFailure`. These are different types.
     They require different responses: reconciliation, not retry."
   - **P16 — Idempotency Is Declared** (covenant:151-154); **P17 — Compensation Is Named**
     (covenant:156-159).
   - **The Epistemic State Machine** (covenant:375-407): `observed → inferred → estimated →
     assumed → simulated → decided → executed → audited`, governed by the **No Upward
     Coercion** rule ("a value may not move to a higher-certainty epistemic state without
     an explicit typed conversion or human review", covenant:391-403).

The gap is therefore **not** "design a model." The gap is threefold:

- **(G1) Unimplemented types.** `UnknownExternalOutcome` and `ObservedFailure` are *named*
  in the Covenant but not formally spec'd. The Covenant enforcement registry lists P15 as a
  `planned PROP` pointing at "PROP-035 — failure taxonomy with distinct types"
  (covenant:680). *(Status-accuracy flag for STAB-P4 — see Appendix B: the portfolio index
  lists PROP-035 as the capability/effect_binding grammar proposal, a different subject. The
  P15→PROP-035 reference may be a stale or double-assigned number. This doc does not resolve it.)*

- **(G2) Lab proofs flatten unknown state.** Every closed lab KDR envelope collapses the
  open-world states the canon model separates. `QueryResult` folds "connection lost, timeout,
  etc." into `kind:"system_error"`
  (`lab-storage-capability-query-execution-boundary-design-v0.md`); `ContractResult` has no
  `unknown_external_state` — its only post-attempt-uncertainty kind is `"upstream_unavailable"`,
  defined as *retry-budget exhaustion*, not *missing confirmation*; storage commit-ack loss is
  "not explicitly modeled in v0". **The lab envelopes are not epistemically honest by canon's
  own P15 standard.**

- **(G3) Enforcement substrate just changed.** The two predecessor governance docs
  (LAB-RESULT-ENVELOPE-P1/P2) named "no sum-type grammar" as the primary blocker for a stronger
  model. **That blocker is now substantially lifted:** PROP-044-P5 landed variant + match at the
  Classifier + TypeChecker layer with OOF-KIND1..5 active (75/75 PASS, 2026-06-10), on top of
  the PROP-044-P3 parser (50/50). An *enforced* `Outcome` variant is now expressible at
  typechecker authority — though **not** at VM/runtime authority (variant/match runtime execution
  is unproved).

So: the model exists in canon doctrine; the failure-taxonomy *types* are planned-not-built; the
lab evidence underspecifies the model; and the grammar to enforce it just arrived at
experiment-pass. This doc maps that terrain and recommends the next route.

---

## Three Orthogonal Axes (do not conflate)

A recurring design error is to flatten three different questions into one type. Canon already
keeps them separate; this doc names them so downstream work does not re-merge them.

| Axis | Question it answers | Canon surface | Wrong merge to avoid |
|------|--------------------|--------------|---------------------|
| **Outcome** | *Did the effect happen, and do we know?* | Ch12 seven outcomes; `UnknownExternalOutcome`/`ObservedFailure` (P15) | folding `timed_out`/`unknown_external_state` into `failed` |
| **Observation** | *Where did this value come from — world, model, or judgment?* | `Obs[kind,T]` (ch3:29); P13 (covenant:127) | using a model observation as a real one |
| **Estimation** | *How certain is this quantity?* | `uncertainty_m`/`confidence` (P11); `~T` probabilistic types (PROP-026, ch9 Stage-2 reserved) | discarding uncertainty into a bare scalar |

**Epistemic outcome = the Outcome axis.** It is distinct from Observation (`Obs`) and from
Estimation (`~T`/`Uncertain[T]`). They *compose* — an `executed` effect can return an
`UnknownExternalOutcome` whose later reconciliation yields a `model` observation carrying
`confidence` — but they must not be unified into one type. (See "Probabilistic uncertainty:
same track or separate?" in Explicit Answers.)

---

## Outcome Taxonomy Matrix

Canonical outcome states, aligned to Ch12 vocabulary and Covenant postulates. "Evidence" =
what the program actually holds when this state is produced. "Propagation" = how a downstream
DAG node must treat it.

| State | Meaning | Evidence available | Downstream propagation rule | Retry / compensation implication | Example domain |
|-------|---------|-------------------|----------------------------|----------------------------------|----------------|
| `succeeded` (observed success) | Effect completed; confirmation received | Receipt of completion | Unwrap value; continue | None | HTTP 200→`found`; storage commit acked |
| `failed` (observed failure) | Effect attempted; *confirmed* negative outcome | Error receipt / typed error | Branch to error handler; safe to surface | Compensation if the failure left partial effect; **no blind retry** | Validation `invalid`; HTTP 4xx `not_found` |
| `denied` (no authority) | Effect **not** attempted; capability refused *before* dispatch | Capability decision record | Branch to denial path; **deterministic, never retried** | No retry (policy is deterministic); no compensation (nothing happened) | `capability_denied`; Query gate G1–G3 `denied`; `unauthorized` |
| `timed_out` | Time limit exceeded; **outcome unknown** | Request-sent marker; no confirmation | Treat as unknown, **not** failure (P15) | **Reconciliation, not retry**; retry only if idempotency declared (P16) | Storage write, no commit ack; upstream call, no response |
| `unknown_external_state` | Request sent; no confirmation; external state indeterminate | Request-sent marker + idempotency key (if any) | **Fail-closed:** must not assume success or failure; route to reconciliation | Reconcile against external system; compensation deferred until reconciled | Payment submitted, settlement unknown; commit-ack lost |
| `partial` | Effect partially completed; some sub-effects confirmed, others not | Partial receipt enumerating done/undone | Carry the partial set explicitly; downstream must handle a mixed state | Compensate the confirmed portion; reconcile the unconfirmed | Batch write half-applied; multi-row commit interrupted |
| `cancelled` | Effect cancelled before completion | Cancellation marker | Branch to cancellation path; distinct from failure and denial | Compensation if any effect started before cancel; otherwise none | Service-loop shutdown mid-job; client abort |
| `compensated` | A prior failure/unknown triggered its named compensation; compensation ran | Compensation receipt (P17) | Treat as a *resolved* terminal state; do not re-compensate | Compensation already executed; record only | Refund issued after failed charge |
| `stale` (observation) | A previously-observed value whose freshness window has lapsed | Original observation + timestamp/horizon | Downstream must re-observe or mark derived results stale | N/A (this is an Observation-axis qualifier; see note) | Cached temporal read past horizon |
| `inferred`/`model` (observation) | Outcome asserted by inference/model, not direct world contact | Model observation packet (P13) | May not be coerced to `observed`/`executed` (No Upward Coercion) | N/A (Observation-axis) | Optimistic local mirror of remote state |

**Notes.**
- The first nine effect-outcome rows (`succeeded`…`compensated`) align directly to Ch12's seven
  outcomes, with `denied` and `partial` split out per the card's required state set. `denied` is
  **not** in Ch12's seven — it is the Covenant's denial-as-data invariant promoted to outcome
  status (see "Should denial be a separate outcome?").
- `stale` and `inferred`/`model` are **Observation-axis** qualifiers, included because the card
  lists them ("stale observation", "inferred/model observation"). They describe *the provenance of
  a value*, not *the fate of an effect*. They belong to `Obs[kind,T]` / P13, not to the effect
  outcome variant. Keeping them on the Observation axis is the correct factoring; merging them
  into the outcome enum would re-conflate axes.
- **`unknown_external_state` vs `timed_out`.** `timed_out` is one *cause* of
  `unknown_external_state`; the latter is the general epistemic state ("sent, unconfirmed"). A
  timeout is the most common producer, but a lost ack or a dropped connection mid-flight produces
  the same epistemic state without a clock expiring. Treat `timed_out` as a labeled subtype of
  `unknown_external_state` for propagation purposes (both → reconciliation).

---

## Relationship Matrix: Option vs Result vs KDR vs future variant `Outcome`

| Construct | Models | Cardinality | Open-world adequate? | Authority today | Verdict for unknown-state |
|-----------|--------|-------------|---------------------|-----------------|---------------------------|
| `Option[T]` | presence vs absence | 2 (`Some`/`None`) | **No** | canon stable (ch3:20, ch8 stdlib) | Cannot express *why* absent, nor "attempted-but-unknown". Insufficient. |
| `Result[T,E]` | success vs error | 2 (`Ok`/`Err`) | **No** | canon stable (ch3:21, ch8 stdlib) | Collapses denial, timeout, and unknown-state into `Err`. **Canon itself rejects this** (P15: timeout ≠ failure). Sufficient for *closed-world* computation only. |
| **KDR** (`kind:String` record) | N-way discriminated outcome by convention | N (documented, unenforced) | **Yes, by convention** | lab convention (PROP-044-P1); 3 domains proved | Can carry a `kind:"unknown_external_state"` value *today*. But `kind` is an unchecked String: typos undetected, no exhaustive match, no narrowing. Adequate as **v0 convention**, not as a guarantee. |
| future `variant Outcome[T,E]` | N-way *sealed* sum with exhaustive match | N (sealed, enforced) | **Yes, enforced** | parser + typechecker at experiment-pass (PROP-044-P3/P5); **no VM/runtime** | The target: arms == Ch12 outcomes; exhaustive match enforced (OOF-KIND1); narrowing per arm. Enforceable at typecheck now; not runnable. |

**KDR → variant migration is now a real path, not a hypothetical.** The predecessor docs treated
the sum type as distant ("no sum-type grammar"). With PROP-044-P3/P5 landed, the KDR convention
and an enforced `variant` are two rungs of the *same* ladder: KDR is the unenforced v0; `variant
Outcome` is the enforced v1, blocked now only on VM/runtime execution of match, not on grammar.

**Naming recommendation.** Do **not** invent `EpistemicOutcome[T]`. Canon already supplies the
vocabulary:
- Effect-outcome variant → **`Outcome[T,E]`**, arms = the Ch12 seven outcomes (+ `denied`).
- Observation packets → **`Obs[kind,T]`** (already in ch3:29), for `observed`/`model`/`human`/`stale`.
- Estimation → **`~T`** / `Uncertain[T]` (PROP-026, Stage-2 reserved).
- The named types `UnknownExternalOutcome` / `ObservedFailure` (Covenant P15) should be the *arm
  payload types* of `Outcome`, not a parallel scheme.

A new top-level name would fork canon's existing vocabulary and create exactly the kind of
overclaiming STAB-P2/P3 are working to remove.

---

## Fragment Impact Matrix

How each compiler fragment relates to the outcome model. (Fragment hierarchy:
CORE / STREAM / TEMPORAL / ESCAPE / OOF, per Ch4; STORAGE and SERVICE LOOP are
capability/profile surfaces layered on ESCAPE and the service loop class.)

| Fragment | Does it produce open-world outcomes? | Outcome states in play | Status / boundary |
|----------|--------------------------------------|------------------------|-------------------|
| **CORE** | No — closed-world, pure/deterministic | `succeeded`/`failed` only; `Result`/`Option` sufficient | No change needed. CORE is exactly where `Result[T,E]` *is* adequate. KDR plan-building (LAB-QUERY-P2) is CORE and stays. |
| **STREAM** | Partially — unbounded sources can stall | `partial`, `unknown_external_state`, `cancelled` | Stream stall ≠ stream end. *(Note the known STREAM→ESCAPE classifier drift, gov C19/C03 — outcome modeling must not ride on top of a misclassified fragment.)* Deferred to Stage-2 (PROP-023). |
| **TEMPORAL** | Yes — a temporal backend may be unable to answer | `unknown_external_state`, `stale` | A temporal query the backend "cannot answer" is `unknown_external_state`, not empty. `stale` is the horizon-lapse case. Stage-2 reserved (PROP-022). |
| **ESCAPE** | Yes — the primary open-world surface | **All** outcome states | This is where the model earns its keep. Real network/effect execution must produce the full outcome set, honoring P15. Currently the lab flattens here (G2). |
| **STORAGE** | Yes — commit ack can be lost | `succeeded`, `denied`, `timed_out`, `unknown_external_state`, `partial`, `system_error` | LAB-STORAGE-CAPABILITY-P1 is design-only; commit-ack loss "not modeled in v0". Real write execution must model `unknown_external_state` before it opens. |
| **SERVICE LOOP** | Yes — heartbeats can be missed | `unknown_external_state`, `cancelled`, `partial` | A missed heartbeat is unknown liveness, not confirmed death. Maps through PROP-037 progression descriptors (Covenant P14). |

**Cross-cutting:** denial-as-data (`denied`) is fragment-independent — it is the strongest lab
invariant (7 proofs) and already flows as data through every fragment that touches a capability.
It is the one outcome state with no implementation gap; it only needs a *name* in the outcome enum.

---

## Promotion Readiness Matrix

| Item | Convention now? | Proposal later? | Implementation | Runtime |
|------|----------------|-----------------|----------------|---------|
| Outcome taxonomy (this doc's state set) | ✅ usable as design vocabulary | ✅ PROP candidate (failure taxonomy) | ⛔ blocked | ⛔ blocked |
| `denied` as a first-class outcome state | ✅ already de-facto (denial-as-data, 7 proofs) | ✅ fold into outcome enum | ⛔ blocked | ⛔ blocked |
| `unknown_external_state` / `timed_out` honesty | ⚠️ convention only via `kind:` String | ✅ **highest-value proposal** | ⛔ blocked | ⛔ blocked |
| `Outcome[T,E]` as enforced variant | ⚠️ not yet — needs design | ✅ PROP on top of PROP-044 | 🟡 typechecker-expressible (PROP-044-P5) | ⛔ VM/match runtime unproved |
| `UnknownExternalOutcome`/`ObservedFailure` types | ❌ named only (Covenant) | ✅ this *is* the planned PROP-035-style failure taxonomy | ⛔ blocked | ⛔ blocked |
| `Obs[kind,T]` observation axis | ✅ named in ch3 | ✅ separate track | ⛔ blocked | ⛔ blocked |
| Probabilistic `~T` / `Uncertain[T]` | ❌ Stage-2 reserved (PROP-026) | ✅ **separate** track | ⛔ blocked | ⛔ blocked |
| Reconciliation contract (consumes unknown state) | ⚠️ design vocabulary only | ✅ needed before ESCAPE/STORAGE writes | ⛔ blocked | ⛔ blocked |

**Legend:** ✅ available / recommended · ⚠️ partial/convention-only · 🟡 expressible at one layer ·
❌ not present · ⛔ explicitly closed (no authority opens this without new PROP + gate).

---

## Domain Pressure → Required State (worked)

| Domain scenario | Wrong (flattened) model | Correct epistemic state | Required downstream |
|-----------------|------------------------|------------------------|---------------------|
| Network call, no confirmation | `Result.Err` | `unknown_external_state` | reconcile; retry only if idempotent (P16) |
| Payment submitted, settlement unknown | `Err("payment failed")` — **dangerous** | `unknown_external_state` | reconcile against PSP; never assume failure→refund nor success→ship |
| Storage write, commit ack lost | `Err` or silent success — **both wrong** | `timed_out` → `unknown_external_state` | reconcile by reading back; compensation deferred |
| Temporal query, backend cannot answer | `None`/empty | `unknown_external_state` | re-query or mark derived results unknown |
| Service-loop heartbeat missed | `failed`/dead | `unknown_external_state` (liveness) | probe before declaring death |
| Retry budget exhausted, external state uncertain | `upstream_unavailable` (lab today) | `unknown_external_state` (budget exhaustion ≠ confirmed unavailability) | reconcile; the *budget* is exhausted, the *world* is unknown |

The last row is the sharpest indictment of current lab practice: `ContractResult.upstream_unavailable`
**asserts unavailability** when all that is actually known is that retries ran out. That is an
upward coercion (unknown → failure) the Covenant forbids (covenant:391-403).

---

## Explicit Answers (card-required)

**Does Igniter currently have an adequate model for unknown external state?**
**Partially — at the design layer only.** Canon *declares* it (Ch12 `unknown_external_state` +
Covenant P15 `UnknownExternalOutcome`). It is **not implemented** (types named, not spec'd;
P15 = `planned PROP`), and the **lab proofs do not honor it** (they flatten timeout/lost-ack into
`system_error`/`upstream_unavailable`). So: adequate as doctrine, inadequate as executable model.

**Is `Result[T,E]` sufficient?** **No** — and canon already says so. P15 makes timeout a
*different type* from failure. `Result` is correct for **closed-world CORE** computation and nothing
more.

**Is `Option[T]` sufficient?** **No.** Presence/absence cannot express denial, timeout, or
attempted-but-unknown. An empty temporal answer and an unanswerable temporal query are different
epistemic states; `Option` collapses them.

**Can KDR conventions model v0 outcomes temporarily?** **Yes** — this is the recommended v0. A
`kind:String` envelope can carry `"unknown_external_state"`, `"denied"`, `"timed_out"` today, exactly
as the lab already carries `"capability_denied"`. The limit is enforcement: unchecked String, no
exhaustive match, no narrowing. Adequate as convention; not a guarantee.

**Is variant/match a prerequisite for a stronger model?** **For an *enforced* model, yes — and it
has now substantially arrived.** PROP-044-P3 (parser) + PROP-044-P5 (classifier + typechecker,
OOF-KIND1..5, 75/75) make a sealed exhaustive `Outcome` variant expressible at typecheck authority.
**It is not a prerequisite for the v0 *convention*.** Runtime execution of match remains unproved,
so the enforced model is typecheck-expressible but not runnable.

**Should probabilistic uncertainty be the same track or separate?** **Separate.** Estimation
(`~T` / `Uncertain[T]`, PROP-026; P11 `confidence`/`uncertainty_m`) answers *how certain is this
quantity*. Epistemic outcome answers *did the effect happen and do we know*. The Epistemic State
Machine already separates `estimated` from `executed`/`observed`. They compose (an unknown outcome,
once reconciled, may yield an estimated quantity) but must not be one type. Keep `~T` on its own
Stage-2 track.

**Does this block StorageCapability execution?** **Yes, for writes.** Real storage *write*
execution must not open until `unknown_external_state` is modeled — lost commit-ack is the canonical
unknown-state case and is currently "not modeled in v0". *Reads* are lower-risk (a failed read is
closer to closed-world), but timeout-on-read is still `unknown`, not empty. StorageCapability is
design-only today, so nothing is lost by gating writes on this.

**Does this block real network execution?** **Yes, for non-idempotent / effectful calls.** Per P16,
a non-idempotent operation under retry without a declared idempotency key is a compile error; per
P15, a timed-out call is `unknown_external_state`, not failure. Real effectful network execution must
honor both before it opens. Idempotent reads are lower-risk.

**Does this change current Query/Rack/Sidekiq proofs?** **No — not retroactively.** They are closed
lab evidence and remain valid proofs *of what they proved* (KDR shape, denial-as-data, Map chains,
budget loops). It **does** reclassify them as **epistemically incomplete**: they flatten unknown
state. Any *future* revision (or any promotion attempt) must add the unknown/timeout states. Their
closed status is untouched; their adequacy as a *complete* outcome model is explicitly denied.

**Should implementation open now?** **No.** This is research/design, lab-only. No types, no
parser/typechecker/runtime edits, no public API.

**What is the exact next recommendation?** See "Next Route" below — KDR-convention proof for the
unknown-state set, then a failure-taxonomy PROP that aligns canon's named types with the Ch12 enum
on top of PROP-044's variant substrate.

---

## Next Route Recommendation

**Recommended: KDR convention proof now → failure-taxonomy PROP next.** (Not "hold"; not "open
implementation".)

1. **Immediate (no gate): LAB-EPISTEMIC-OUTCOME-P2 — unknown-state KDR convention proof.**
   Prove a `kind:String` outcome envelope that *adds the open-world states the current lab
   envelopes omit*: `unknown_external_state`, `timed_out`, `partial`, `cancelled`, `denied`,
   alongside `succeeded`/`failed`. Target the sharpest domain: a storage-write or upstream-call
   fixture where confirmation is lost. Goal: demonstrate, lab-only, that the KDR convention can
   carry epistemic honesty *today*, and that consumers can branch fail-closed on unknown. This
   directly closes G2 at the convention layer without touching canon.

2. **Short-term (no gate): reconciliation-consumer design note.** Specify how a downstream DAG node
   consumes `unknown_external_state` (fail-closed; route to a named reconciliation contract; never
   coerce upward). This is the missing half of P15 — the Covenant says "reconciliation, not retry"
   but no reconciliation surface is designed.

3. **Medium-term (requires PROP + gate): failure-taxonomy PROP on the PROP-044 substrate.** Author
   the proposal that turns the named types (`UnknownExternalOutcome`, `ObservedFailure`) + the Ch12
   enum into a sealed `Outcome[T,E]` variant with exhaustive match (OOF-KIND1) and per-arm narrowing.
   This is the work the Covenant registry calls "PROP-035 — failure taxonomy" (covenant:680). It is
   now *grammar-unblocked* at typecheck authority; it remains *runtime-blocked* (variant/match VM
   execution unproved). **Sequence it after** VM match execution is proved, or scope it
   typecheck-only.

4. **Governance hygiene (route to STAB-P4): resolve the P15→PROP-035 number.** The Covenant maps P15
   to "PROP-035 — failure taxonomy" while the portfolio index uses PROP-035 for the
   capability/effect_binding grammar. Confirm whether the failure taxonomy needs a fresh PROP number
   before any proposal in step 3 is authored. (See Appendix B.)

**Blocked / closed (no route opens these here):**
- Any `Outcome` type implementation in production files.
- Real StorageCapability *write* execution.
- Real effectful network execution.
- VM/runtime authority for variant/match.
- Redefining `Result`/`Option` semantics, or claiming `~T` belongs in the outcome type.

---

## Gap Packet

```
analysis:   lab-epistemic-outcome-model-and-unknown-state-boundary / v0
status:     CLOSED — research/design complete; no promotions authorized
authority:  governance / lab_only
date:       2026-06-10

model_exists_in_canon:    YES — Ch12 (7 outcomes) + Covenant P11/P13/P15/P16/P17 + state machine
model_implemented:        NO  — UnknownExternalOutcome/ObservedFailure named, not spec'd (P15 = planned PROP)
lab_honors_model:         NO  — QueryResult/ContractResult flatten unknown→system_error/upstream_unavailable

three_axes:
  outcome:        Ch12 enum + UnknownExternalOutcome/ObservedFailure   (this track)
  observation:    Obs[kind,T] (ch3:29) + P13 real/model/human          (separate)
  estimation:     ~T / Uncertain[T] (PROP-026) + P11 confidence        (separate, Stage-2)

sufficiency:
  Result[T,E]:    closed-world CORE only — INSUFFICIENT for open world (P15)
  Option[T]:      INSUFFICIENT (presence/absence only)
  KDR (kind:Str): SUFFICIENT as v0 convention; unenforced
  variant Outcome: enforced model; typecheck-expressible (PROP-044-P5), runtime-blocked

grammar_blocker_status:   LIFTED at typecheck (PROP-044-P3 parser 50/50; P5 TC+OOF-KIND 75/75)
                          STILL CLOSED at runtime (variant/match VM execution unproved)

blocks:
  storage_write_exec:     YES — until unknown_external_state modeled (lost-ack)
  real_network_exec:      YES — non-idempotent/effectful; P15+P16
  storage_read / idempotent_read: lower risk; timeout-on-read still = unknown
  existing_query_rack_sidekiq_proofs: NOT retroactively; reclassified epistemically-incomplete

implementation_open_now:  NO
probabilistic_same_track: NO — separate (~T / Uncertain[T])

next_authorized_routes:
  immediate:    LAB-EPISTEMIC-OUTCOME-P2 (unknown-state KDR convention proof, no gate)
  short_term:   reconciliation-consumer design note (no gate)
  medium_term:  failure-taxonomy PROP on PROP-044 variant substrate (PROP + gate; runtime-sequenced)
  governance:   STAB-P4 — resolve P15→PROP-035 number collision
```

---

## Appendix A — Source Citations

Canon (igniter-lang — **authority**):
- `docs/spec/ch12-effect-surface.md:121-138` — seven effect outcomes; `unknown_external_state` not a failure; compensation.
- `docs/spec/ch3-type-system.md:18-29` — `Variant{}`, `Option[T]`, `Result[T,E]`, `Obs[kind,T]` grammar.
- `docs/language-covenant.md:107-119` (P11), `:127-131` (P13), `:145-149` (P15), `:151-159` (P16/P17), `:375-407` (Epistemic State Machine + No Upward Coercion), `:680` (P15 enforcement registry → planned PROP-035).
- `docs/spec/ch9-stage2-reserved.md` — PROP-022 (History), PROP-023 (stream), PROP-026 (`~T`).

Lab (igniter-lab — **evidence**):
- `lab-docs/governance/lab-contract-result-envelope-taxonomy-and-promotion-boundary-v0.md` (LAB-RESULT-ENVELOPE-P1).
- `lab-docs/governance/lab-result-envelope-third-domain-kind-discriminant-pressure-v0.md` (LAB-RESULT-ENVELOPE-P2).
- `lab-docs/lang/lab-storage-capability-query-execution-boundary-design-v0.md` — QueryResult 5-kind; `system_error` folds timeout/connection-loss; commit-ack "not modeled in v0".
- `lab-docs/lang/lab-network-http-upstream-call-contract-composition-proof-v0.md` — ContractResult 6-kind; `upstream_unavailable` = budget exhaustion.
- `.agents/work/cards/lang/PROP-044-P3.md` / `PROP-044-P5.md` — variant+match parser (50/50) + TypeChecker/OOF-KIND (75/75).
- `.agents/work/cards/lang/PROP-045-P2.md` — `intent` descriptor (queryable purpose, not behavior/authority).
- `.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md`, `LAB-QUERY-P3.md`, `LAB-STDLIB-NET-P8/P9.md`.

Governance (igniter-gov — **private coordination, evidence**):
- `portfolio/governance/2026-06-10-mode-a-docs-stabilization-pause.md:65-68` — STAB-P1..P4 definitions; STAB-P4 = P0 governance fixes (PROP numbering/status/hash/fragment).

## Appendix B — Flagged Inconsistency (for STAB-P4, not resolved here)

Covenant enforcement registry (covenant:680) lists Postulate 15 as a `planned PROP` =
"PROP-035 — failure taxonomy with distinct types". The lab portfolio index lists **PROP-035** as
"capability/effect_binding grammar + OOF-M2/M4/M5 (experiment-pass, 64/64)". These are different
subjects under one number. This is the class of issue STAB-P4 governs (PROP numbering/status). This
doc does **not** resolve it and does not assert a number for the failure-taxonomy proposal; it flags
it so step 3 of the Next Route does not author under a colliding number.

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. No production files changed.
No types, parser, typechecker, or runtime modified. No PROP authored. `Result`/`Option` semantics
untouched. No variant/match runtime authority claimed. Old Ruby framework surfaces were not used as
language authority. The external ecosystem report was treated as evidence, not authority.
This doc informs future gate decisions; it does not make them.
