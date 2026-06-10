# Lab: Epistemic Outcome as Variant and VM Match Proof — v0

**Card:** LAB-OUTCOME-VARIANT-P1  
**Status:** Proved (58/58 PASS)  
**Date:** 2026-06-10  
**Route:** LAB PROOF / VARIANT OUTCOME / VM EXECUTION / NO FAILURE TAXONOMY  
**Authority:** lab_only — not canon, not production

---

## Motivation

LAB-EPISTEMIC-OUTCOME-P4 (46/46 PASS) proved the reconciliation receipt routing
model through the Rust lab VM, but using the **KDR convention** (`kind: String`).
The routing logic was expressed as nested `if/else` with string equality comparisons.
This approach has two known limitations:

1. **P4 itself flagged STAB-P4**: the Ruby TypeChecker rejects `String ==` and `||`
   operators, so the P4 routing is Rust-VM-only, not dual-implementation.
2. **KDR is a convention, not a constraint**: nothing prevents a caller from providing
   `kind: "failed"` when the receipt should be `kind: "confirmed_succeeded"`. The
   exhaustiveness and arm identity live in the developer's head, not the typechecker.

LAB-VARIANT-RUST-P1 (39/39) and LAB-VARIANT-VM-P1 (42/42) proved that the Rust lab
toolchain can compile and execute `variant`/`match` source. This card closes the loop:
re-express the epistemic outcome routing as a real Igniter `variant` declaration with
exhaustive `match`, prove it compiles through the Rust TypeChecker (OOF-KIND1..5
enforcement), emits correct SemanticIR, and executes correct routing in the VM.

---

## Scope

**In scope (authorized writes):**
- `igniter-lab/igniter-view-engine/fixtures/epistemic_outcome/outcome_variant.ig`
- `igniter-lab/igniter-view-engine/fixtures/epistemic_outcome/outcome_variant_oof_kind1..5.ig`
- `igniter-lab/igniter-view-engine/proofs/verify_lab_outcome_variant_p1.rb`
- `igniter-lab/lab-docs/lang/lab-epistemic-outcome-as-variant-and-vm-match-proof-v0.md`
- `igniter-lang/.agents/work/cards/lang/LAB-OUTCOME-VARIANT-P1.md`
- `igniter-lab/.agents/portfolio-index.md`

**Closed (no writes):**
- Generic sealed `Outcome[T,E]` — not introduced
- Failure taxonomy proposal — not authored
- Ruby canon pipeline — unchanged
- `Value::Variant`, new VM opcodes — closed per LAB-VARIANT-VM-P1
- Production runtime authority — none claimed
- Real storage/network/DB I/O — none opened
- Automatic retry/compensation execution — none

---

## Core Formula

**OutcomeVariant v0 = ReconciliationOutcome variant + exhaustive match + VM execution**

```igniter
variant ReconciliationOutcome {
  ConfirmedSucceededReal        { request_id: String, resource: String }
  ConfirmedSucceededHuman       { request_id: String, resource: String }
  ConfirmedSucceededModel       { request_id: String, resource: String }
  ConfirmedFailedRetryable      { request_id: String, idempotency_key: String }
  ConfirmedFailedCompensatable  { request_id: String, compensation: String }
  ConfirmedFailedTerminal       { request_id: String }
  StillUnknownWithBudget        { request_id: String, attempt: Integer, budget_remaining: Integer }
  StillUnknownNoBudget          { request_id: String, attempt: Integer }
  PartiallyConfirmed            { request_id: String, resource: String }
  ReconciliationDenied          { request_id: String, reason: String }
  ReconciliationError           { request_id: String, detail: String }
}
```

**StillUnknown split:** The P3/P4 model had one `StillUnknown` arm gated by
`budget_remaining > 0`. Rather than forcing an `if`-expression into a match arm body
(which requires raw-AST field-name handling), the variant splits into
`StillUnknownWithBudget` and `StillUnknownNoBudget`. The semantics are preserved:
budget-present outcomes reconcile; budget-absent outcomes hold. The routing is
encoded in the arm name, not a hidden numeric check.

---

## Routing Table

| Arm | Action | Notes |
|-----|--------|-------|
| ConfirmedSucceededReal | accept | Real-world observation confirms success |
| ConfirmedSucceededHuman | accept | Human reviewer confirmed success (P13) |
| ConfirmedSucceededModel | needs_human_review | Model evidence cannot route directly to accept |
| ConfirmedFailedRetryable | retry | Idempotency key present (P16) |
| ConfirmedFailedCompensatable | compensate | Named compensation contract present (P17) |
| ConfirmedFailedTerminal | fail | No retry, no compensation path |
| StillUnknownWithBudget | reconcile_again | Budget present — re-enter reconciliation |
| StillUnknownNoBudget | hold | Budget exhausted — hold pending human escalation |
| PartiallyConfirmed | reconcile_remainder | Some sub-effects confirmed; reconcile the rest |
| ReconciliationDenied | hold | Authority refused; deterministic; not retried |
| ReconciliationError | hold | Reconciliation machinery error; not a success |

---

## No-Upward-Coercion Enforcement

The Covenant principle "No Upward Coercion" (Ch12, Epistemic State Machine) forbids:
- Model evidence routing directly to "accept"
- Unknown state routing directly to "retry" or "compensate"
- Denied/error states routing to any success action

In this proof, these invariants are enforced by **distinct arm names**, not string checks:
- `ConfirmedSucceededModel` is a separate arm from `ConfirmedSucceededReal`. They cannot
  be confused. The TypeChecker's OOF-KIND checks enforce exhaustiveness and arm identity.
- `StillUnknownWithBudget` routes to `"reconcile_again"`, never to `"retry"`.
- `ReconciliationDenied` and `ReconciliationError` both route to `"hold"`, never to
  `"accept"`, `"retry"`, or `"compensate"`.

The OUTVAR-NO-UPWARD section proves all five invariants via VM execution.

---

## KDR Convention Superseded for This Domain

The P4 proof used `kind: String` comparison with 11 string constants. This proof
replaces that with exhaustive `variant`/`match`. The routing semantics are equivalent
for the representative cases proved in OUTVAR-KDR-EQUIV. The structural difference:

| Dimension | P4 KDR | P1 Variant |
|-----------|--------|------------|
| Type of subject | String (convention) | ReconciliationOutcome (declared type) |
| Exhaustiveness | Developer-maintained | TypeChecker-enforced (OOF-KIND1) |
| Unknown arm | Impossible to prevent | Impossible to introduce (OOF-KIND2) |
| Duplicate arm | Not detectable | Blocked (OOF-KIND3) |
| Evidence identity | Hidden string check | Distinct named arms |
| VM representation | Record with `kind: String` | Record with `__arm: String` (Path B) |

---

## Contracts

| Contract | Purpose |
|----------|---------|
| `RouteOutcome` | input: ReconciliationOutcome → output: action String |
| `BuildSucceededReal` | Constructs ConfirmedSucceededReal with payload fields |
| `BuildSucceededHuman` | Constructs ConfirmedSucceededHuman |
| `BuildSucceededModel` | Constructs ConfirmedSucceededModel |
| `BuildFailedRetryable` | Constructs ConfirmedFailedRetryable with idempotency_key |
| `BuildFailedCompensatable` | Constructs ConfirmedFailedCompensatable with compensation |
| `BuildFailedTerminal` | Constructs ConfirmedFailedTerminal |
| `BuildStillUnknownWithBudget` | Constructs StillUnknownWithBudget with Integer fields |
| `BuildStillUnknownNoBudget` | Constructs StillUnknownNoBudget |
| `BuildReconciliationError` | Constructs ReconciliationError with detail field |
| `RouteBuiltOutcome` | Constructs ConfirmedSucceededReal then routes it in one contract |

---

## OOF Error Fixtures

| File | OOF Code | What it proves |
|------|----------|---------------|
| `outcome_variant_oof_kind1.ig` | OOF-KIND1 | Non-exhaustive match is blocked |
| `outcome_variant_oof_kind2.ig` | OOF-KIND2 | Unknown arm NonExistent is blocked |
| `outcome_variant_oof_kind3.ig` | OOF-KIND3 | Duplicate arm Succeeded is blocked |
| `outcome_variant_oof_kind4.ig` | OOF-KIND4 | Non-variant String subject is blocked |
| `outcome_variant_oof_kind5.ig` | OOF-KIND5 | Divergent arm result types are blocked |

---

## VM Runtime Representation

Following Path B (LAB-VARIANT-VM-P1), variants are lowered to records:

```json
{
  "__arm": "ConfirmedSucceededReal",
  "__variant": "ReconciliationOutcome",
  "request_id": "req-001",
  "resource": "payment/123"
}
```

The `__arm` field is the discriminant. `OP_GET_FIELD("__arm")` + `OP_EQ` drives routing.
Payload fields are present in the record and survive VM execution (OUTVAR-VM proves this
for Integer and String fields).

---

## Proof Result

**58/58 PASS** — `ruby igniter-lab/igniter-view-engine/proofs/verify_lab_outcome_variant_p1.rb`

| Section | Checks | Description |
|---------|--------|-------------|
| OUTVAR-COMPILE | 6 | Compilation, no OOF-KIND, SIR structure |
| OUTVAR-SIR | 6 | variant_decl shape, payload fields, match_node shape |
| OUTVAR-VM | 16 | All 11 arms routed; Integer fields survive; RouteBuiltOutcome |
| OUTVAR-OOF | 10 | All 5 OOF-KIND diagnostics fire; no valid SIR produced |
| OUTVAR-KDR-EQUIV | 8 | Representative P4 equivalence |
| OUTVAR-NO-UPWARD | 5 | Forbidden transition invariants |
| OUTVAR-CLOSED | 7 | Closed surface verification |

---

## What This Proves

- `ReconciliationOutcome` variant compiles, emits SIR, and executes in the lab VM
- Exhaustive match routing is enforced by OOF-KIND1; non-exhaustive match is blocked
- OOF-KIND2..5 protect against unknown/duplicate/non-variant/divergent arm definitions
- Payload fields with String and Integer types survive the full compile → VM path
- `RouteBuiltOutcome` proves the construct → route pipeline works in one contract
- No-Upward-Coercion invariants hold at the type level (distinct arm names, not string checks)
- The variant surface supersedes the KDR convention for this domain while the Path B
  runtime representation remains a record with `__arm` discriminant

## What This Does NOT Prove

- Generic sealed `Outcome[T,E]` — not introduced; still requires PROP-044-P7
- Any failure taxonomy — not authored
- Production runtime support — lab only
- Public/stable API — no API surface added
- Ruby canon authority — Ruby pipeline unchanged
- Real reconciliation execution — no storage, no scheduler, no retry/compensation

---

## Promotion Boundary

| Layer | Status |
|-------|--------|
| KDR convention (LAB-EPISTEMIC-OUTCOME-P2) | ✅ 54/54 |
| KDR routing state machine (LAB-EPISTEMIC-OUTCOME-P3) | ✅ 43/43 |
| KDR VM receipt flow (LAB-EPISTEMIC-OUTCOME-P4) | ✅ 46/46 |
| Rust variant/match front-end (LAB-VARIANT-RUST-P1) | ✅ 39/39 |
| Rust variant/match VM lowering (LAB-VARIANT-VM-P1) | ✅ 42/42 |
| **Epistemic outcome as variant (this)** | ✅ 58/58 |
| PROP-044-P7 sealed Outcome[T,E] | 🔒 Requires governance gate |
| LAB-FAILURE-TAXONOMY-P1 | 🔒 Proposal-planning only; unblocked by this proof |
