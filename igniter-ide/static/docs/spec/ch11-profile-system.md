# Chapter 11: Profile System

Status: proposed
Stage: 3 (Phase 2)
Source PROP: PROP-034 (not yet authored)
Governance: META-EXPERT-013
Last updated: 2026-05-12

> **Proposed.** This chapter describes the profile system extension.
> Status advances to `accepted` when PROP-034 regression suite passes.
> PROP-034 authorship is gated on PROP-031 + PROP-032 passing.

---

## �� 11.1 Overview

A profile is a named, compile-time policy declaration that binds to a contract
via the `via` clause. It declares what the contract is *obligated* to do and
*restricted* from doing ��� independently of the contract body.

```igniter
profile audited_billing {
  time: explicit
  lifecycle: :audit
  backend: :ledger
  evidence: required
  allowed_effects: [payment_gateway.charge, ledger.write]
  requires_authority: [billing_operator]
}

effect contract ChargeCustomer(customer_id: String, amount: Decimal[2])
  via audited_billing
{
  ...
}
```

The compiler validates that the contract body satisfies the profile's obligations
and does not exceed its restrictions. A contract without `via` uses the implicit
`default` profile, which imposes no additional constraints.

---

## �� 11.2 Grammar

```
profile-decl  ::= "profile" ident "{" profile-prop* "}"

profile-prop  ::= time-prop
               | lifecycle-prop
               | backend-prop
               | evidence-prop
               | allowed-effects-prop
               | requires-authority-prop
               | loop-prop
               | heartbeat-prop
               | checkpoint-prop
               | cancellation-prop
               | max-step-latency-prop

via-clause    ::= "via" ident

contract-decl ::= contract-modifier? "contract" ident type-params?
                  "(" param-list? ")" ("->" output-spec)?
                  via-clause?
                  "{" body-decl* "}"
```

`profile-decl` is a new top-level declaration alongside `contract`, `type`, and
`olap_point`. The `via-clause` is an optional extension to `contract-decl`.

---

## �� 11.3 Profile Properties

| Property | Values | Meaning |
|----------|--------|---------|
| `time` | `explicit`, `implicit`, `none` | Whether `as_of: DateTime` is required on the contract |
| `lifecycle` | `:session`, `:durable`, `:audit` | Minimum persistence tier for outputs |
| `backend` | `:memory`, `:ledger`, `:external` | Required storage backend |
| `evidence` | `required`, `optional`, `none` | Whether `output ... evidence [...]` is mandatory |
| `allowed_effects` | list of capability symbols | Restricts which `escape` capabilities the body may declare |
| `requires_authority` | list of authority symbols | Contract must receive matching authority |
| `loop` | `none`, `finite_loop`, `fuel_bounded`, `convergent`, `service` | Permitted loop class |
| `heartbeat` | `required`, `optional`, `none` | Service loop heartbeat obligation |
| `checkpoint` | `required`, `optional`, `none` | Service loop checkpoint obligation |
| `cancellation` | `required`, `optional`, `none` | Service loop cancellation handling obligation |
| `max_step_latency` | duration | Maximum time budget per loop step |

---

## �� 11.4 Compiler Enforcement

Profile-system diagnostics use the `OOF-PROF*` namespace. `OOF-PR*` is reserved
for PROP-037 progression diagnostics.

For each contract with a `via` clause, the compiler checks:

1. **Obligations met**: if `evidence: required`, every `output` in the body must
   carry an `evidence [...]` clause. If `time: explicit`, the contract must declare
   `input as_of: DateTime`.

2. **Restrictions not exceeded**: if `allowed_effects` is set, no `escape`
   declaration in the body may name a capability outside the list. Violation:
   OOF-PROF1.

3. **Authority**: if `requires_authority` is set, the contract modifier must be
   `privileged` or `irreversible`. Violation: OOF-PROF2.

4. **Loop class**: if `loop: service` is declared, the contract modifier must be
   absent or use the `service contract` form (Ch13). Violation: OOF-PROF3.

---

## �� 11.5 Stdlib Profiles

The stdlib ships seven built-in profiles:

| Profile | Intended use |
|---------|-------------|
| `pure` | Pure computation only; no escape, no evidence |
| `simple_compute` | Lightweight compute; session lifecycle |
| `audited_compute` | Evidence required; durable lifecycle; ledger backend |
| `mesh` | Distributed computation; causal consistency |
| `safety_critical` | Strong consistency; evidence required; authority required |
| `agent_planning` | Fuel-bounded convergent loops; audit lifecycle |
| `emergency_service` | Service loop with all three obligations; strong consistency |

Full property tables for each profile are specified in PROP-034.

---

## �� 11.6 Relationship to Other Chapters

- **Ch10 (Contract Modifiers):** profiles may restrict which modifiers are permitted
  (e.g., a `pure`-only profile rejects `effect` contracts). Ch10 is a prerequisite.
- **Ch12 (Effect Surface):** the `allowed_effects` profile property validates
  against the Effect Surface fields in Ch12.
- **Ch13 (Managed Recursion):** the `loop`, `heartbeat`, `checkpoint`,
  `cancellation`, and `max_step_latency` properties govern service loops defined
  in Ch13.
