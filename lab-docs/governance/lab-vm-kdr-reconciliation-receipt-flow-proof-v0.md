# Lab Governance Doc: VM KDR ReconciliationReceipt Flow Proof

**Track:** lab-vm-kdr-reconciliation-receipt-flow-proof-v0
**Card:** LAB-EPISTEMIC-OUTCOME-P4
**Category:** governance
**Date:** 2026-06-10
**Route:** LAB PROOF / VM KDR RECEIPT FLOW / NO OUTCOME VARIANT
**Status:** CLOSED — 46/46 PASS; ReconciliationReceipt flows through the lab VM as KDR; no promotion authorized

---

## Purpose

P2 proved a KDR `OutcomeEnvelope` can carry `unknown_external_state` as data. P3 designed
the reconciliation-consumer transition rules. **P4 proves a KDR `ReconciliationReceipt` can
be produced, carried, inspected, and routed through the lab Rust VM as ordinary record data**
— implementing the P3 transition guards as in-VM branching — **without** sealed `Outcome[T,E]`,
variant/match runtime authority, or real storage/network I/O.

This is **not** a runtime reconciliation system. It is a VM proof that the receipt shape the
reconciliation-consumer boundary needs is executable KDR **today**.

Authority: lab-only. `igniter-lang` is the language authority. PROPOSED Ch12 Effect Surface +
Covenant doctrine (P13/P15/P16/P17 + the Epistemic State Machine / No Upward Coercion) are the
references, **treated as proposed, not accepted canon**. The lab KDR convention is not promoted
to canon.

---

## What Was Built

| Artifact | Path |
|----------|------|
| Fixture (2 types, 5 contracts) | `igniter-view-engine/fixtures/epistemic_outcome/reconciliation_receipt_flow.ig` |
| Proof runner (46 checks) | `igniter-view-engine/proofs/verify_reconciliation_receipt_vm_flow.rb` |
| This doc | `lab-docs/governance/lab-vm-kdr-reconciliation-receipt-flow-proof-v0.md` |
| Card | `.agents/work/cards/governance/LAB-EPISTEMIC-OUTCOME-P4.md` |

### ReconciliationReceipt (KDR — 11 fields, VM-executed)

```
ReconciliationReceipt {
  kind:             String   — confirmed_succeeded | confirmed_failed | still_unknown
                             |  partially_confirmed | reconciliation_denied | reconciliation_error
  request_id:       String   — correlates to the original unknown envelope (required)
  resource:         String   — the effect target reconciled (required)
  idempotency_key:  String   — "" if absent; gates post-reconcile retry (P16)
  observed_at:      String   — when reconciliation observed the state; "" if n/a
  evidence_kind:    String   — real | human | model | absent (P13 — observation certainty)
  compensation:     String   — named compensation contract; "" | "no_compensation" (P17)
  attempt:          Integer  — prior attempt count (ordinal; numeric with budget)
  budget_remaining: Integer  — reconcile re-entry budget
  detail:           String
  metadata:         Map[String, String]  — raw receipt fields or absence marker
}
```

**`attempt` is typed `Integer`, not `String` (justification).** `attempt` is an ordinal count
the budget logic reasons about numerically alongside `budget_remaining: Integer` (the re-entry
guard compares `budget_remaining > 0`). Typing it `Integer` keeps both retry-budget fields in
one numeric domain — no `String → Int` coercion — and matches the Sidekiq `RetryEnvelope`
precedent (`attempt: Integer`). The only String-ish alternative would force a parse at the guard
site, which would itself be an upward coercion risk.

### The five contracts

- **`ReconcileFromLostAck`** — produces a receipt from a lost-ack `OutcomeEnvelope`, preserving
  the `idempotency_key` and pulling `request_id`/`resource` out of the envelope metadata via
  `map_get`/`or_else`; carries `evidence_kind` in from the reconciliation pass.
- **`MakeReceipt`** — general receipt builder (record literal).
- **`RouteReceipt`** — the heart: the P3 transition guards executed **in the VM** as nested
  `if/else` over `kind`, `evidence_kind`, `idempotency_key`, `compensation`, `budget_remaining`.
- **`RouteEnvelope`** — routes a raw `OutcomeEnvelope`; proves direct unknown→terminal routing is
  **absent / fail-closed** (unknown/timed_out/partial produce only `reconcile_required`).
- **`ReceiptInspector`** — `map_get`/`or_else` over `receipt.metadata` (VM map-chain).

---

## Proof Architecture (and a real Ruby/Rust divergence)

The router contracts branch with String `==` and (avoided) boolean `||`. This surfaced a genuine
**Ruby/Rust implementation divergence**, which the proof documents rather than hides:

- The **production Ruby TypeChecker** rejects String `==` and `||` ("Unsupported operator"), so
  `RouteReceipt`/`RouteEnvelope` are **BLOCKED in Layer A** (proved: RRF-DIVERGENCE-01).
- The **Rust compiler** accepts `==` (rejects only `||`, which the fixture avoids by nesting),
  and the **Rust VM executes the routing** (proved: RRF-DIVERGENCE-02).

Therefore the layering is honest about which implementation is authority for what:

- **Layer A — Ruby TypeChecker:** proves the receipt **type shape** (11 fields; `attempt`/
  `budget_remaining` Integer) and that the **producer/inspector** contracts are accepted.
- **Layer B — Rust compiler + VM:** proves the **routing execution** — every P3 transition.

**This divergence is flagged for governance (STAB-P4 class — Ruby/Rust operator-support drift),
not resolved here.** It is material: today the reconciliation *routing* layer is a Rust-VM-only
proof, not a dual-implementation proof. A future sealed `Outcome`/`match` would route on arms
rather than String `==`, side-stepping this specific operator gap — another reason the variant
path matters, once VM variant dispatch is proved.

**Result: 46/46 PASS.** Sections: RRF-COMPILE (4), RRF-TYPES (7), RRF-PRODUCE (4), RRF-ACCEPT (4),
RRF-FAILROUTE (4), RRF-LOOP (4), RRF-HOLD (3), RRF-NODIRECT (6), RRF-INSPECT (2),
RRF-DIVERGENCE (2), RRF-CLOSED (6).

---

## P3 Transitions Proved Under VM Execution

Every transition below was executed by the lab VM (`RouteReceipt`/`RouteEnvelope`), not modeled:

| P3 transition | Input | VM output | Check |
|---------------|-------|-----------|-------|
| confirmed_succeeded + real → accept | evidence_kind=real | `accept` | RRF-ACCEPT-01 |
| confirmed_succeeded + human → accept | evidence_kind=human | `accept` | RRF-ACCEPT-02 |
| confirmed_succeeded + **model** → needs_human_review | evidence_kind=model | `needs_human_review` | RRF-ACCEPT-03/04 |
| confirmed_failed + idempotency → retry | idempotency_key set | `retry` | RRF-FAILROUTE-01 |
| confirmed_failed + named compensation → compensate | compensation set, no idem | `compensate` | RRF-FAILROUTE-03 |
| confirmed_failed + neither → fail | no idem, no_compensation | `fail` | RRF-FAILROUTE-04 |
| still_unknown + budget → reconcile_again | budget_remaining>0 | `reconcile_again` | RRF-LOOP-01 |
| still_unknown + no budget → hold | budget_remaining=0 | `hold` | RRF-LOOP-02 |
| reconciliation_error + budget / no budget | — | `reconcile_again` / `hold` | RRF-LOOP-03/04 |
| reconciliation_denied → hold | — | `hold` | RRF-HOLD-01 |
| partially_confirmed → reconcile_remainder | — | `reconcile_remainder` | RRF-HOLD-02 |
| unrecognised kind → hold (fail-closed) | — | `hold` | RRF-HOLD-03 |
| **raw unknown/timed_out/partial → reconcile_required ONLY** | — | `reconcile_required` | RRF-NODIRECT-01/02/03/06 |

**No envelope kind for `unknown_external_state`/`timed_out`/`partial` yields a terminal
success/failure** (RRF-NODIRECT-06) — the only branch they reach is `reconcile_required`. That is
the No-Upward-Coercion rule made executable: there is literally no VM path from unknown to a
terminal accept/fail without going through reconciliation.

**`evidence_kind` is load-bearing under VM execution** (RRF-ACCEPT-04): the *same* receipt kind
`confirmed_succeeded` routes to `accept` with `real` evidence but to `needs_human_review` with
`model` evidence. The model→real upgrade is blocked at runtime, not just on paper.

**The receipt carries its reconciliation evidence through the VM** (RRF-PRODUCE-02/03/04): the
produced receipt preserves the `idempotency_key` (`idem-9`) from the unknown envelope and pulls
`request_id` (`r-9`) and `resource` (`users`) out of the envelope metadata.

---

## Explicit Answers (card-required)

**Can `ReconciliationReceipt` KDR flow through the VM today?** **Yes.** It is produced
(`ReconcileFromLostAck`/`MakeReceipt`), carried (11 typed fields incl. Integer `attempt`/
`budget_remaining`), inspected (`ReceiptInspector` map-chain), and routed (`RouteReceipt`) — all
VM-executed, 46/46.

**Which P3 transitions are VM-proved?** All of them — see the table above: accept (real/human),
needs_human_review (model), retry (idempotency), compensate (named), fail, reconcile_again /
hold (budget-gated), reconcile_remainder, hold (denied/unrecognised), and raw unknown/timed_out/
partial → reconcile_required only.

**Is `evidence_kind` preserved and load-bearing?** **Yes** — preserved through production
(RRF-PRODUCE-04) and load-bearing in routing (RRF-ACCEPT-03/04): model evidence cannot reach
`accept`.

**Is retry still idempotency-gated?** **Yes** — `confirmed_failed` → `retry` only with a non-empty
`idempotency_key` (RRF-FAILROUTE-01/02), under VM execution.

**Is compensation still named-contract-gated?** **Yes** — `confirmed_failed` → `compensate` only
with a named compensation (not `""`/`no_compensation`) (RRF-FAILROUTE-03/04).

**Does this use variant/match runtime?** **No.** Pure KDR record + `if/else`. The fixture declares
zero variants (RRF-COMPILE-04) and uses no `match`/`Outcome[` in code (RRF-CLOSED-01).

**Does this implement sealed `Outcome[T,E]`?** **No.** KDR only.

**Does this open real storage/network/DB/runtime I/O?** **No.** Pure contracts; the runner does no
file/network/db/socket/worker I/O (RRF-CLOSED-02/06).

**Does this authorize failure-taxonomy PROP implementation?** **No.** Evidence toward it, not
authority. No PROP authored.

**What exact route should follow?** **PROP-044-P7-READINESS** — a governance/design probe mapping
VM variant/match dispatch sequencing and risk (the true gate for any sealed `Outcome[T,E]`). Only
after P4 + P7-readiness should a failure-taxonomy proposal-planning card be considered. See Next
Route.

---

## KDR-Now / `Outcome[T,E]`-Later Bridge (updated by P4)

| Concern | KDR now (proved here) | Sealed `Outcome[T,E]` later |
|---------|----------------------|----------------------------|
| Receipt shape | `kind:String` record, VM-executed | variant arms |
| Routing | nested `if/else` on String `==` (Rust VM) | exhaustive `match` on arms |
| Forbidden transitions | no VM branch exists (fail-closed) | unrepresentable (type error) |
| `model → real` guard | `evidence_kind == "model"` → `needs_human_review` (RRF-ACCEPT-03) | typed observation conversion (P13) |
| Ruby/Rust parity | **diverges** — Ruby TC rejects `==`; routing is Rust-VM-only | a sealed `match` routes on arms, side-stepping the `==` gap |
| Status | executable today (46/46) | typecheck-expressible (PROP-044-P3/P5); VM dispatch unproved |

P4 confirms the KDR path is not just type-level but **executable end-to-end** today. The variant
path remains the way to make the forbidden transitions *unrepresentable* and to escape the Ruby/
Rust `==` divergence — but it is still gated on VM variant dispatch.

---

## Next Route Recommendation

**Recommended: PROP-044-P7-READINESS — VM variant/match dispatch sequencing and risk map**
(governance/design probe, no gate). The honest gate for any sealed `Outcome[T,E]` is whether
variant/match can *execute* in the VM (today it is typecheck-only, PROP-044-P5/P6). P7-readiness
should map: what VM dispatch a sealed-variant `match` requires, the sequencing against existing
opcodes, the risk surface, and how it would replace the String-`==` routing proved here (also
closing the Ruby/Rust `==` divergence this proof surfaced).

**Only after P4 + P7-readiness:** consider a failure-taxonomy proposal-planning card for sealed
`Outcome[T,E]`.

**Closed (no route opens these here):** sealed `Outcome[T,E]` implementation; variant/match runtime
authority; the failure-taxonomy PROP itself; canon spec/Covenant edits; real storage writes / SQL /
DB / network / sockets / workers / runtime I/O; public/stable API authority; the PROP-035 numbering
collision (STAB-P4 owns it); promoting the lab KDR convention into canon; changing `Result`/`Option`.

---

## Gap Packet

```
proof:      lab-vm-kdr-reconciliation-receipt-flow-proof / v0
status:     CLOSED — 46/46 PASS
authority:  governance / lab_only
date:       2026-06-10

receipt:    ReconciliationReceipt KDR — 11 fields; attempt:Integer + budget_remaining:Integer
            (attempt typed Integer: numeric with budget guard; no String→Int coercion; Sidekiq precedent)
layers:     A=Ruby TC (type shape + producers accepted) | B=Rust compiler+VM (routing executed)

vm_proved_transitions:
  confirmed_succeeded+real/human → accept
  confirmed_succeeded+model      → needs_human_review (NOT accept; P13 no upward coercion)
  confirmed_failed+idempotency   → retry (P16)
  confirmed_failed+named_comp    → compensate (P17)
  confirmed_failed+neither       → fail
  still_unknown/recon_error +budget → reconcile_again ; +no budget → hold
  partially_confirmed            → reconcile_remainder
  reconciliation_denied / unknown_kind → hold (fail-closed)
  raw unknown/timed_out/partial  → reconcile_required ONLY (no terminal success/failure)

evidence_kind_loadbearing: YES (same kind: real→accept, model→needs_human_review)
idem_carried_through_vm:   YES (idem-9 preserved); req_id/resource pulled from metadata
retry_idempotency_gated:   YES   compensation_named_gated: YES
uses_variant_match:        NO    implements_sealed_outcome: NO
opens_real_io:             NO    authorizes_failure_taxonomy_prop: NO

ruby_rust_divergence:      Ruby TC rejects String `==`/`||` (routers BLOCKED in Layer A);
                           Rust compiler accepts `==`, VM executes routing → routing is Rust-VM-only.
                           FLAGGED for STAB-P4 (operator-support drift); NOT resolved here.

regression: P2 54/54 green | P3 43/43 green | git: only new files added
next: PROP-044-P7-READINESS (VM variant/match dispatch sequencing + risk map)
      then (only after): failure-taxonomy proposal-planning card for sealed Outcome[T,E]
```

---

## Authority

lab-only — no canon claim, no stable surface, no framework compat. KDR convention only — no sealed
`Outcome[T,E]`, no variant/match runtime authority. No failure-taxonomy PROP authored. No canon spec
or Covenant edits. No new parser/typechecker/runtime surface (the Rust compiler/VM were used
read-only as the existing lab toolchain). No real storage writes, SQL, DB, network, sockets, workers,
or runtime I/O. `Result`/`Option` untouched. Ch12 treated as proposed, not accepted canon. PROP-035
numbering collision not resolved (STAB-P4 owns it). The Ruby/Rust `==` divergence is flagged, not
resolved. Old Ruby framework surfaces not used as language authority. Lab behavior not accepted as
canon. This doc informs future gate decisions; it does not make them.
