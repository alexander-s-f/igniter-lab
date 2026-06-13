# lab-rule-engine-baseline-p1-v0

**Card:** LAB-RULE-ENGINE-BASELINE-P1  
**Date:** 2026-06-13  
**Status:** CLOSED — 52/52 PASS  
**Predecessors:** LAB-DYNAMIC-CONTRACT-DISPATCH-P1 · LAB-UNKNOWN-FIELD-ACCESS-P1 · LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 · APP-RECHECK-WAVE-P7

---

## Purpose

Freeze the current blocked baseline of the `rule_engine` app after all P-series safety
work. The goal is **not** to unblock rule_engine. The goal is to pin its exact diagnostic
state so future implementation work (dynamic dispatch, validation receipts, HOF lambda
error propagation alignment) cannot accidentally weaken the safety boundary.

---

## Frozen Diagnostic State (Wave P7 / 2026-06-13)

### Rust TC

```
Status:       oof
Diagnostics:  2× OOF-TY1
  [OOF-TY1] Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]  (node: active_decisions)
  [OOF-TY1] Output type mismatch: expected RuleDecision, got Unknown  (node: decision)
Source hash:  sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b
Liveness:     tc_infer=6 / fr_walk=6 / no breaches
```

### Ruby TC

```
Status:       oof
Diagnostics:  2× OOF-P1
  [OOF-P1] Unresolved symbol: d
  [OOF-P1] Unresolved field: Unknown.action
```

---

## Source Structure

| File | Module | Role |
|------|--------|------|
| `types.ig` | RuleEngineTypes | Defines `Transaction` and `RuleDecision` record types |
| `rules.ig` | RuleEngineRules | 3 rule contracts: `HighValueRule`, `ForeignCurrencyRule`, `FraudScoreRule` |
| `engine.ig` | RuleEngineCore | `ExecuteRules` — contains Tier 2 dynamic callee + Unknown field access |
| `example.ig` | RuleEngineExample | `RunRuleEngine` — invokes ExecuteRules with literal Tier 1 callees |

---

## Blocked Sites

### Site 1 — Dynamic callee (engine.ig:17-18)

```igniter
compute raw_decisions = map(rules, r ->
  call_contract(r, t)
)
```

`r : String` from `Collection[String]`. Variable callee — Tier 2 (not statically resolvable).

**Result chain:**  
`call_contract(r, t)` → `Unknown` → `map(...)` → `Collection[Unknown]` → output boundary →  
Rust: OOF-TY1 `Collection[Unknown] → Collection[RuleDecision]` (D2 rule: Unknown-at-depth)

**Classification:** BLOCKED (typed output + dynamic callee). Quarantine path: declare  
`output : Unknown` — removes Rust OOF-TY1 but Ruby OOF-P1 remains (HOF lambda body  
propagation path unchanged).

---

### Site 2 — Unknown field access (engine.ig:27)

```igniter
compute active_decisions = filter(raw_decisions, d ->
  if d.action == "SKIP" { false } else { true }
)
```

`d` is the element type of `Collection[Unknown]`. Lambda param bound to Unknown.

**Ruby TC path:**  
`d` is Unknown → `Unresolved symbol: d` (OOF-P1, typechecker.rb:929) →  
`d.action` on Unknown → `Unresolved field: Unknown.action` (OOF-P1, typechecker.rb:966-967)  
Both OOF-P1 propagate from lambda body (same `type_errors` reference — not `temp_errors`).

**Rust TC path:**  
`filter` HOF uses `temp_errors = Vec::new()` for lambda body typecheck (typechecker.rs:2975, 3075).  
OOF-P1 is silenced inside HOF lambda. Rust compensates via OOF-TY1 at output boundary.

**Documented divergence:** LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 (successor).

---

## Safety Policy Summary (inherited from predecessors)

| Form | Status |
|------|--------|
| Tier 1 literal callee | ACCEPTED |
| Tier 2 dynamic callee + typed output | BLOCKED (OOF-TY1 D2) |
| Tier 2 dynamic callee + `output : Unknown` | QUARANTINED (OOF-TY1 removed; Ruby OOF-P1 remains) |
| Field access on Unknown — direct context | BLOCKED (OOF-P1 both TCs) |
| Field access on Unknown — HOF lambda (Ruby) | BLOCKED (OOF-P1 propagates) |
| Field access on Unknown — HOF lambda (Rust) | SILENCED; OOF-TY1 compensates at boundary |

---

## Causal Chain

```
LANG-OUTPUT-TYPE-ASSIGNABILITY-P4
  └─ removed LAB-RACK-P9 guard in Rust TC
  └─ structurally_assignable D2: Unknown → false at any depth
  └─ Rust TC now fires OOF-TY1 for Collection[Unknown] → Collection[RuleDecision]

LAB-DYNAMIC-CONTRACT-DISPATCH-P1
  └─ confirmed 1 dynamic callee site / 155 literal callee sites
  └─ established ACCEPTED / QUARANTINED / BLOCKED / DEFERRED policy table

LAB-UNKNOWN-FIELD-ACCESS-P1
  └─ confirmed HOF lambda divergence: Ruby propagates / Rust silences
  └─ confirmed output safety not bypassed in either TC
  └─ confirmed no unblock route in current stage

APP-RECHECK-WAVE-P7
  └─ Wave P6: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved tx1 → Transaction (RE-P07 partial)
  └─ Wave P7: remaining Ruby diags: d + Unknown.action (2 diags, not 3)

LAB-RULE-ENGINE-BASELINE-P1
  └─ pinned: Rust 2× OOF-TY1 / Ruby 2× OOF-P1 / source hash frozen
```

---

## Proof

**Runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_rule_engine_baseline_p1.rb`  
**Result:** 52/52 PASS

| Section | Topic | Checks |
|---------|-------|--------|
| A | Preconditions — compiler + source files | 5 |
| B | Rust TC status and diagnostic count frozen | 6 |
| C | Rust OOF-TY1 messages frozen | 5 |
| D | Ruby TC diagnostic count and messages frozen | 6 |
| E | Dynamic callee site classified and quarantined | 5 |
| F | Unknown field access site classified and policy confirmed | 5 |
| G | Source integrity — no app source changes | 5 |
| H | Safety policy assertions | 5 |
| I | Liveness counters within bounds | 5 |
| J | Closed surfaces — no implementation, no regression | 5 |

---

## Non-Goals

- No dynamic dispatch implementation
- No validation receipt semantics
- No HOF lambda error propagation changes
- No type narrowing or cast operator
- No plugin or reflection feature
- No app source changes
- No new OOF codes

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Implementation planning for parametric container assignability |
| LAB-DYNAMIC-CONTRACT-DISPATCH-P2 | Validation receipt and fail-closed semantics for dynamic callees |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 | Rust HOF temp_errors vs Ruby propagation divergence |
