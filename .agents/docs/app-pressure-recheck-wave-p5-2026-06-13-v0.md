# App Pressure Recheck — Wave P5

**Date:** 2026-06-13  
**Trigger:** LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 CLOSED  
**Scope:** All 10 apps; evidence + registry updates only; no compiler or app source changes  
**Toolchains checked:** Ruby (igniter-lang) + Rust (igniter-compiler)

---

## Headline Finding

LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 had **zero app pressure impact**. All prior Wave P4 diagnostic counts are unchanged. No app in the corpus uses annotated compute record literals (`compute name : Type = { ... }`). All intermediate record literal computes are unannotated (`compute name = { ... }`), so the P2 mechanism (temporary `@output_type_hints` install for annotated computes) never fires against real app source.

P2 is correct and working as designed — it closes the annotated case. The dominant remaining gap across the corpus is structural field-matching for unannotated intermediates (`LANG-RUBY-RECORD-LITERAL-INFERENCE-P3`).

---

## Compiler Status Table

| App | Ruby status | Ruby diags | Rust status | Rust diags | Δ from P4 |
|---|---|---|---|---|---|
| advanced_logistics | ok | 0 | ok | 0 | unchanged |
| vector_math | oof | 41 | ok | 0 | unchanged |
| dsa | oof | 4 | ok | 0 | unchanged |
| vector_editor | oof | 4 | oof | 1 | unchanged |
| decision_tree | oof | 7 | oof | 4 | unchanged |
| arch_patterns | oof | 14 | oof | 8 | unchanged |
| dataframes | oof | 2 | ok | 0 | unchanged |
| rule_engine | oof | 3 | oof | 2 | unchanged |
| neural_net | oof | 2 | ok | 0 | unchanged |
| sim_framework | oof | 4 | ok | 0 | unchanged |

---

## Record Literal Classification Table

| Pressure ID | Symbol(s) | Classification | Route |
|---|---|---|---|
| DSA-P10 | e0, s, edge1, c_h | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| DF-P10 | c00, p1 | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| NN-P09 | w1, x1 | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| VM-P09 | gravity, point, b, a_min, min_pt | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| SIM-P12 | pop_constraint | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| SIM-P13 | wolves | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| AP-P12 (partial) | genesis | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| RE-P07 (partial) | tx1 | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| VE-P08 (partial) | default_style, new_pos | ACTIVE_TRUE_INTERMEDIATE | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| VM-P10 | result (r0/r1/r2 vs x/y/z) | ACTIVE_FIELD_NAME_MISMATCH | Field name alignment in type decl vs literal call site |
| DT-P09 | new_nodes, nodes_0, features_good | NOT_RECORD_LITERAL (stringly call_contract cascade) | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 |
| VE-P08 (partial) | new_objects | NOT_RECORD_LITERAL (stringly call_contract cascade) | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 |
| AP-P12 (partial) | new_trail ×3 | NOT_RECORD_LITERAL (stringly call_contract cascade) | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 |
| RE-P07 (partial) | d, Unknown.action | NOT_RECORD_LITERAL (dynamic dispatch) | LAB-DYNAMIC-CONTRACT-DISPATCH-P1 |
| SIM-P10 | corrective_event (rule_name field) | NOT_RECORD_LITERAL (String/Text alias) | LANG-STRING-TEXT-ALIAS-P1 |
| SIM-P11 | corrective_event (output boundary) | NOT_RECORD_LITERAL (String/Text alias cascade) | LANG-STRING-TEXT-ALIAS-P1 |
| — | — | RESOLVED_BY_COMPUTE_ANNOTATION | 0 pressures (P2 finds no targets in corpus) |
| — | — | RESOLVED_BY_OUTPUT_HINT | 0 pressures (no same-name output/compute intermediate gaps) |

**ACTIVE_TRUE_INTERMEDIATE count:** 12 symbols across 9 apps  
**NOT_RECORD_LITERAL count:** 8 pressures across 5 apps (3 categories)  
**ACTIVE_FIELD_NAME_MISMATCH count:** 1 pressure (VM-P10, already surfaces via existing output hint mechanism)

---

## Resolved Pressure Table

No pressures were resolved in Wave P5. All Wave P4 pressures remain active with unchanged diagnostic counts.

| Pressure ID | App | Status | Notes |
|---|---|---|---|
| — | all | unchanged | LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 finds zero annotated compute record literal targets in corpus |

---

## Next Route Ranking

| Rank | Route | Pressure coverage | Apps affected | Notes |
|---|---|---|---|---|
| 1 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 | ACTIVE_TRUE_INTERMEDIATE: 12 symbols, 9 apps | dsa, dataframes, neural_net, vector_math, sim_framework, arch_patterns, rule_engine, vector_editor, + | Dominant gap; structural field-matching for unannotated intermediate computes; Ruby TC only |
| 2 | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 | NOT_RECORD_LITERAL (stringly): 8 cascade pressures, 3 apps | decision_tree, vector_editor, arch_patterns | Migrates `call_contract("append", ...)` form to stdlib dispatch; clears DT-P09, VE-P08-partial, AP-P12-partial, DT-P03, AP-P02, VE-P03 |
| 3 | LANG-STRING-TEXT-ALIAS-P1 | NOT_RECORD_LITERAL (String/Text): SIM-P10/P11 | sim_framework | `concat(...)` returns "Text"; type declares "String"; alias unification needed |
| 4 | LAB-DYNAMIC-CONTRACT-DISPATCH-P1 | NOT_RECORD_LITERAL (dynamic dispatch): RE-P07-partial | rule_engine | Variable callee dispatch; safety design required; RE-P02/RE-P03/RE-P04 clear when addressed |

---

## Focus Question Answers

**Q: Which pressures did LANG-RUBY-RECORD-LITERAL-INFERENCE-P2 resolve?**  
None. The P2 mechanism activates for `compute name : Type = { ... }` annotated forms only. No app in the corpus uses this pattern.

**Q: Which active pressures are record literal gaps vs other roots?**  
12 symbols across 9 apps are ACTIVE_TRUE_INTERMEDIATE (unannotated record literal, no output_type_hint). 8 pressures are NOT_RECORD_LITERAL (stringly call_contract cascade, dynamic dispatch, or String/Text alias). 1 pressure is ACTIVE_FIELD_NAME_MISMATCH (VM-P10, field naming inconsistency in app source).

**Q: What is the correct next route?**  
`LANG-RUBY-RECORD-LITERAL-INFERENCE-P3` — structural field-matching for unannotated intermediate computes. This is the single highest-yield compiler change available, covering the dominant remaining gap across 9 apps.

**Q: Did any new pressures surface?**  
No. All pressures were already documented in Wave P4. Wave P5 confirms classification and adds ACTIVE_TRUE_INTERMEDIATE / NOT_RECORD_LITERAL labelling.
