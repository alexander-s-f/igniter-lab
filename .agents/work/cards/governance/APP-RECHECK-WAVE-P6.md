# APP-RECHECK-WAVE-P6

**Lane:** governance / app-pressure recheck  
**Status:** CLOSED  
**Date:** 2026-06-13  
**Trigger:** LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 CLOSED (76/76 PASS)  
**Scope:** 12 apps (10 existing + igniter_parser + bloom_filter); evidence + registry updates only

---

## Prerequisite Status

| Prerequisite | Status |
|---|---|
| LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 | CLOSED / 76/76 PASS |
| P2 proof updated (H-01/J-01..J-04) | 52/52 still PASS |
| P3 implementation: `infer_record_literal` +14 lines | CONFIRMED in typechecker.rb |

---

## Compiler Results

| App | Rust | Rust diags | Ruby | Ruby diags | Δ Ruby vs P5 |
|---|---|---|---|---|---|
| advanced_logistics | ok | 0 | ok | 0 | unchanged |
| dsa | ok | 0 | ok | 0 | −4 → DUAL-CLEAN |
| dataframes | ok | 0 | ok | 0 | −2 → DUAL-CLEAN |
| neural_net | ok | 0 | ok | 0 | −2 → DUAL-CLEAN |
| vector_math | ok | 0 | oof | 36 | −5 |
| vector_editor | oof | 1 | oof | 3 | −1 |
| decision_tree | oof | 4 | oof | 7 | unchanged |
| arch_patterns | oof | 8 | oof | 14 | unchanged (composition changed) |
| rule_engine | oof | 2 | oof | 2 | −1 |
| sim_framework | ok | 0 | oof | 3 | −1 |
| igniter_parser | oof | 1 | oof | 1 | new |
| bloom_filter | oof | 15 | oof | 16 | new |

---

## Key Findings

**P3 impact:** All 12 Wave P5 ACTIVE_TRUE_INTERMEDIATE symbols resolved. 3 apps go dual-toolchain CLEAN (dsa, dataframes, neural_net). Total dual-CLEAN fleet: 4 apps. No ambiguity-OOF-TY0 fired in any real app. No regressions.

**New cascades exposed by P3 resolutions:**
- **VE-P09** (vector_editor): `new_obj` in tools.ig:21 — unannotated record literal newly visible after `default_style` resolved; route: LANG-RUBY-RECORD-LITERAL-INFERENCE-P4
- **AP-P13** (arch_patterns): `empty_trail` in example.ig:65 — BOOTSTRAP stringly `call_contract("append", text, text)` newly visible after `genesis` resolved; route: LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1
- **SIM-P14** (sim_framework): `initial_state` in example.ig:66 — `{ ..., events: [], proofs: [], violations: [] }` fails structural match because `Collection[Unknown]` (from empty arrays `[]`) is rejected by `structurally_assignable?` at param depth (line 1536: `actual==Unknown → false`); zero candidates → Unknown; route: LANG-RUBY-RECORD-LITERAL-INFERENCE-P4

**igniter_parser inclusion:** Both toolchains stop at `OOF-IMP2 unknown stdlib module path 'stdlib.string'` — confirmed first blocker. LANG-STDLIB-STRING-SURFACE-P1 is the dominant route. Stringly `call_contract("empty")` and `call_contract("append", ...)` are hidden behind P01.

**bloom_filter inclusion:** Both toolchains blocked by 15 stringly `call_contract("append", ...)` sites in `InitFilter16`. Ruby adds cascade `Unresolved symbol: b14`. BOOTSTRAP shape (two bare BitSlot values) confirmed. LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 dominant route.

**Dominant cross-app blocker:** Stringly `call_contract("append", ...)` now blocks decision_tree, arch_patterns, vector_editor, bloom_filter — 4 apps, 6+ contracts, 37+ call sites across the fleet.

---

## Record Literal Classification (P6)

| Classification | Count | Pressure IDs |
|---|---|---|
| RESOLVED_BY_P3 | 12 Wave P5 symbols (19 individual) | DSA-P10/DF-P10/NN-P09/VM-P09/VE-P08-partial/RE-P07-partial/SIM-P12/SIM-P13/AP-P12-partial |
| ACTIVE_FIELD_NAME_MISMATCH | 1 | VM-P10 (x/y/z vs r0/r1/r2; app source alignment needed) |
| ACTIVE_TRUE_INTERMEDIATE (new, P3 zero-match) | 1 | SIM-P14 (Collection[Unknown] param-depth rejection) |
| NOT_RECORD_LITERAL (stringly cascade) | 5 | DT-P09/AP-P13/VE-P09-partial/BF-P01 |
| NOT_RECORD_LITERAL (String/Text alias) | 2 | SIM-P10/P11 |
| NOT_RECORD_LITERAL (dynamic dispatch) | 2 | RE-P02/RE-P03 |

---

## Next Routes

| Rank | Route | Apps affected |
|---|---|---|
| 1 | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 | decision_tree, arch_patterns, vector_editor, bloom_filter (+ igniter_parser hidden) |
| 2 | LANG-STDLIB-STRING-SURFACE-P1 | igniter_parser |
| 3 | LANG-STRING-TEXT-ALIAS-P1 | sim_framework |
| 4 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 | sim_framework (SIM-P14), vector_editor (VE-P09) |
| 5 | LAB-DYNAMIC-CONTRACT-DISPATCH-P1 | rule_engine |

---

## Deliverables

- [x] 12 PRESSURE_REGISTRY.md files updated with Wave P6 Recheck Summary
- [x] New pressure IDs: VE-P09, AP-P13, SIM-P14
- [x] igniter_parser Wave P6 Recheck Summary added
- [x] bloom_filter Wave P6 Recheck Summary added
- [x] Rollup doc: `igniter-lab/.agents/docs/app-pressure-recheck-wave-p6-2026-06-13-v0.md`
- [x] Governance card: this file
- [x] Portfolio index: prepended
- [x] No app source changes
- [x] No compiler source changes
