# APP-RECHECK-WAVE-P2

**Lane:** governance / app pressure  
**Mode:** COMPILE/REPORT  
**Status:** CLOSED — RECHECK COMPLETE  
**Date:** 2026-06-12  
**Predecessor:** APP-RECHECK-WAVE-P1  
**Rollup doc:** `igniter-lab/.agents/docs/app-pressure-recheck-wave-p2-2026-06-12-v0.md`

---

## Goal

App-pressure recheck after Wave P1 infra fixes. Gate: all 8 prerequisite cards CLOSED. Scope: compile/report only for dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net. No app source edits, no proposals, no implementations.

---

## Gate Result: CLEAR

All 8 prerequisite cards confirmed CLOSED before recheck:

| Card | Proof |
|------|-------|
| LANG-EMITTER-ENCODING-P2 | 18/18 PASS |
| LANG-STDLIB-NUMERIC-COMPARISON-P3 | 46/46 PASS |
| LANG-UNARY-OPERATORS-P4 | 47/47 PASS |
| LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 | 70/70 PASS |
| LANG-STDLIB-COLLECTION-CONCAT-PROP-P4 | 32/32 PASS |
| LANG-STDLIB-IS-EMPTY-PROP-P4 | 50/50 PASS |
| LANG-STDLIB-COLLECTION-APPEND-PROP-P4 | 66/66 PASS |
| LANG-STDLIB-TEXT-EQUALITY-P3 | 52/52 PASS |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Rollup doc | `igniter-lab/.agents/docs/app-pressure-recheck-wave-p2-2026-06-12-v0.md` | Written |
| DSA PRESSURE_REGISTRY | `igniter-lab/igniter-apps/dsa/PRESSURE_REGISTRY.md` | Updated |
| vector_editor PRESSURE_REGISTRY | `igniter-lab/igniter-apps/vector_editor/PRESSURE_REGISTRY.md` | Updated |
| decision_tree PRESSURE_REGISTRY | `igniter-lab/igniter-apps/decision_tree/PRESSURE_REGISTRY.md` | Updated |
| arch_patterns PRESSURE_REGISTRY | `igniter-lab/igniter-apps/arch_patterns/PRESSURE_REGISTRY.md` | Updated |
| dataframes PRESSURE_REGISTRY | `igniter-lab/igniter-apps/dataframes/PRESSURE_REGISTRY.md` | Updated |
| rule_engine PRESSURE_REGISTRY | `igniter-lab/igniter-apps/rule_engine/PRESSURE_REGISTRY.md` | Updated |
| neural_net PRESSURE_REGISTRY | `igniter-lab/igniter-apps/neural_net/PRESSURE_REGISTRY.md` | Updated |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Resolutions

| Pressure ID | App | Was | Now | Prerequisite |
|-------------|-----|-----|-----|--------------|
| DSA-P09 | dsa | ACTIVE (UTF-8 crash) | RESOLVED | LANG-EMITTER-ENCODING-P2 |
| AP-P09 | arch_patterns | ACTIVE (`<` operator gap) | RESOLVED | LANG-STDLIB-NUMERIC-COMPARISON-P3 |
| AP-P10 | arch_patterns | ACTIVE (UTF-8 crash) | RESOLVED | LANG-EMITTER-ENCODING-P2 |
| DF-P09 | dataframes | ACTIVE (UTF-8 crash) | RESOLVED | LANG-EMITTER-ENCODING-P2 |
| NN-P02 | neural_net | ACTIVE (unary minus) | RESOLVED | LANG-UNARY-OPERATORS-P3/P4 |
| NN-P07 | neural_net | ACTIVE (`<` operator gap) | RESOLVED | LANG-STDLIB-NUMERIC-COMPARISON-P3 |
| RE-P04 | rule_engine | HOLD/SAFETY-HIGH | ACTIVE/CONFIRMED | LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 |

**Total new RESOLVED:** 6  
**Improved diagnostics:** 1 (RE-P04 — error message now carries full type info)

---

## Compile Results

| App | Rust | Ruby | First blocker |
|-----|------|------|---------------|
| dsa | ok / 0 diags | oof / 15 diags | call_contract (DSA-P08) |
| vector_editor | oof / 1 diag | oof / 7 diags | call_contract (VE-P02/P03) |
| decision_tree | oof / 4 diags | error / 1 diag | append Rust / keyword(label) Ruby |
| arch_patterns | oof / 7 diags | oof / 39 diags | call_contract (AP-P02) |
| dataframes | ok / 0 diags | oof / 8 diags | call_contract (DF-P08) |
| rule_engine | ok / 0 diags | oof / 9 diags | call_contract (RE-P02/P03/P04) |
| neural_net | ok / 0 diags | oof / 12 diags | call_contract (NN-P08) |

Rust CLEAN: dsa, dataframes, rule_engine, neural_net (unchanged from Wave P1).

---

## Dominant Remaining Pressure

**call_contract parity** is the cross-app dominant blocker:
- Ruby: all 7 apps affected
- Rust: vector_editor (1), decision_tree (4), arch_patterns (7) — `call_contract("append",...)` stringly-typed form not dispatched

Next route: LANG-RUBY-CALL-CONTRACT-PARITY-P2 + LANG-PARSER-CONTEXTUAL-KEYWORDS-P1.
