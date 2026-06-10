# Card: LAB-EPISTEMIC-OUTCOME-P2
**Category:** governance
**Track:** lab-unknown-state-kdr-convention-proof-v0
**Status:** CLOSED — PROVED
**Gate result:** 54/54 PASS
**Date closed:** 2026-06-10
**Route:** LAB PROOF / KDR CONVENTION / NO IMPLEMENTATION AUTHORITY

---

## Goal

Prove the v0 Kind-Discriminated Record convention for epistemic unknown state: a lost
commit-acknowledgement / timeout scenario must produce data shaped as
`unknown_external_state` or `timed_out` — NOT `failed`, NOT `system_error`, NOT
`upstream_unavailable` — and must route the consumer toward reconciliation, never toward an
inferred success/failure or a blind retry. Primary scenario: storage write commit-ack loss.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-EPISTEMIC-OUTCOME-P1 | ✅ DONE — taxonomy + unknown-state boundary doc |
| LAB-RESULT-ENVELOPE-P2 | ✅ DONE — kind-discriminant 3-domain proof (50/50) |
| LAB-STORAGE-CAPABILITY-P1 | ✅ DONE — storage boundary; commit-ack unmodeled in v0 |
| LAB-QUERY-P3 | ✅ DONE — QueryResult 5-kind; system_error folds timeout (44/44) |
| PROP-044-P6 | ✅ DONE — variant+match SemanticIR emitter (50/50) — NOT used (KDR-only) |
| Covenant P15 | ✅ doctrine — Timeout Is Not Failure (UnknownExternalOutcome) |
| Proposed Ch12 Effect Surface | ✅ proposed — 7-outcome vocabulary (not accepted canon) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (9 contracts, OutcomeEnvelope) | `igniter-view-engine/fixtures/epistemic_outcome/lost_confirmation_kdr.ig` | ✅ DONE |
| Proof runner (54 checks) | `igniter-view-engine/proofs/verify_epistemic_unknown_state_kdr.rb` | ✅ DONE |
| Governance/proof doc | `lab-docs/governance/lab-unknown-state-kdr-convention-proof-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## Envelope (KDR convention only)

```
OutcomeEnvelope {
  kind:            String              — 7 epistemic-outcome values (documented, unenforced)
  message:         String
  idempotency_key: String              — "" if absent; P16 retry precondition, carried as data
  metadata:        Map[String, String] — reconciliation context
}
```

kinds: `succeeded | denied | timed_out | unknown_external_state | partial | cancelled | compensated`
(`compensated` included, not deferred). No variant. No match. No sealed `Outcome[T,E]`.

---

## Proof Sections (54/54)

```
EOUT-COMPILE   (4)  — 9 contracts compile; SIR; no type_errors
EOUT-TYPES     (5)  — OutcomeEnvelope fields; kind/idempotency_key String; metadata Map; Option chain
EOUT-KINDS     (7)  — all seven kinds VM-produced as data
EOUT-UNKNOWN   (5)  — PRIMARY: lost-ack → unknown_external_state; key+metadata preserved; mapper≠system_error
EOUT-NOTFAILED (5)  — unknown/timeout never failed/system_error/upstream_unavailable
EOUT-RECONCILE (4)  — reconciliation is explicit data (map_get+or_else; router returns data)
EOUT-DENIAL    (4)  — denial distinct from unknown; deterministic; no retry
EOUT-PARTIAL   (3)  — partial distinct from unknown
EOUT-RETRY     (5)  — retry NOT authorized unless idempotency explicitly present (P16)
EOUT-CANCEL    (2)  — cancelled distinct path
EOUT-COMPARE   (4)  — vs HttpResult/ContractResult/QueryResult/ValidationResult
EOUT-CLOSED    (6)  — KDR-only; no variant/match; no real I/O; lab-only; no sealed Outcome
```

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Lost-ack → unknown_external_state | VM-executed; NOT succeeded/failed/system_error/upstream_unavailable |
| Idempotency carried as data | `idempotency_key` survives VM execution; decision lives in consumer (P16) |
| Reconciliation metadata preserved | `request_id`/`reconcile_hint` survive for the reconcile pass |
| Mapper does not flatten | raw lost-ack signal → `unknown_external_state`, not `system_error` |
| Timeout never failure | timed_out/unknown route to reconcile; no failure coercion (P15) |
| Retry gated on idempotency | no key ⇒ no retry; denied never retried even with key |
| States distinct | denied (not sent) ≠ unknown (sent, unconfirmed) ≠ partial (some confirmed) |
| KDR sufficient as v0 | seven kinds carried + branched; unchecked String is the only limit |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| KDR sufficient as v0 convention for unknown state? | **YES** — seven kinds carried, VM-executed, consumer-branched |
| Proves an enforced `Outcome[T,E]` type? | **NO** — no variant/match; convention evidence only |
| Authorizes PROP failure-taxonomy implementation? | **NO** — evidence, not authority; needs separate PROP + gate |
| Does timeout become failure anywhere? | **NO** — timed_out/unknown route to reconcile (P15) |
| Does retry open without idempotency? | **NO** — retry authorized only with explicit key (P16) |
| Does StorageCapability execution open? | **NO** — pure contracts; no real write/SQL/commit |
| Does real DB/network/runtime I/O open? | **NO** — no file/network/db/socket/worker I/O |
| Creates public/stable API authority? | **NO** — lab-only |
| Exact next card? | **LAB-EPISTEMIC-OUTCOME-P3** — reconciliation-consumer design note |

---

## Gap Packet

```
proof:      lab-unknown-state-kdr-convention-proof / v0
status:     CLOSED — 54/54 PASS
authority:  governance / lab_only
date:       2026-06-10
domain:     storage write commit-ack loss

primary:
  lost_ack → unknown_external_state    YES (not failed/system_error/upstream_unavailable)
  idempotency_key preserved            YES
  reconcile metadata preserved         YES
  mapper lost-ack → unknown not sys_err YES

invariants:
  timeout_not_failure (P15):           YES
  retry_gated_on_idempotency (P16):    YES
  denial_distinct_from_unknown:        YES
  partial_distinct_from_unknown:       YES
  reconciliation_is_data:              YES

answers:
  kdr_sufficient_v0: YES | proves_enforced_outcome: NO | authorizes_prop_impl: NO
  timeout_becomes_failure: NO | retry_without_idempotency: NO
  storagecapability_opens: NO | real_io_opens: NO | public_stable_authority: NO

existing_proofs_changed: NO (git: only new files added)
  regression sample: RESULT-ENVELOPE-P2 50/50 | QUERY-P3 44/44 | SIDEKIQ-P5 48/48
  P14 58/60 = pre-existing map_get VM-gap markers, independent of this card

next: LAB-EPISTEMIC-OUTCOME-P3 (reconciliation-consumer design note — DAG nodes consume
      unknown_external_state without upward coercion)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only — no sealed
`Outcome[T,E]`, no variant/match runtime authority. No canon spec or Covenant edits. No real storage
writes, SQL, DB, sockets, workers, or runtime I/O opened. `Result`/`Option` untouched. Ch12 treated
as proposed, not accepted canon. PROP-035 numbering collision not resolved (STAB-P4 owns it). Old
Ruby framework surfaces not used as language authority. Lab behavior not accepted as canon. This
card informs future gate decisions; it does not make them.
