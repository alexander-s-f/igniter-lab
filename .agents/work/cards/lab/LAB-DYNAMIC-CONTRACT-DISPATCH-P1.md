# LAB-DYNAMIC-CONTRACT-DISPATCH-P1 — Dynamic Dispatch Safety Boundary

**Track:** lab / safety / dynamic dispatch
**Route:** EVIDENCE + SAFETY BOUNDARY CLASSIFICATION
**Status:** CLOSED — PROVED 30/30 — SAFETY POLICY ESTABLISHED
**Date:** 2026-06-13
**Predecessors:** LAB-RUBY-CALL-CONTRACT-PARITY-P3, LANG-OUTPUT-TYPE-ASSIGNABILITY-P4, APP-RECHECK-WAVE-P7

---

## Goal

Classify which `call_contract` forms are acceptable, blocked, or require quarantine
before any dynamic dispatch implementation is attempted. Determine the correct safety
policy given that the output assignability boundary now rejects `Unknown`-to-concrete
assignments.

---

## Trigger

- `rule_engine` uses a dynamic/variable callee in `call_contract(r, t)` (Tier 2)
- `vector_editor` uses only literal callees
- LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 removed LAB-RACK-P9; Rust TC now emits OOF-TY1
  for `Collection[Unknown] → Collection[RuleDecision]`
- Active pressures: RE-P02, RE-P03, RE-P04, RE-P07 (partial)

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc  | `igniter-lab/lab-docs/lang/lab-dynamic-contract-dispatch-p1-safety-boundary-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-apps/rule_engine/verify_dynamic_dispatch_p1.rb` | 30/30 PASS |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Findings (5 Questions Answered)

**Q1. Which apps use dynamic callee variables?**
One site: `rule_engine/engine.ig:17-18` — `call_contract(r, t)` where `r : String`
from `Collection[String]`. All 155 other `call_contract` calls in the fleet use
string literal callees.

**Q2. Which use literal user-contract `call_contract`?**
155 calls in 32 files. Confirmed CLEAN in both TCs after LAB-RUBY-CALL-CONTRACT-PARITY-P3.
Key apps: vector_editor, arch_patterns, neural_net, sim_framework, dataframes.

**Q3. Which return Unknown?**
Only `rule_engine/ExecuteRules`: `call_contract(r, t)` → Unknown → `map` wraps as
`Collection[Unknown]` → `filter` preserves → output boundary annotated
`Collection[RuleDecision]`.

**Q4. Which output boundaries now catch them?**
`engine.ig:30` — Rust TC: 2× OOF-TY1 (`Collection[Unknown]` outer + `Unknown` element).
Ruby TC: `Unresolved symbol: d` + `Unresolved field: Unknown.action` (Tier 2 binding gap).
Both toolchains reject the Unknown-to-concrete path. Safety-positive.

**Q5. What safety policy is acceptable before any implementation?**

| Form | Status | Gate |
|------|--------|------|
| Literal callee, same module | ACCEPTED | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| Dynamic callee + Unknown output | QUARANTINED | Must declare `output : Unknown` |
| Dynamic callee + typed output | BLOCKED | OOF-TY1 (D2) |
| Field access on Unknown result | DEFERRED | LAB-UNKNOWN-FIELD-ACCESS-P1 |

---

## Verdict: PROVED 30/30 — SAFETY POLICY ESTABLISHED

```
Result: 30/30 PASS
VERDICT: PASS — LAB-DYNAMIC-CONTRACT-DISPATCH-P1 PROVED

  Dynamic callee sites:            1  (rule_engine/engine.ig)
  Literal callee sites:          155  (32 files; DUAL-CLEAN)
  Contracts returning Unknown:     1  (ExecuteRules)
  Output boundaries blocking:      1  (engine.ig:30 — 2× OOF-TY1 Rust)

  ACCEPTED:    Tier 1 literal callees
  QUARANTINED: Tier 2 + explicit Unknown output
  BLOCKED:     Tier 2 + typed output (OOF-TY1 D2)
  DEFERRED:    Field access on Unknown (LAB-UNKNOWN-FIELD-ACCESS-P1)
```

---

## Proof Matrix (30 checks / 6 sections)

| Section | Checks | Result |
|---------|--------|--------|
| A — Preconditions: compiler + source census | 5 | 5/5 PASS |
| B — Rust TC: output boundary fires OOF-TY1 | 5 | 5/5 PASS |
| C — Ruby TC: Tier 2 dynamic callee inline | 6 | 6/6 PASS |
| D — Ruby TC: Tier 1 literal callee control | 5 | 5/5 PASS |
| E — Safety policy classification assertions | 5 | 5/5 PASS |
| F — Closed surfaces: no regression, no implementation | 4 | 4/4 PASS |

---

## OOF Codes

| Code | Role in this card |
|------|-----------------|
| OOF-TY1 | Confirms output boundary fires for Unknown-to-concrete (B-02..B-05) |
| OOF-TY0 | Confirms fail-closed on bad literal callees (D-03, D-04) |

No new OOF codes introduced.

---

## Authority Closed

- No compiler source changes
- No dynamic dispatch implementation
- No validation receipt semantics
- No plugin model
- No reflection feature
- No new OOF codes

---

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline post P-series |
| LAB-UNKNOWN-FIELD-ACCESS-P1 | Field projection policy over Unknown; toolchain divergence |
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Implementation planning for parametric container assignability |
