# Card: LAB-EPISTEMIC-OUTCOME-P4
**Category:** governance
**Track:** lab-vm-kdr-reconciliation-receipt-flow-proof-v0
**Status:** CLOSED — PROVED
**Gate result:** 46/46 PASS
**Date closed:** 2026-06-10
**Route:** LAB PROOF / VM KDR RECEIPT FLOW / NO OUTCOME VARIANT

---

## Goal

Prove a KDR `ReconciliationReceipt` can be produced, carried, inspected, and routed through the
lab Rust VM as ordinary record data — implementing the P3 reconciliation-consumer transition
guards as in-VM branching — without sealed `Outcome[T,E]`, variant/match runtime authority, or
real storage/network I/O. Not a runtime reconciliation system; a VM proof the receipt shape is
executable KDR today.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-EPISTEMIC-OUTCOME-P1 | ✅ DONE — taxonomy + unknown-state boundary |
| LAB-EPISTEMIC-OUTCOME-P2 | ✅ DONE — KDR carries unknown state (54/54) |
| LAB-EPISTEMIC-OUTCOME-P3 | ✅ DONE — reconciliation-consumer boundary design (43/43) |
| LAB-STORAGE-CAPABILITY-P2 | ✅ DONE — mocked execution boundary; QueryExecutionReceipt |
| LAB-VM-MAP-P1 | ✅ DONE — map_get VM runtime (48/48) |
| LAB-RECORD-VM-P3 | ✅ DONE — nested record field values |
| PROP-044-P6 | ✅ DONE — variant+match SemanticIR emitter — NOT used (KDR-only) |
| Covenant P13 / P15 / P16 / P17 + Epistemic State Machine | ✅ doctrine |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture (2 types, 5 contracts) | `igniter-view-engine/fixtures/epistemic_outcome/reconciliation_receipt_flow.ig` | ✅ DONE |
| Proof runner (46 checks) | `igniter-view-engine/proofs/verify_reconciliation_receipt_vm_flow.rb` | ✅ DONE |
| Proof doc | `lab-docs/governance/lab-vm-kdr-reconciliation-receipt-flow-proof-v0.md` | ✅ DONE |
| This card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P4.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

---

## ReconciliationReceipt (KDR — VM-executed)

11 fields: `kind, request_id, resource, idempotency_key, observed_at, evidence_kind,
compensation, attempt:Integer, budget_remaining:Integer, detail, metadata:Map[String,String]`.

**`attempt` typed Integer** (chosen over String): ordinal count the budget guard reasons about
numerically alongside `budget_remaining:Integer`; no String→Int coercion; matches Sidekiq
RetryEnvelope precedent.

---

## Proof Sections (46/46)

```
RRF-COMPILE   (4)  — Ruby TC runs; Rust SIR 5 contracts; producers accepted; no variants
RRF-TYPES     (7)  — 11-field receipt; attempt+budget Integer; metadata Map
RRF-PRODUCE   (4)  — VM produces receipt from lost-ack; preserves idem; pulls req_id/resource
RRF-ACCEPT    (4)  — confirmed_succeeded routing; evidence_kind load-bearing (model≠accept)
RRF-FAILROUTE (4)  — confirmed_failed → retry|compensate|fail by guard
RRF-LOOP      (4)  — still_unknown / reconciliation_error budget-gated loop vs hold
RRF-HOLD      (3)  — reconciliation_denied → hold; partial → remainder; unknown kind → hold
RRF-NODIRECT  (6)  — raw unknown/timed_out/partial → reconcile_required ONLY (no terminal)
RRF-INSPECT   (2)  — map_get over receipt.metadata
RRF-DIVERGENCE(2)  — Ruby TC blocks routers (== unsupported); Rust VM executes them
RRF-CLOSED    (6)  — KDR-only; no variant/match; no sealed Outcome; no real I/O; lab-only
```

---

## Key Findings

| Finding | Detail |
|---------|--------|
| Receipt flows through VM | produced, carried (11 typed fields), inspected (map-chain), routed — all VM-executed |
| All P3 transitions VM-proved | accept/needs_human_review/retry/compensate/fail/reconcile_again/hold/reconcile_remainder |
| evidence_kind load-bearing at runtime | same kind: real→accept, model→needs_human_review (No Upward Coercion executable) |
| No direct unknown→terminal | unknown/timed_out/partial reach ONLY reconcile_required in the VM (no accept/fail branch) |
| idempotency preserved through VM | produced receipt keeps idem-9; req_id/resource pulled from envelope metadata |
| retry idem-gated / compensate named-gated | enforced in-VM via nested if-else |
| **Ruby/Rust divergence** | Ruby TC rejects String `==`/`||` (routers BLOCKED); Rust VM executes routing — routing is Rust-VM-only; flagged for STAB-P4 |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| ReconciliationReceipt KDR flows through VM today? | **YES** — 46/46 |
| Which P3 transitions VM-proved? | all (accept/human-review/retry/compensate/fail/reconcile_again/hold/remainder/reconcile_required) |
| evidence_kind preserved & load-bearing? | **YES** — model cannot reach accept |
| retry still idempotency-gated? | **YES** (P16) |
| compensation still named-contract-gated? | **YES** (P17) |
| uses variant/match runtime? | **NO** — KDR + if/else only |
| implements sealed `Outcome[T,E]`? | **NO** |
| opens real storage/network/DB/runtime I/O? | **NO** |
| authorizes failure-taxonomy PROP impl? | **NO** |
| exact next route? | **PROP-044-P7-READINESS** (VM variant/match dispatch sequencing + risk map) |

---

## Gap Packet

```
proof:      lab-vm-kdr-reconciliation-receipt-flow-proof / v0
status:     CLOSED — 46/46 PASS
authority:  governance / lab_only
date:       2026-06-10

receipt:    ReconciliationReceipt KDR 11-field; attempt:Integer + budget_remaining:Integer
layers:     A=Ruby TC (type shape + producers accepted) | B=Rust VM (routing executed)

vm_proved:  cs+real/human→accept | cs+model→needs_human_review | cf+idem→retry |
            cf+named→compensate | cf+neither→fail | still_unknown/recon_error+budget→reconcile_again|hold |
            partially_confirmed→reconcile_remainder | recon_denied/unknown→hold |
            raw unknown/timed_out/partial→reconcile_required ONLY (no terminal)

answers: kdr_flows_vm YES | evidence_kind_loadbearing YES | retry_idem_gated YES
         compensate_named_gated YES | uses_variant_match NO | sealed_outcome NO
         opens_io NO | authorizes_prop NO

ruby_rust_divergence: Ruby TC rejects String ==/|| (routers BLOCKED Layer A);
                      Rust VM executes routing → Rust-VM-only; FLAGGED STAB-P4; NOT resolved
regression: P2 54/54 | P3 43/43 green; git: only new files
next: PROP-044-P7-READINESS (VM variant/match dispatch sequencing + risk map)
      then only: failure-taxonomy proposal-planning for sealed Outcome[T,E]
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only — no sealed
`Outcome[T,E]`, no variant/match runtime authority, no failure-taxonomy PROP authored. No canon spec
or Covenant edits. No new parser/typechecker/runtime surface (Rust compiler/VM used read-only as the
existing lab toolchain). No real storage writes, SQL, DB, network, sockets, workers, or runtime I/O.
`Result`/`Option` untouched. Ch12 treated as proposed, not accepted canon. PROP-035 numbering
collision not resolved (STAB-P4 owns it). Ruby/Rust `==` divergence flagged, not resolved. Old Ruby
framework surfaces not used as language authority. Lab behavior not accepted as canon. This card
informs future gate decisions; it does not make them.
