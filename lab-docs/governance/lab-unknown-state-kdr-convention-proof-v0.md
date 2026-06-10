# Lab Governance Doc: Unknown-State KDR Convention Proof

**Track:** lab-unknown-state-kdr-convention-proof-v0
**Card:** LAB-EPISTEMIC-OUTCOME-P2
**Category:** governance
**Date:** 2026-06-10
**Route:** LAB PROOF / KDR CONVENTION / NO IMPLEMENTATION AUTHORITY
**Status:** CLOSED — 54/54 PASS; v0 unknown-state KDR convention proved; no promotion authorized

---

## Purpose

Prove, at the lab level, that the v0 Kind-Discriminated Record (KDR) convention can
carry **epistemic unknown state honestly today** — without any sealed `Outcome[T,E]`
variant, without variant/match runtime authority, and without opening real storage or
network execution.

The proof targets the case the prior lab envelopes flattened: a **storage write whose
commit acknowledgement is lost**. A request was sent; no ack was received; the external
state is genuinely indeterminate. The system must not infer success, must not infer
failure, and must route the consumer toward **reconciliation, not retry** (Covenant
Postulate 15).

This is a lab proof. `igniter-lang` remains the language authority; PROPOSED Ch12 Effect
Surface + Covenant doctrine are the design references, **treated as proposed, not accepted
canon**. The lab KDR convention is **not** promoted into canon by this proof.

---

## What Was Built

| Artifact | Path |
|----------|------|
| Fixture (9 contracts, 1 type) | `igniter-view-engine/fixtures/epistemic_outcome/lost_confirmation_kdr.ig` |
| Proof runner (54 checks) | `igniter-view-engine/proofs/verify_epistemic_unknown_state_kdr.rb` |
| This doc | `lab-docs/governance/lab-unknown-state-kdr-convention-proof-v0.md` |
| Card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P2.md` |

### The envelope (KDR convention only)

```
OutcomeEnvelope {
  kind:            String              — primary discriminant (7 epistemic-outcome values)
  message:         String              — human-readable outcome detail
  idempotency_key: String              — "" if absent; P16 retry precondition, carried as data
  metadata:        Map[String, String] — reconciliation context (request_id, reconcile_hint, …)
}
```

`kind` value vocabulary (closed set, documented — not type-enforced; this is the KDR
convention, exactly as PROP-044-P1 defines it):

| kind | meaning | consumer route |
|------|---------|---------------|
| `succeeded` | effect confirmed | accept (value path) |
| `denied` | capability refused **before** dispatch | deny (deterministic; no retry) |
| `timed_out` | time budget exceeded; outcome **unknown** (subtype of unknown) | reconcile |
| `unknown_external_state` | sent; no confirmation; state indeterminate | reconcile |
| `partial` | some sub-effects confirmed, others not | reconcile_partial |
| `cancelled` | cancelled before completion | cancel |
| `compensated` | named compensation already ran (P17) | record (terminal) |

`compensated` was **included** (not deferred) — it is cheap to carry as a terminal kind and
demonstrates the P17 compensation outcome is distinct from the unknown/partial states.

### The 9 contracts

Seven kind-producing contracts (`CommitWriteAcked`, `CommitWriteDenied`,
`CommitWriteTimedOut`, `CommitWriteLostAck` *(primary)*, `CommitWritePartial`,
`CommitWriteCancelled`, `CompensatedWrite`); one three-layer mapper
(`StorageOutcomeMapper`: raw storage signal → epistemic outcome, never fabricating
`succeeded`/`failed`/`system_error` from a missing ack); one map-chain reader
(`ReconciliationHint`: `map_get(env.metadata, key)` + `or_else`).

---

## Proof Architecture (three layers)

- **Layer A — Production Ruby TypeChecker** (`igniter-lang/lib`): 9/9 contracts accepted,
  zero type_errors; `OutcomeEnvelope` fields typed; `metadata: Map[String,String]` via the
  C1 fix; `map_get` through the named-record field yields `Option[String]`.
- **Layer B — Lab Rust VM** (`igniter-compiler` + `igniter-vm`): all seven kinds constructed
  and returned as data; the lost-ack contract returns `kind:"unknown_external_state"` while
  **preserving the idempotency key and reconciliation metadata**; the map-chain executes.
- **Layer C — Proof-local consumer** (`ReconciliationRouter`, deterministic Ruby): kind→action
  routing, denial-as-data, reconciliation routing, and idempotency-gated retry — reconciliation
  returned as **data**, never via exception/control-flow.

**Result: 54/54 PASS.** Sections: EOUT-COMPILE (4), EOUT-TYPES (5), EOUT-KINDS (7),
EOUT-UNKNOWN (5), EOUT-NOTFAILED (5), EOUT-RECONCILE (4), EOUT-DENIAL (4), EOUT-PARTIAL (3),
EOUT-RETRY (5), EOUT-CANCEL (2), EOUT-COMPARE (4), EOUT-CLOSED (6).

---

## The Lost-Confirmation Scenario (primary)

`CommitWriteLostAck` receives a `resource`, an `idempotency_key`, and reconciliation
`metadata`. It emits:

```json
{ "kind": "unknown_external_state",
  "message": "write sent; commit ack lost; external state indeterminate",
  "idempotency_key": "idem-9",
  "metadata": { "request_id": "r-9", "sent_at": "t0", "reconcile_hint": "read-back users row" } }
```

Proved (VM-executed):
- The kind is `unknown_external_state` — **not** `succeeded`, **not** `failed`, **not**
  `system_error`, **not** `upstream_unavailable` (EOUT-UNKNOWN-01, EOUT-NOTFAILED-01..03).
- The idempotency key survives as data — the P16 retry precondition is carried, not decided
  inside the envelope (EOUT-UNKNOWN-02, EOUT-RETRY-05).
- The reconciliation metadata survives — `request_id` is available for the reconciliation pass
  (EOUT-UNKNOWN-03).
- `StorageOutcomeMapper` projects a raw lost-ack signal to `unknown_external_state`, **not**
  `system_error` — closing, at the convention layer, the exact flattening the prior lab
  envelopes performed (EOUT-UNKNOWN-05).
- The consumer routes `unknown_external_state` → `reconcile`, never to a failure-shaped action
  and never to `accept` (EOUT-NOTFAILED-04, EOUT-RECONCILE-02).

### Retry is gated on explicit idempotency (Covenant P16)

`ReconciliationRouter.retry_authorized?` returns **true only** when the kind is in the
reconcile-then-retry class *and* an idempotency key is explicitly present:
- unknown / timed_out **without** a key → retry **not** authorized (EOUT-RETRY-01, -03).
- unknown **with** a key → retry authorized (after reconciliation) (EOUT-RETRY-02).
- `denied` → retry **never** authorized, even with a key present (deterministic) (EOUT-DENIAL-03).
- `succeeded` → never a blind-retry candidate (EOUT-RETRY-04).

### Distinctness (the states do not collapse into each other)

- `denied` ≠ `unknown_external_state` (EOUT-DENIAL-04): denial means **nothing was sent**;
  unknown means **sent, unconfirmed**.
- `partial` ≠ `unknown_external_state` (EOUT-PARTIAL-03): partial means **some effect is
  confirmed**; unknown means **no confirmation at all**.
- `cancelled` routes to `cancel`, distinct from `deny` and `reconcile` (EOUT-CANCEL-02).

---

## Explicit Answers (card-required)

**Is KDR sufficient as a v0 convention for unknown state?**
**Yes.** A `kind:String` envelope carries `unknown_external_state`/`timed_out`/`partial`/
`cancelled`/`denied`/`compensated` today, executes through the lab VM, and a consumer branches
on it deterministically — including routing unknown state to reconciliation and gating retry on
idempotency. KDR is sufficient as the v0 convention. Its limit (unchanged from PROP-044): `kind`
is an unchecked String — no exhaustive-match enforcement, no narrowing, typos undetected. v0
convention, not a guarantee.

**Does this prove an enforced `Outcome[T,E]` type?**
**No.** No sealed variant, no `match`, no narrowing. The fixture declares zero variants
(EOUT-CLOSED-01) and uses no `match`/`Outcome[` in code (EOUT-CLOSED-02). This is convention
evidence only.

**Does this authorize PROP failure-taxonomy implementation?**
**No.** It is evidence toward such a PROP, not authority. Authority requires a separate proposal
+ gate. No PROP was authored or implemented here.

**Does timeout become failure anywhere?**
**No.** `timed_out` and `unknown_external_state` route to `reconcile`; no VM result carries
`failed`/`system_error`/`upstream_unavailable`; the consumer never coerces an unknown kind into a
failure action (EOUT-NOTFAILED-01..05). Covenant P15 honored.

**Does retry open without idempotency?**
**No.** Retry is authorized only when an idempotency key is explicitly present (EOUT-RETRY-01..05).
Covenant P16 honored.

**Does StorageCapability execution open?**
**No.** No real storage write, SQL, DB, transaction, or commit occurs. The scenario is a pure
contract producing typed data; the commit/ack is modeled, not performed. Real StorageCapability
write execution remains closed.

**Does real DB/network/runtime I/O open?**
**No.** The runner performs no file/network/db/socket/worker I/O (EOUT-CLOSED-04); the fixture is
pure contracts. No sockets, no workers, no runtime I/O.

**Does this create public/stable API authority?**
**No.** Lab-only; no canon claim, no stable surface, no framework compat (EOUT-CLOSED-05/06).

**What exact reconciliation-consumer card should follow?**
**LAB-EPISTEMIC-OUTCOME-P3 — reconciliation-consumer design note:** how DAG nodes consume
`unknown_external_state` without upward coercion. This proof built a *minimal* router
(`ReconciliationRouter`); P3 should design the reconciliation-consumer contract surface properly:
the fail-closed propagation rule, the reconcile→confirm→(retry|compensate) lifecycle, and how the
idempotency precondition and the No-Upward-Coercion rule (Covenant:391-403) are enforced at DAG
boundaries. See Next Route.

---

## Relationship to Prior Lab Envelopes

| Envelope | Lost-ack / timeout today | This proof |
|----------|--------------------------|------------|
| `QueryResult` (LAB-QUERY-P3) | folds timeout/connection-loss into `system_error` | replaced by `unknown_external_state` at the convention layer |
| `ContractResult` (LAB-STDLIB-NET-P9) | `upstream_unavailable` = budget exhaustion (asserts unavailability) | `unknown_external_state` keeps the world unknown; budget exhaustion ≠ confirmed unavailability |
| storage commit-ack (LAB-STORAGE-CAPABILITY-P1) | "not modeled in v0" | now modeled as `unknown_external_state` (convention) |
| `ValidationResult` (LAB-RESULT-ENVELOPE-P2) | closed-world; no idempotency carrier | adds `idempotency_key` (P16) for the open-world axis |

`OutcomeEnvelope` carries `unknown_external_state`, a kind **none** of the prior envelopes have
(EOUT-COMPARE-01), and adds the `idempotency_key` carrier absent from `ValidationResult`
(EOUT-COMPARE-03). The KDR `kind:String` discriminant is the same proven pattern as the three
prior domains (EOUT-COMPARE-04).

**Existing proofs are not retroactively changed.** Git confirms only new files were added (the
fixture and runner). Regression sample in this environment: LAB-RESULT-ENVELOPE-P2 **50/50**,
LAB-QUERY-P3 **44/44**, LAB-SIDEKIQ-P5 **48/48** all green; LAB-RACK-P14 sits at **58/60** due to
two pre-existing `map_get` VM-gap markers (`P14-MAP-04`, `P14-GAP-02`) that are self-describing
and **independent of this card** — this proof touched neither the P14 fixture nor its runner.

---

## Next Route Recommendation

**Recommended: LAB-EPISTEMIC-OUTCOME-P3 — reconciliation-consumer design note** (no gate; design
only). Specify how downstream DAG nodes consume `unknown_external_state` without upward coercion:
- the fail-closed propagation rule (unknown may not be read as success or failure),
- the reconcile → confirm → (retry-if-idempotent | compensate-if-named) lifecycle,
- where the idempotency precondition (P16) and No-Upward-Coercion rule (P15, Covenant:391-403) are
  enforced at contract boundaries,
- the reconciliation-consumer contract surface (the P2 `ReconciliationRouter` is a placeholder).

**After P3 (PROP + gate, not yet authorized):** the failure-taxonomy PROP on the PROP-044 variant
substrate (turns the Ch12 enum + `UnknownExternalOutcome`/`ObservedFailure` into a sealed
`Outcome[T,E]`), runtime-sequenced after variant/match VM execution is proved.

**Closed (no route opens these here):** sealed `Outcome[T,E]` implementation; variant/match runtime
authority; real storage writes / SQL / DB / sockets / workers / runtime I/O; canon spec or Covenant
edits; renaming `Result`/`Option`; promoting the lab KDR convention into canon; resolving the
PROP-035 numbering collision (STAB-P4 owns that).

---

## Gap Packet

```
proof:      lab-unknown-state-kdr-convention-proof / v0
status:     CLOSED — 54/54 PASS
authority:  governance / lab_only
date:       2026-06-10
domain:     storage write commit-acknowledgement loss

envelope:   OutcomeEnvelope (KDR; kind:String + idempotency_key:String + metadata:Map[String,String])
kinds:      succeeded | denied | timed_out | unknown_external_state | partial | cancelled | compensated
layers:     A=Ruby TypeChecker (9/9 accepted) | B=Rust VM (7 kinds executed) | C=consumer sim

primary_scenario:
  lost_ack → unknown_external_state    YES (NOT failed/system_error/upstream_unavailable)
  idempotency_key preserved as data    YES
  reconcile metadata preserved         YES
  mapper lost-ack → unknown not sys_err YES

invariants_proved:
  timeout_not_failure (P15):           YES — timed_out/unknown route to reconcile
  retry_gated_on_idempotency (P16):    YES — no key ⇒ no retry; denied never retried
  denial_distinct_from_unknown:        YES
  partial_distinct_from_unknown:       YES
  reconciliation_is_data_not_raise:    YES

explicit_answers:
  kdr_sufficient_v0:           YES
  proves_enforced_outcome:     NO
  authorizes_prop_impl:        NO
  timeout_becomes_failure:     NO (nowhere)
  retry_without_idempotency:   NO
  storagecapability_opens:     NO
  real_db_network_io_opens:    NO
  public_stable_authority:     NO

existing_proofs_changed:       NO (git: only new files; P14 58/60 pre-existing map_get VM-gap)
next_route:                    LAB-EPISTEMIC-OUTCOME-P3 (reconciliation-consumer design note)
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only — no sealed
`Outcome[T,E]`, no variant/match runtime authority. No canon spec or Covenant edits. No real storage
writes, SQL, DB, sockets, workers, or runtime I/O opened. `Result`/`Option` semantics untouched.
Ch12 treated as proposed (not accepted canon). PROP-035 numbering collision not resolved here. Old
Ruby framework surfaces not used as language authority. Lab behavior not accepted as canon. This doc
informs future gate decisions; it does not make them.
