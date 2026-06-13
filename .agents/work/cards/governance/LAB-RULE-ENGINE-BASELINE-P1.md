# LAB-RULE-ENGINE-BASELINE-P1

**Status:** CLOSED — PROVED 52/52 PASS — BASELINE FROZEN  
**Route:** APP BASELINE / SAFETY REGRESSION  
**Date:** 2026-06-13  
**Predecessors:** LAB-DYNAMIC-CONTRACT-DISPATCH-P1 · LAB-UNKNOWN-FIELD-ACCESS-P1 · LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 · APP-RECHECK-WAVE-P7

## Goal

Freeze the current `rule_engine` app baseline after dynamic dispatch, output assignability, and Unknown field access safety work.

The goal is not to unblock rule_engine. The goal is to pin the current blocked state so future IO/runtime and dynamic-dispatch work does not accidentally weaken the safety boundary.

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_rule_engine_baseline_p1.rb` | 52/52 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-rule-engine-baseline-p1-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-RULE-ENGINE-BASELINE-P1.md` | CLOSED |
| PRESSURE_REGISTRY update | `igniter-lab/igniter-apps/rule_engine/PRESSURE_REGISTRY.md` | Updated |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

## Frozen Baseline (Wave P7 / 2026-06-13)

```
Rust TC:  oof / 2× OOF-TY1
  "Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]"  (node: active_decisions)
  "Output type mismatch: expected RuleDecision, got Unknown"  (node: decision)

Ruby TC:  oof / 2× OOF-P1
  "Unresolved symbol: d"
  "Unresolved field: Unknown.action"

Source hash:  sha256:0cf7f61465246aedb46242c9c6c36add39f9d71956950461a7831e9bdc22486b
Liveness:     tc_infer=6 / fr_walk=6 / no breaches
Unblock route: NONE in current stage
```

## Proof Matrix (52 checks / 10 sections)

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

## Acceptance Confirmed

- Rust and Ruby diagnostics frozen with exact OOF counts and messages: ✓
- Dynamic callee remains blocked (typed output) — Tier 2 quarantine policy: ✓
- Unknown field access blocked in Ruby / silenced+OOF-TY1 in Rust HOF lambda: ✓
- No app source changes: ✓
- Source hash stable across two independent compile runs: ✓

## Authority Closed

- No compiler or TC source changes
- No app source changes
- No dynamic dispatch implementation
- No validation receipt semantics
- No new OOF codes
- No HOF lambda error propagation changes

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2 | Implementation planning for parametric container assignability |
| LAB-DYNAMIC-CONTRACT-DISPATCH-P2 | Validation receipt and fail-closed semantics for dynamic callees |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 | Rust HOF temp_errors vs Ruby propagation divergence |
