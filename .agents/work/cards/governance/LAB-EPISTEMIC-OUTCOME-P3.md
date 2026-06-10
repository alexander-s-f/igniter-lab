# Card: LAB-EPISTEMIC-OUTCOME-P3
**Category:** governance
**Track:** lab-reconciliation-consumer-boundary-for-unknown-state-v0
**Status:** CLOSED — DESIGN NOTE COMPLETE
**Gate result:** 43/43 PASS (proof-local state machine — design evidence, not runtime)
**Date closed:** 2026-06-10
**Route:** DESIGN NOTE / LAB-ONLY / NO IMPLEMENTATION AUTHORITY

---

## Goal

Design the reconciliation-consumer boundary for `unknown_external_state`: define how a
downstream DAG node may consume unknown state without silently coercing it into success,
failure, retry, or compensation. Core formula: `unknown_external_state` is a state requiring
reconciliation, not a value to unwrap and not a failure to handle.

**Spine:** reconciliation IS the explicit typed conversion the Covenant No-Upward-Coercion
rule (covenant:391-403) requires to move unknown (low certainty) → confirmed (observed).

---

## Depends On

| Card | Status |
|------|--------|
| LAB-EPISTEMIC-OUTCOME-P1 | ✅ DONE — taxonomy + unknown-state boundary |
| LAB-EPISTEMIC-OUTCOME-P2 | ✅ DONE — KDR carries unknown state as data (54/54) |
| LAB-STORAGE-CAPABILITY-P1 | ✅ DONE — storage boundary; commit-ack unmodeled |
| LAB-QUERY-P3 | ✅ DONE — QueryResult system_error folds timeout (44/44) |
| PROP-044-P6 | ✅ DONE — variant+match SemanticIR emitter — NOT used (KDR-only) |
| Covenant P15 / P16 / P17 | ✅ doctrine — timeout≠failure / idempotency declared / compensation named |
| Covenant Epistemic State Machine / No Upward Coercion | ✅ doctrine — covenant:375-407 |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Design note | `lab-docs/governance/lab-reconciliation-consumer-boundary-for-unknown-state-v0.md` | ✅ DONE |
| State-machine proof (43 checks) | `igniter-view-engine/proofs/verify_reconciliation_state_machine.rb` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P3.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Proof Sections (43/43 — proof-local, pure Ruby, no compiler/VM/I/O)

```
RSM-ALLOWED   (12) — every allowed transition accepted with its guard satisfied
RSM-FORBIDDEN (10) — every forbidden transition rejected (no direct upgrade; P15)
RSM-GUARD      (6) — retry⇐idempotency; compensate⇐named; accept⇐real/human; loop⇐budget
RSM-DRIVE     (11) — end-to-end honest consumer paths from lost-ack
RSM-CLOSED     (4) — pure-Ruby; no real I/O; KDR-only; lab-only
```

Key proved behaviors: lost-ack + reconcile(success, **real**) → accept; lost-ack +
reconcile(success, **model**) → needs_human_review (NOT accept — No Upward Coercion);
lost-ack + reconcile(failed) + idempotency → retry; + named compensation → compensate;
+ neither → fail (honest); still_unknown + budget → reconcile_again, no budget → hold;
lost-ack with no reconcile result → stuck at reconcile_required (never terminal);
reconciliation_denied → hold (cannot manufacture an outcome).

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| What may consume `unknown_external_state`? | **Only a reconciliation-consumer** — not a value-consumer, not a failure-handler |
| What must a consumer preserve? | request_id, idempotency_key, resource, sent_at/observed_at, attempt/budget, compensation name, raw receipt or absence marker; + kind distinctions |
| Which transitions allowed? | unknown/timeout/partial→reconcile; reconcile→6 results; confirmed→accept/retry/compensate/fail; still_unknown→bounded re-reconcile/hold |
| Which transitions forbidden? | unknown→success/failure/accept/retry/compensate (direct); timed_out→failed; accept w/o confirm; model→real w/o conversion |
| When is retry allowed? | only post-`confirmed_failed` + explicit idempotency (P16) |
| When is compensation allowed? | only post-`confirmed_failed`/`cancelled`-started + named contract (P17) |
| When may unknown become observed success/failure? | only via reconcile pass yielding real/human-evidenced confirmation (P13) |
| Minimum reconciliation receipt? | kind + request_id + resource (required); idempotency_key/observed_at/evidence_kind/compensation/attempt/metadata (typed, never dropped) |
| Requires variant/match runtime? | **NO** — KDR sufficient for v0 |
| Authorizes `Outcome[T,E]` impl? | **NO** — design note only |
| Opens storage writes / DB-network I/O / runtime? | **NO** |
| Exact PROP/failure-taxonomy route? | gated on VM variant dispatch sequencing (not yet understood); PROP deferred — see Next Route |

---

## Gap Packet

```
note:       lab-reconciliation-consumer-boundary-for-unknown-state / v0
status:     CLOSED — design note; transition table proved proof-local 43/43
authority:  governance / lab_only
date:       2026-06-10

spine:      reconciliation IS the explicit typed conversion No-Upward-Coercion requires
recon_results: confirmed_succeeded|confirmed_failed|still_unknown|partially_confirmed|
               reconciliation_denied|reconciliation_error
guards:     accept⇐real/human(P13) | retry⇐idempotency(P16) | compensate⇐named(P17)
            | still_unknown loop⇐budget | hold=escalate (never infer)
forbidden:  unknown→succeeded/failed/accept/retry/compensate; timed_out→failed;
            reconcile_required→accept; model→real(no conversion)
receipt_min: kind+request_id+resource required; evidence_kind blocks model→real upgrade

answers: kdr_sufficient YES | requires_variant_match NO | authorizes_outcome_impl NO
         opens_io NO | retry⇐idempotency+confirmed_failed | compensate⇐named+confirmed_failed
         unknown→observed only via reconcile+real/human | public_stable NO

existing_proofs_changed: NO (git: only new files added)
next: LAB-EPISTEMIC-OUTCOME-P4 (executable reconciliation state-machine, VM)
      + parallel governance probe: VM variant/match dispatch sequencing (gate for Outcome[T,E])
      then: failure-taxonomy proposal-planning card on PROP-044 (PROP+gate; runtime-sequenced)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. Design note + pure-Ruby model.
KDR convention only — no sealed `Outcome[T,E]`, no variant/match runtime authority, no
failure-taxonomy PROP authored. No canon spec or Covenant edits. No new parser/typechecker/runtime
surface. No real storage writes, SQL, DB, network, sockets, workers, or runtime I/O. `Result`/
`Option` untouched. Ch12 treated as proposed, not accepted canon. PROP-035 numbering collision not
resolved (STAB-P4 owns it). Old Ruby framework surfaces not used as language authority. Lab behavior
not accepted as canon. This card informs future gate decisions; it does not make them.
