# Lab Governance Doc: Reconciliation-Consumer Boundary for Unknown State

**Track:** lab-reconciliation-consumer-boundary-for-unknown-state-v0
**Card:** LAB-EPISTEMIC-OUTCOME-P3
**Category:** governance
**Date:** 2026-06-10
**Route:** DESIGN NOTE / LAB-ONLY / NO IMPLEMENTATION AUTHORITY
**Status:** CLOSED — design note complete; transition table proved proof-local (43/43); no promotion authorized

---

## Purpose

P1 named the epistemic outcome model; P2 proved a KDR envelope can carry
`unknown_external_state` honestly as data. **P3 defines how a downstream DAG node is
allowed to *consume* that unknown state** — the consumer contract surface — so that
unknown is never silently coerced into success, failure, retry, or compensation.

**Core formula:** `unknown_external_state` is a *state requiring reconciliation*, not a
value to unwrap and not a failure to handle.

**The spine of this note:** the Covenant's **No Upward Coercion** rule (covenant:391-403)
already forbids a value moving to a higher-certainty epistemic state "without an explicit
typed conversion or human review." `unknown_external_state` sits *below* `observed`.
Therefore **the reconciliation pass IS that explicit typed conversion** — the only
sanctioned route from unknown (low certainty) to `confirmed_succeeded`/`confirmed_failed`
(observed). A consumer that reaches `accept` or `failed` without passing through
reconciliation has performed exactly the forbidden upgrade.

Authority: lab-only design note. `igniter-lang` is the language authority. PROPOSED Ch12
Effect Surface + Covenant doctrine (P13/P15/P16/P17 + the Epistemic State Machine) are the
references, **treated as proposed, not accepted canon**. No code, no parser/typechecker/
runtime surface, no variant/match runtime authority, no failure-taxonomy PROP, no canon
edits. The lab KDR convention is not promoted to canon.

---

## Design Evidence

A proof-local, pure-Ruby state machine encodes the transition table below and asserts every
allowed transition is accepted, every forbidden transition is rejected, and the guards
behave (retry needs idempotency; compensate needs a named contract; accept needs a
real/human confirmation; the still-unknown loop is budget-bounded).

- Runner: `igniter-view-engine/proofs/verify_reconciliation_state_machine.rb` — **43/43 PASS**.
- It runs **no** .ig fixture, **no** compiler, **no** VM, **no** I/O. It is a model of the
  consumer contract surface — the KDR-now behaviour a future sealed `Outcome[T,E]` would make
  type-enforced. It is design evidence, **not** language runtime.

---

## The Three Bands of State

| Band | States |
|------|--------|
| **Effect kinds** (from P2 `OutcomeEnvelope.kind`) | `succeeded`, `denied`, `timed_out`, `unknown_external_state`, `partial`, `cancelled`, `compensated` |
| **Reconciliation lifecycle** | `reconcile_required`, `confirmed_succeeded`, `confirmed_failed`, `still_unknown`, `partially_confirmed`, `reconciliation_denied`, `reconciliation_error` |
| **Terminal actions** | `accept`, `deny`, `retry`, `compensate`, `fail`, `cancel`, `record`, `hold` (escalate to human/audit) |

**Kind distinctions the consumer must preserve** (never collapse):

| kind | what is known | consumer entry |
|------|---------------|----------------|
| `denied` | **nothing was sent** (capability refused pre-dispatch) | `deny` — terminal, no reconcile |
| `timed_out` | **sent, no response** within time budget; outcome unknown | `reconcile_required` |
| `unknown_external_state` | **sent, no confirmation**; state indeterminate | `reconcile_required` |
| `partial` | **some sub-effects confirmed**, others not | `reconcile_required` (remainder) |
| `cancelled` | **stopped before completion** | `cancel` (compensate if effect started) |
| `compensated` | **compensation already ran** (P17) | `record` — terminal |

---

## State-Transition Matrix

```
  EFFECT KIND            ENTRY                 RECONCILIATION RESULT        TERMINAL
  ───────────            ─────                 ─────────────────────        ────────
  succeeded ───────────────────────────────────────────────────────────▶ accept*
  denied ──────────────────────────────────────────────────────────────▶ deny
  cancelled ───────────────────────────────────────────────────────────▶ cancel (▶ compensate†)
  compensated ─────────────────────────────────────────────────────────▶ record

  unknown_external_state ─┐
  timed_out ──────────────┼─▶ reconcile_required ─┬─▶ confirmed_succeeded ─▶ accept*
  partial ────────────────┘                       ├─▶ confirmed_failed ─────▶ retry‡ | compensate† | fail
                                                   ├─▶ partially_confirmed ──▶ reconcile_required (remainder)
                                                   ├─▶ still_unknown ────────▶ reconcile_required§ | hold
                                                   ├─▶ reconciliation_denied ▶ hold
                                                   └─▶ reconciliation_error ──▶ reconcile_required§ | hold

  Guards:  * accept requires real|human observation (P13)      ‡ retry requires idempotency_key (P16)
           † compensate requires a named compensation (P17)    § re-entry requires budget_remaining > 0
```

---

## Allowed / Forbidden Transition Table

### Allowed (with guard)

| From | To | Guard |
|------|----|-------|
| `unknown_external_state` / `timed_out` / `partial` | `reconcile_required` | — |
| `reconcile_required` | `confirmed_succeeded` / `confirmed_failed` / `still_unknown` / `partially_confirmed` / `reconciliation_denied` / `reconciliation_error` | — (the pass reports one of six results) |
| `confirmed_succeeded` | `accept` | observation is `real` or `human` (P13) |
| `confirmed_failed` | `retry` | `idempotency_key` present (P16) |
| `confirmed_failed` | `compensate` | named compensation contract (P17) |
| `confirmed_failed` | `fail` | — (honest surfacing always permitted) |
| `partially_confirmed` | `reconcile_required` | — (reconcile the unconfirmed remainder) |
| `still_unknown` | `reconcile_required` | `budget_remaining > 0` |
| `still_unknown` / `reconciliation_denied` / `reconciliation_error` | `hold` | — (escalate to human/audit; never infer) |
| `succeeded` | `accept` | observation is `real` or `human` |
| `denied` | `deny` | — |
| `cancelled` | `cancel` | — |
| `cancelled` | `compensate` | effect started **and** named compensation |
| `compensated` | `record` | — |

### Forbidden (always rejected)

| From | To | Why |
|------|----|-----|
| `unknown_external_state` | `succeeded` / `confirmed_succeeded` | upward coercion without the reconciliation conversion (covenant:391-403) |
| `unknown_external_state` | `failed` / `confirmed_failed` | unknown is not observed failure (P15) |
| `unknown_external_state` | `accept` | skips reconciliation entirely |
| `unknown_external_state` | `retry` | no reconciliation, and no idempotency (P15+P16) |
| `unknown_external_state` | `compensate` | no reconciliation, no named compensation (P17) |
| `timed_out` | `failed` | timeout is `UnknownExternalOutcome`, not `ObservedFailure` (P15) |
| `reconcile_required` / `still_unknown` | `accept` | a terminal accept without a confirmation |
| `confirmed_failed` | `retry` (no idempotency) | P16 |
| `confirmed_failed` | `compensate` (no named contract) | P17 |
| `confirmed_succeeded` (model evidence) | `accept` (as real) | model observation ≠ real observation without typed conversion / human review (P13) |
| `reconciliation_denied` | `confirmed_succeeded` | a denied reconciliation cannot manufacture an outcome |
| `still_unknown` | `reconcile_required` (no budget) | unbounded reconcile loop |

---

## Explicit Answers (card-required)

**What may consume `unknown_external_state`?** Only a **reconciliation-consumer** — a node
that takes the unknown envelope to `reconcile_required` and runs a reconciliation pass. A
plain value-consumer may **not** unwrap it, and a failure-handler may **not** treat it as an
error. Any node that consumes it must either reconcile or propagate it unchanged (fail-closed).

**What must a consumer preserve?** The evidence needed to reconcile (see Minimum
Reconciliation Receipt): `request_id`, `idempotency_key` (if present), the effect
target/`resource`, `sent_at`/`observed_at` (if available), prior attempt count / budget (if
available), the named compensation contract (if any), and the raw receipt **or an explicit
absence marker**. It must also preserve the kind distinction (`denied` ≠ `timed_out` ≠
`unknown` ≠ `partial` ≠ `cancelled` ≠ `compensated`).

**Which transitions are allowed?** See table. In short: unknown/timeout/partial → reconcile;
reconcile → one of six results; confirmed_succeeded → accept (real/human); confirmed_failed →
retry (idempotent) | compensate (named) | fail; still_unknown → bounded re-reconcile | hold.

**Which transitions are forbidden?** See table. In short: any direct unknown→success,
unknown→failure, unknown→retry/compensate without the reconcile pass and its guards;
timed_out→failure; accept without a confirmation; model→real without conversion.

**When is retry allowed?** Only after `reconcile_required → confirmed_failed`, and only when an
idempotency key is explicitly present (P16). Never directly from `unknown_external_state`.

**When is compensation allowed?** Only after `confirmed_failed` (or `cancelled` with effect
started) **and** only when a compensation contract is named (P17) — otherwise `fail` is the
honest terminal.

**When may an unknown become observed success or observed failure?** Only through a
reconciliation pass that yields `confirmed_succeeded`/`confirmed_failed` carrying a **real or
human** observation (P13). The reconciliation pass *is* the "explicit typed conversion" the
No-Upward-Coercion rule requires. A reconciliation grounded in a *model* observation may not be
promoted to a real success/failure without human review.

**What is the minimum reconciliation receipt shape?** See below.

**Does this require variant/match runtime?** **No.** The whole boundary is expressible and
testable as KDR convention (proved 43/43 proof-local). Variant/match would make the forbidden
transitions *unrepresentable* rather than merely rejected, but it is not required for v0.

**Does this authorize `Outcome[T,E]` implementation?** **No.** Design note only. No sealed type,
no PROP authored.

**Does this open StorageCapability writes, real DB/network I/O, or runtime execution?** **No.**
Pure design + a pure-Ruby model. No fixture, no compiler, no VM, no I/O.

**What exact PROP/failure-taxonomy route should follow, if any?** See Next Route — the failure-
taxonomy PROP is **gated on VM variant/match dispatch sequencing being understood**, which it is
not yet. So the immediate route is executable hardening (P4), not the PROP.

---

## Minimum Reconciliation Receipt Shape

KDR now (a `kind:String` record, exactly like the P2 `OutcomeEnvelope`):

```
ReconciliationReceipt {
  kind:            String              — confirmed_succeeded | confirmed_failed | still_unknown
                                       |  partially_confirmed | reconciliation_denied | reconciliation_error
  request_id:      String              — correlates to the original unknown envelope (REQUIRED)
  resource:        String              — the effect target/resource reconciled (REQUIRED)
  idempotency_key: String              — "" if absent; gates any post-reconcile retry (P16)
  observed_at:     String              — when reconciliation observed the state; "" if n/a
  evidence_kind:   String              — real | human | model | absent  (P13 — certainty of the observation)
  compensation:    String              — named compensation contract; "" or "no_compensation" (P17)
  attempt:         String              — prior attempt count / budget marker, as string; "" if unknown
  detail:          String              — human-readable
  metadata:        Map[String, String] — raw receipt fields OR an explicit absence marker
}
```

**Why `evidence_kind` is load-bearing.** It is the field that prevents the forbidden
`model → real` upgrade. A `confirmed_succeeded` receipt with `evidence_kind: "model"` may not
drive `accept` as a real success — it routes to `needs_human_review`. This is the
No-Upward-Coercion rule made concrete in the receipt (proof: RSM-GUARD-03/04, RSM-DRIVE-02).

**Required vs optional.** `kind`, `request_id`, `resource` are required (a receipt that cannot
be correlated to a request and resource is useless for reconciliation). `idempotency_key`,
`compensation`, `attempt`, `observed_at` are optional-but-typed (carried as `""`/markers when
absent, never dropped — Covenant P11 "uncertainty is not silently discarded" applied to the
receipt itself).

---

## KDR-Now / `Outcome[T,E]`-Later Bridge

| Concern | KDR now (v0) | Sealed `Outcome[T,E]` later |
|---------|--------------|----------------------------|
| Outcome kinds | `kind:String` (documented set) | variant arms (sealed) |
| Reconciliation results | `ReconciliationReceipt.kind:String` | variant arms |
| Forbidden transitions | **rejected** by the consumer (convention; proof-local) | **unrepresentable** (type error) — e.g. no `unwrap_success` arm exists on `unknown_external_state` |
| Exhaustiveness (handle `still_unknown`/`reconciliation_error`) | by discipline + review | enforced by exhaustive `match` (OOF-KIND1, PROP-044-P5) |
| Narrowing (no field-access on the wrong arm) | by discipline | per-arm narrowing (PROP-044-P5) |
| `model → real` guard | `evidence_kind` field + consumer check | typed observation conversion (P13) at the boundary |
| Status | proved 43/43 proof-local | typecheck-expressible (PROP-044-P3/P5); **runtime-blocked** (variant/match VM dispatch unproved) |

The bridge is continuous: the P3 transition guards are exactly the obligations a future
exhaustive `match` over a sealed `Outcome`/`ReconciliationResult` variant would discharge at
compile time. KDR carries the design now; the variant makes the forbidden transitions
impossible later — once VM variant dispatch is proved.

---

## Next Route Recommendation

The card offers two options. The honest gate determines the choice: the failure-taxonomy PROP
(Option 2) sits on the PROP-044 variant substrate, whose **VM dispatch sequencing is not yet
understood** (variant/match executes at typecheck authority only; runtime execution is
unproved). Authoring the PROP now would front-run that unknown.

**Therefore — recommended immediate next: LAB-EPISTEMIC-OUTCOME-P4 — proof-local reconciliation
state-machine (executable, full lifecycle).** Harden this design with executable KDR evidence
of the *loops* this note only models statically: the bounded `still_unknown` re-reconcile loop,
the `partially_confirmed` remainder pass, and a `ReconciliationReceipt` KDR flowing through the
lab VM (as P2 did for `OutcomeEnvelope`). Output: an end-to-end lab proof that the reconciliation
lifecycle holds under VM execution, not just in pure Ruby.

**In parallel (governance probe, no gate): scope VM variant/match dispatch sequencing.** This is
the true gate for any `Outcome[T,E]`. Until it is understood, the failure-taxonomy PROP stays
deferred.

**After P4 + the VM-dispatch probe (PROP + gate): failure-taxonomy proposal-planning card** on
PROP-044, runtime-sequenced.

**Closed (no route opens these here):** sealed `Outcome[T,E]` implementation; variant/match
runtime authority; the failure-taxonomy PROP itself; canon spec/Covenant edits; real storage
writes / SQL / DB / network / sockets / workers / runtime I/O; public/stable API authority; the
PROP-035 numbering collision (STAB-P4 owns it); promoting the lab KDR convention into canon.

---

## Gap Packet

```
note:       lab-reconciliation-consumer-boundary-for-unknown-state / v0
status:     CLOSED — design note; transition table proved proof-local 43/43
authority:  governance / lab_only
date:       2026-06-10

core_formula: unknown_external_state is a state requiring reconciliation,
              not a value to unwrap and not a failure to handle.
spine:        reconciliation IS the explicit typed conversion that No-Upward-Coercion requires.

allowed_entry:    unknown/timed_out/partial → reconcile_required
recon_results:    confirmed_succeeded | confirmed_failed | still_unknown
                  | partially_confirmed | reconciliation_denied | reconciliation_error
terminal_guards:  accept⇐real/human(P13) | retry⇐idempotency(P16)
                  | compensate⇐named(P17) | fail=honest | hold=escalate
forbidden:        unknown→succeeded/failed/accept/retry/compensate (direct);
                  timed_out→failed; reconcile_required→accept; model→real(no conversion)

receipt_min:      kind + request_id + resource (required); idempotency_key/observed_at/
                  evidence_kind/compensation/attempt/metadata (typed, never dropped)
evidence_kind:    load-bearing — blocks model→real upgrade (→ needs_human_review)

answers:
  consumes_unknown:        only a reconciliation-consumer
  requires_variant_match:  NO (KDR sufficient for v0)
  authorizes_outcome_impl: NO
  opens_storage_write/io:  NO
  retry_allowed:           only post-confirmed_failed + idempotency
  compensation_allowed:    only post-confirmed_failed/cancelled-started + named
  unknown→observed:        only via reconcile pass w/ real|human evidence
  public_stable_authority: NO

next:
  immediate: LAB-EPISTEMIC-OUTCOME-P4 (proof-local reconciliation state-machine, executable/VM)
  parallel:  governance probe — VM variant/match dispatch sequencing (gate for Outcome[T,E])
  later:     failure-taxonomy proposal-planning card on PROP-044 (PROP+gate; runtime-sequenced)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Design note + pure-Ruby model
only. KDR convention only — no sealed `Outcome[T,E]`, no variant/match runtime authority, no
failure-taxonomy PROP authored. No canon spec or Covenant edits. No new parser/typechecker/runtime
surface. No real storage writes, SQL, DB, network, sockets, workers, or runtime I/O. `Result`/
`Option` untouched. Ch12 treated as proposed, not accepted canon. PROP-035 numbering collision not
resolved (STAB-P4 owns it). Old Ruby framework surfaces not used as language authority. Lab behavior
not accepted as canon. This note informs future gate decisions; it does not make them.
