# LAB-DYNAMIC-CONTRACT-DISPATCH-P1: Dynamic Dispatch Safety Boundary

Date: 2026-06-13
Card: LAB-DYNAMIC-CONTRACT-DISPATCH-P1
Status: CLOSED — PROVED 30/30 — EVIDENCE + SAFETY BOUNDARY
Authority: lab-only — no canon claim, no stable-API surface, no implementation

---

## Context

`rule_engine` and `vector_editor` both use `call_contract`, but in structurally
different forms. LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 landed and removed LAB-RACK-P9,
so the output boundary now rejects `Unknown`-to-concrete assignments (OOF-TY1).
The open question is which `call_contract` forms are safe, which are blocked by the
new boundary, and what the policy should be before any dynamic dispatch implementation
is attempted.

This card answers the five questions from the trigger exactly, then closes with a
safety classification table and a no-implementation boundary statement.

---

## Q1. Which apps use dynamic callee variables?

**One site, one app:**

```
igniter-apps/rule_engine/engine.ig:17-18
  compute raw_decisions = map(rules, r -> call_contract(r, t))
```

`r` is a `String` drawn from `input rules : Collection[String]`. This is a
**Tier 2 (non-literal) callee** — the compiler cannot statically resolve the
target contract name at typecheck time.

Every other app in the fleet (155 `call_contract` calls across 32 files) uses
a string literal as the first argument.

---

## Q2. Which use literal user-contract `call_contract`?

**155 calls in 32 files** — all using string literal callees.

Representative examples:

| App | File | Callee literal |
|-----|------|----------------|
| vector_editor | document.ig:31 | `"AppendObjectToLayer"` |
| vector_editor | tools.ig:30 | `"AddObjectToDoc"` |
| vector_editor | tools.ig:42 | `"CreateAndAppendRect"` |
| rule_engine | example.ig:41-43 | `"ExecuteRules"` (×3) |
| arch_patterns | pipeline.ig | `"ApplyEvent"`, `"CheckTransition"` |
| neural_net | network.ig | `"DenseLayer2x2"`, `"ReLU"`, etc. |
| sim_framework | various | 33 literal calls |

Literal callees are **Tier 1** — statically resolved by the TypeChecker in both
toolchains. LAB-RUBY-CALL-CONTRACT-PARITY-P3 (56/56 PASS) closed Tier 1 parity.

---

## Q3. Which return Unknown?

**One contract: `ExecuteRules` in `rule_engine/engine.ig`.**

The Unknown propagates via the Tier 2 dynamic callee path:

```
Line 17-18:  call_contract(r, t)              → Unknown         (Tier 2 result)
Line 17:     map(rules, r -> ...)             → Collection[Unknown]
Line 26-28:  filter(raw_decisions, d -> ...)  → Collection[Unknown]
Line 27:     d.action                         → gap: field access on Unknown (RE-P03)
Line 30:     output active_decisions :
               Collection[RuleDecision]       → output boundary fires (Q4)
```

All 155 literal-callee calls resolve to the declared output type of the target
contract. None return Unknown.

---

## Q4. Which output boundaries now catch them?

**`engine.ig:30` — `output active_decisions : Collection[RuleDecision]`**

| Toolchain | Diagnostics | Rule | Message |
|-----------|-------------|------|---------|
| Rust TC   | 2 × OOF-TY1 | OOF-TY1 | `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]` |
| Rust TC   | — | OOF-TY1 | `Output type mismatch: expected RuleDecision, got Unknown` |
| Ruby TC   | 2 active | — | `Unresolved symbol: d` (Tier 2 binding gap RE-P02/RE-P07) |
| Ruby TC   | — | — | `Unresolved field: Unknown.action` (cascade RE-P03) |

**Mechanism:** LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 replaced the LAB-RACK-P9 guard
(`type_name(&actual) != "Unknown"` short-circuit) with recursive
`structurally_assignable()`. Decision rule D2 (`actual == Unknown → false`)
now fires, which causes both the outer `Collection[Unknown]` and the inner
element `Unknown` to produce OOF-TY1. This is **safety-positive** — the output
boundary is load-bearing.

The Ruby TC gap differs in shape: the result of `call_contract(r, t)` is not
bound into `symbol_types` at the compute step, so `d` is unresolved rather than
typed as Unknown. The net effect is the same — the pipeline from dynamic callee
to typed output produces errors, not silent coercion.

---

## Q5. What safety policy is acceptable before any implementation?

Three forms, three statuses:

### ACCEPTED — Tier 1 literal callee

Form: `call_contract("ContractName", args...)`  
Condition: first argument is a string literal; contract exists in same module.

- Statically resolved by both TypeCheckers
- Output type verifiable at TC time via registry lookup
- No Unknown propagation
- OOF-TY0 fires on all fail-closed paths (arity, purity, self-recursion,
  unknown name)
- 155 sites / 32 files / confirmed clean

**Policy: ACCEPTED with no further gate.**

---

### QUARANTINED — Tier 2 dynamic callee with explicit Unknown output

Form: `call_contract(variable, args...)` with `output foo : Unknown` annotation.

- No call_contract error from TC (Tier 2 path)
- Result typed as Unknown; output declared Unknown → D3 rule passes (any → Unknown)
- No type safety at the output boundary — caller explicitly acknowledges this
- `output foo : Unknown` is the sanctioned escape hatch per LANG-OUTPUT-TYPE-ASSIGNABILITY-P1 §D3

**Policy: QUARANTINED — permissible only with explicit `output : Unknown`
annotation. No current lab app uses this form. No positive capability granted.
VM fail-closed guards (LAB-RACK-P9) still protect runtime dispatch.**

---

### BLOCKED — Tier 2 dynamic callee with typed output

Form: `call_contract(variable, args...)` with concrete output annotation.

- Call itself produces no error (Tier 2 path)
- Unknown flows to concrete output → OOF-TY1 in Rust TC
- Ruby TC: binding gap causes Unresolved symbol / Unresolved field cascade
- `rule_engine/ExecuteRules` is the sole instance; it is blocked by this policy

**Policy: BLOCKED. No path forward until one of: (a) output declared Unknown
(escaping to QUARANTINED), (b) validation receipt semantics landed, or
(c) Tier 2 type narrowing specified in canon. None of these are in scope.**

---

### DEFERRED — Field access on Unknown-derived result

Form: `d.action` where `d : Unknown` (downstream of Tier 2 result).

- Ruby TC: `Unresolved field: Unknown.action` (RE-P03)
- Rust TC: field access on Unknown is permissive under P9/P11 rules (not OOF)
- Toolchain divergence: Ruby is stricter than Rust here
- Route: **LAB-UNKNOWN-FIELD-ACCESS-P1** — separate card, not in this scope

**Policy: DEFERRED. Toolchain divergence documented. No acceptance.**

---

## Safety Classification Table

| Form | Example | Status | Gate |
|------|---------|--------|------|
| Literal callee, same module | `call_contract("Validate", x)` | ACCEPTED | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| Dynamic callee, Unknown output | `call_contract(name) → Unknown` | QUARANTINED | Must declare `output : Unknown` |
| Dynamic callee, typed output | `call_contract(name) → Collection[T]` | BLOCKED | OOF-TY1 at boundary (D2) |
| Field access on Unknown | `d.action` where `d : Unknown` | DEFERRED | LAB-UNKNOWN-FIELD-ACCESS-P1 |

---

## No Implementation Route Open

This card does not authorize and does not route to:

- Any implementation of dynamic callee dispatch
- Runtime reflection or duck-typing surface
- Plugin/middleware pipeline model
- Validation receipt semantics (mentioned as future work in
  LANG-OUTPUT-TYPE-ASSIGNABILITY-P1; not yet scoped in canon)
- Cross-module dynamic dispatch

---

## Proof

```
proof runner:  igniter-lab/igniter-apps/rule_engine/verify_dynamic_dispatch_p1.rb
checks:        30/30 PASS
sections:      A (preconditions) / B (Rust TC boundary) / C (Ruby TC Tier 2) /
               D (Ruby TC Tier 1 control) / E (safety policy) / F (closed surfaces)
```

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline post P-series |
| LAB-UNKNOWN-FIELD-ACCESS-P1 | Field projection policy over Unknown |
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Implementation planning for parametric container assignability |
