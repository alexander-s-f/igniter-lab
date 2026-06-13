# APP-RECHECK-WAVE-P5

**Status:** CLOSED  
**Date:** 2026-06-13  
**Lane:** governance / app-pressure recheck  
**Trigger:** LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 CLOSED

---

## Summary

Fresh app-pressure recheck across all 10 apps after LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 closed. Finding: zero app pressure impact. All Wave P4 diagnostic counts unchanged. No app in the corpus uses annotated compute record literals; the P2 mechanism never fires against real source. All intermediate record literal computes are unannotated (`compute name = { ... }`), making `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` (structural field-matching for unannotated intermediates) the dominant next route.

---

## Compiler Results

| App | Ruby | Rust | Δ from P4 |
|---|---|---|---|
| advanced_logistics | ok / 0 | ok / 0 | unchanged — CLEAN |
| vector_math | oof / 41 | ok / 0 | unchanged |
| dsa | oof / 4 | ok / 0 | unchanged |
| vector_editor | oof / 4 | oof / 1 | unchanged |
| decision_tree | oof / 7 | oof / 4 | unchanged |
| arch_patterns | oof / 14 | oof / 8 | unchanged |
| dataframes | oof / 2 | ok / 0 | unchanged |
| rule_engine | oof / 3 | oof / 2 | unchanged |
| neural_net | oof / 2 | ok / 0 | unchanged |
| sim_framework | oof / 4 | ok / 0 | unchanged |

---

## Key Finding

LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 implements temporary `@output_type_hints` installation for annotated compute record literals (`compute name : Type = { ... }`). Zero apps in the corpus use this pattern — all intermediate computes with record literal RHS are unannotated. The P2 change is architecturally correct but exercises no real app source.

This is the same finding pattern as LANG-TYPED-COMPUTE-BINDING-P2 (Wave P4): successive narrowing of the annotated path confirmed the true dominant gap is the unannotated path.

---

## Record Literal Classification (P5)

- **ACTIVE_TRUE_INTERMEDIATE:** 12 symbols across 9 apps (DSA-P10, DF-P10, NN-P09, VM-P09, SIM-P12, SIM-P13, AP-P12-partial, RE-P07-partial, VE-P08-partial) → route: LANG-RUBY-RECORD-LITERAL-INFERENCE-P3
- **NOT_RECORD_LITERAL (stringly call_contract):** DT-P09, VE-P08-partial, AP-P12-partial → route: LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1
- **NOT_RECORD_LITERAL (dynamic dispatch):** RE-P07-partial → route: LAB-DYNAMIC-CONTRACT-DISPATCH-P1
- **NOT_RECORD_LITERAL (String/Text alias):** SIM-P10/P11 → route: LANG-STRING-TEXT-ALIAS-P1
- **ACTIVE_FIELD_NAME_MISMATCH:** VM-P10 (x/y/z vs r0/r1/r2) — pre-existing, already detected via output hint
- **RESOLVED_BY_COMPUTE_ANNOTATION:** 0 pressures
- **RESOLVED_BY_OUTPUT_HINT:** 0 pressures

---

## Deliverables

- [x] All 10 `PRESSURE_REGISTRY.md` files: Wave P5 Recheck Summary added; headers updated to APP-RECHECK-WAVE-P5
- [x] Rollup doc: `igniter-lab/.agents/docs/app-pressure-recheck-wave-p5-2026-06-13-v0.md`
- [x] Governance card: this file
- [x] Portfolio index: prepended

---

## Next Routes (ranked)

1. `LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` — structural field-matching for unannotated intermediate computes (12 symbols, 9 apps)
2. `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` — stringly call_contract("append") cascade (DT, VE, AP)
3. `LANG-STRING-TEXT-ALIAS-P1` — String/Text alias unification (sim_framework)
