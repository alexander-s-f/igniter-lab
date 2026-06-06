# Chapter 12: Effect Surface

Status: proposed
Stage: 3 (Phase 2)
Source PROP: PROP-035 (not yet authored)
Governance: META-EXPERT-013
Last updated: 2026-05-10

> **Proposed.** This chapter describes the Effect Surface extension.
> Status advances to `accepted` when PROP-035 regression suite passes.
> PROP-035 authorship is gated on PROP-031 passing.

---

## �� 12.1 Overview

An `effect`, `privileged`, or `irreversible` contract must declare its Effect
Surface ��� a set of seven fields that make the contract's consequences explicit and
compiler-verifiable.

```igniter
effect contract ChargeCustomer(customer_id: String, amount: Decimal[2], currency: String)
  -> receipt: ChargeReceipt
  affects  external PaymentGateway.ChargeEndpoint
  authority billing_operator
  reversibility :compensatable
  idempotency key content_hash(customer_id, amount, currency)
  receipt  ChargeReceipt
  failure  PaymentFailure
  compensation RefundCustomer
  via audited_billing
{
  ...
}
```

The Effect Surface separates the *declaration of consequence* from the *body of
computation*. A reader can understand the full external impact of a contract by
reading the surface alone, without inspecting the body.

`pure` and `observed` contracts do not carry an Effect Surface. `observed` contracts
may carry `receipt` and `failure` for the observation result, but the remaining
fields are not applicable.

---

## �� 12.2 Grammar

```
effect-surface ::= affects-clause
                   authority-clause?
                   reversibility-clause
                   idempotency-clause
                   receipt-clause
                   failure-clause
                   compensation-clause?

affects-clause       ::= "affects" ("external" | "internal") qualified-name
authority-clause     ::= "authority" ident
reversibility-clause ::= "reversibility" reversibility-value
reversibility-value  ::= ":reversible" | ":compensatable" | ":refundable"
                       | ":append_only" | ":irreversible" | ":destructive"
idempotency-clause   ::= "idempotency" ("key" expr | "natural" | "none")
receipt-clause       ::= "receipt" type-ref
failure-clause       ::= "failure" type-ref
compensation-clause  ::= "compensation" contract-ref | "no_compensation"
```

The Effect Surface appears between the return type and the `via` clause in a
contract declaration.

---

## �� 12.3 The Seven Fields

### affects

Names the external or internal system that the contract mutates. Required for all
three modifiers. The `external` keyword signals that the named system is outside
the current igniter-lang application boundary.

### authority

Names the authority role required to execute this contract. Required for
`privileged` and `irreversible`. Optional for `effect`. When present, the runtime
verifies the authority before execution.

### reversibility

Declares where the action sits on the reversibility scale:

| Value | Meaning |
|-------|---------|
| `:reversible` | Can be undone without consequence |
| `:compensatable` | Cannot be undone, but can be compensated |
| `:refundable` | Monetary or resource compensation is possible |
| `:append_only` | Data can be appended but not deleted |
| `:irreversible` | No compensation is possible |
| `:destructive` | Data is deleted or permanently altered |

### idempotency

Declares the idempotency contract for this operation. Required for all three
modifiers. Non-idempotent operations under automatic retry are a compile-time error.

- `key expr`: the operation is idempotent when the key expression matches a prior call
- `natural`: the operation is naturally idempotent (e.g., `SET x = 5`)
- `none`: explicitly declares non-idempotency; prohibited in retry-enabled profiles

### receipt

Names the type of audit proof emitted when the operation completes. The receipt
is returned as part of the contract's output.

### failure

Names the error type emitted when the operation fails. This is not an exception ���
it is a declared output variant. The full error taxonomy includes seven possible
outcomes:

| Outcome | Description |
|---------|-------------|
| `succeeded` | Operation completed as expected |
| `failed` | Operation returned a known error |
| `partial` | Operation partially completed |
| `timed_out` | Time limit exceeded ��� outcome unknown |
| `unknown_external_state` | Request sent, no confirmation received |
| `compensated` | Failure triggered compensation |
| `cancelled` | Operation was cancelled before completion |

`unknown_external_state` is not a failure. It signals that a reconciliation pass
is required before retrying.

### compensation

Names the contract that reverses or compensates for the operation if it must be
undone. Required for `irreversible` contracts unless `no_compensation` is declared.
Optional for `effect` and `privileged`.

---

## �� 12.4 Reversibility Scale

```
reversible < compensatable < refundable < append_only < irreversible < destructive
```

A profile may declare a maximum reversibility level. An `irreversible` contract
in a profile that only permits `compensatable` is a compile-time error (OOF-M2).

---

## �� 12.5 OOF Rules

| Code | Condition | Severity |
|------|-----------|----------|
| OOF-M2 | `effect/privileged/irreversible` missing required Effect Surface fields | error |
| OOF-M3 | `irreversible` without `compensation` or `no_compensation` | warn |
| OOF-M4 | `idempotency: none` used in a retry-enabled profile | error |
| OOF-M5 | `reversibility` exceeds profile maximum | error |

---

## �� 12.6 Relationship to Other Chapters

- **Ch10 (Contract Modifiers):** Effect Surface applies only to `effect`, `privileged`,
  and `irreversible` contracts. Ch10 is a prerequisite.
- **Ch11 (Profile System):** profile `allowed_effects` restricts `affects` targets;
  `reversibility` maximum enforces OOF-M5.
- **Ch6 (SemanticIR):** the Effect Surface fields are emitted into the `contract_ir`
  node as a structured `effect_surface` object.
