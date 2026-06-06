# Chapter 10: Contract Modifiers

Status: proposed
Stage: 3
Source PROP: PROP-031
Governance: META-EXPERT-013
Last updated: 2026-05-10

> **Proposed.** This chapter describes the contract modifier extension.
> Status advances to `accepted` when PROP-031 regression suite passes.

---

## �� 10.1 Overview

A contract modifier is an optional keyword that precedes the `contract` keyword.
It declares the contract's effect character at the declaration site ��� making the
relationship between a contract and the outside world explicit and compiler-checked.

```igniter
pure         contract ScoreRisk(contradiction_count: Integer, ...) -> risk: RiskScore
observed     contract ExtractClaims(article: NewsArticle, as_of: DateTime) -> claims: Collection[Claim]
effect       contract ChargeCustomer(customer_id: String, amount: Decimal[2]) -> receipt: ChargeReceipt
privileged   contract UnlockDoor(door_id: String, officer_id: String) -> opened: Bool
irreversible contract DispatchEmergency(incident_id: String) -> receipt: DispatchReceipt
```

A contract without a modifier is implicitly `pure`. All existing programs are
unaffected.

---

## �� 10.2 Grammar

```
contract-modifier  ::= "pure"
                     | "observed"
                     | "effect"
                     | "privileged"
                     | "irreversible"

contract-decl      ::= contract-modifier? "contract" ident type-params?
                       "(" param-list? ")" ("->" output-spec)?
                       "{" body-decl* "}"
```

The modifier is optional. No other grammar productions change.

---

## �� 10.3 Modifier Semantics

### pure

The contract performs no I/O and is deterministic. Given the same inputs,
it always produces the same outputs. `pure` is the default; a contract without
a modifier is treated as `pure`.

Compile-time constraint: the body must not contain `escape` declarations.
Violation: OOF-M1.

### observed

The contract reads from an external source (sensor, API, model, database) without
mutating it. The external world is unaware of the observation. The contract carries
an `escape` declaration naming the observation capability.

Example: extracting claims from an article using an ML model, reading a sensor
value at a point in time.

### effect

The contract mutates an external system in a way that can be reversed, compensated,
or refunded. The consequence is real but not permanent in the strongest sense.

Example: charging a payment gateway (charge can be refunded), sending a notification
(notification can be followed by a retraction).

### privileged

The contract performs an action that requires explicit operator authority. The
authority must be passed as a value or verified from context. Without the correct
authority, the contract is refused at compile time (Phase 2) or at the Gate.

Example: approving an expense over a threshold, unlocking a physical door,
prescribing medication.

### irreversible

The contract performs an action whose consequence cannot be undone. No compensation
is possible in the general case. The action requires explicit acknowledgment of
permanence at the call site.

Example: dispatching emergency units (cannot un-dispatch), GDPR deletion (data
is gone), wiring funds (cannot be recalled from recipient's bank).

---

## �� 10.4 Fragment Classification

| Modifier | Fragment class |
|----------|---------------|
| `pure` (default) | CORE (or ESCAPE if body contains TEMPORAL/STREAM ��� PROP-028 applies) |
| `observed` | ESCAPE |
| `effect` | ESCAPE |
| `privileged` | ESCAPE |
| `irreversible` | ESCAPE |

The modifier sets a lower bound on fragment class. It does not override upward
propagation. A `pure` contract with a `history_at` read is classified TEMPORAL
by PROP-028 rules.

---

## �� 10.5 SemanticIR

The `contract_ir` node gains a `modifier` field:

```json
{
  "kind": "contract_ir",
  "name": "ExtractClaims",
  "modifier": "observed",
  "fragment_class": "ESCAPE",
  "nodes": [...],
  "outputs": [...]
}
```

Default: `"pure"`. The field is always present in PROP-031+ compiled programs.

---

## �� 10.6 OOF Rules

| Code | Condition | Severity |
|------|-----------|----------|
| OOF-M1 | `pure contract` body contains `escape` declaration | error |
| OOF-M2 | `effect/privileged/irreversible` without Effect Surface fields | error (PROP-035) |
| OOF-M3 | `irreversible` without `compensation` or `no_compensation` | warn (PROP-035) |

OOF-M2 and OOF-M3 are reserved. They are enforced when PROP-035 (Effect Surface)
lands.

---

## �� 10.7 Relationship to Other Chapters

- **Ch2 (Source Surface):** modifier prefix is a grammar extension. Ch2 addendum
  references this chapter.
- **Ch4 (Fragment Classification):** modifier sets minimum fragment class per ��10.4.
  PROP-028 TEMPORAL classification composes independently.
- **Ch11 (Profile System):** profiles may restrict which modifiers are permitted.
  A `pure`-only profile rejects `effect` contracts at compile time. (Ch11, proposed.)
- **Ch12 (Effect Surface):** `effect`, `privileged`, and `irreversible` contracts
  require additional Effect Surface declarations. (Ch12, proposed.)
