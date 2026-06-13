# App Pressure Recheck — Wave P6

**Date:** 2026-06-13  
**Trigger:** LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 CLOSED (76/76 PASS)  
**Scope:** All 12 apps (10 existing + igniter_parser + bloom_filter newly added); evidence + registry updates only; no compiler or app source changes  
**Toolchains checked:** Ruby (igniter-lang) + Rust (igniter-compiler)

---

## Headline Finding

LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 resolved **all 12 ACTIVE_TRUE_INTERMEDIATE symbols** tracked from Wave P5, plus exposed 3 new cascades made visible by those resolutions. **3 apps go dual-toolchain CLEAN** this wave (dsa, dataframes, neural_net), bringing the total CLEAN fleet to 4 apps. No app regressed. The fail-closed ambiguity path (OOF-TY0) did not fire in any real app — no ambiguous type shapes exist in the fleet. Stringly `call_contract("append", ...)` is now the dominant cross-app blocker across all remaining non-CLEAN apps.

Two previously omitted apps are now fully included in the fleet:
- **igniter_parser** — first blocker `OOF-IMP2 stdlib.string`; exposes self-hosting stdlib frontier
- **bloom_filter** — first blocker stringly call_contract("append"); adds strong regression pressure for stdlib.collection.append migration

---

## Table 1: Compiler Status

| App | Rust status | Rust diags | Ruby status | Ruby diags | First active diagnostic | Δ vs Wave P5 |
|---|---|---|---|---|---|---|
| advanced_logistics | ok | 0 | ok | 0 | — | unchanged (dual-CLEAN) |
| dsa | ok | 0 | ok | 0 | — | **−4 Ruby → DUAL-TOOLCHAIN CLEAN** |
| dataframes | ok | 0 | ok | 0 | — | **−2 Ruby → DUAL-TOOLCHAIN CLEAN** |
| neural_net | ok | 0 | ok | 0 | — | **−2 Ruby → DUAL-TOOLCHAIN CLEAN** |
| vector_math | ok | 0 | oof | 36 | OOF-TY0 record literal field mismatch r0/r1/r2 vs x/y/z | −5 Ruby (VM-P09 resolved) |
| vector_editor | oof | 1 | oof | 3 | OOF-TY0 call_contract unknown callee 'append' | −1 Ruby (VE-P08 partial resolved) |
| decision_tree | oof | 4 | oof | 7 | OOF-TY0 call_contract unknown callee 'append' | unchanged |
| arch_patterns | oof | 8 | oof | 14 | OOF-TY0 call_contract unknown callee 'append' | unchanged count (AP-P12 genesis resolved; AP-P13 empty_trail new) |
| rule_engine | oof | 2 | oof | 2 | OOF-TY1 Output type mismatch (Rust) / OOF-P1 Unresolved d (Ruby) | −1 Ruby (RE-P07 tx1 resolved) |
| sim_framework | ok | 0 | oof | 3 | OOF-TY0 String/Text mismatch (rule_name) | −1 Ruby (SIM-P12/P13 resolved; SIM-P14 new) |
| igniter_parser | oof | 1 | oof | 1 | OOF-IMP2 unknown stdlib module path 'stdlib.string' | new fleet member |
| bloom_filter | oof | 15 | oof | 16 | OOF-TY0 call_contract unknown callee 'append' | new fleet member |

**Dual-toolchain CLEAN apps (Wave P6):** advanced_logistics, dsa, dataframes, neural_net (4 total; +3 this wave)

---

## Table 2: Record Literal Impact

| Prior pressure ID | Symbol(s) | P5 classification | P6 result | Resolved by P3? |
|---|---|---|---|---|
| DSA-P10 | e0, s, edge1, c_h | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — e0 → IndexedElement, s → IntSet (param-depth disambiguation), edge1 → Edge, c_h → Cell | Yes |
| DF-P10 | c00, p1 | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — c00 → Cell, p1 → DataPoint | Yes |
| NN-P09 | w1, x1 | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — w1 → weight type, x1 → InputVector | Yes |
| VM-P09 | gravity, point, b, a_min, min_pt | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — all 5 infer correct types | Yes |
| VE-P08 (partial) | default_style, new_pos | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — default_style → Style, new_pos → Point | Yes |
| RE-P07 (partial) | tx1 | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — tx1 → Transaction | Yes |
| SIM-P12 | pop_constraint | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — pop_constraint → ConstraintViolation | Yes |
| SIM-P13 | wolves | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — wolves → inferred population type | Yes |
| AP-P12 (partial) | genesis | ACTIVE_TRUE_INTERMEDIATE | RESOLVED — genesis infers correct account/event-sourcing type | Yes |
| VM-P10 | result (field mismatch) | ACTIVE_FIELD_NAME_MISMATCH | STILL ACTIVE — 36 diags; x/y/z vs r0/r1/r2 is a name mismatch, not a structural inference gap; unaffected by P3 | No |
| DT-P09 | new_nodes, nodes_0, features_good | NOT_RECORD_LITERAL (stringly cascade) | STILL ACTIVE — stringly append cascade; unaffected by P3 | No |
| AP-P11 | OOF-TY1 cascade | NOT_RECORD_LITERAL (OOF-TY1 cascade) | STILL ACTIVE — clears when stringly append resolves | No |
| SIM-P10/P11 | corrective_event (rule_name) | NOT_RECORD_LITERAL (String/Text alias) | STILL ACTIVE — unaffected by P3 | No |

**New cascades exposed by P3 resolutions:**

| New pressure ID | Symbol | Root cause | Route |
|---|---|---|---|
| VE-P09 | new_obj (tools.ig:21) | Unannotated record literal, newly exposed after default_style resolved; fields include `style: default_style`; P3 should match it to GraphicObject — needs re-check | LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 or re-run |
| AP-P13 | empty_trail (example.ig:65) | `call_contract("append", "pipeline:start", "pipeline:init")` — BOOTSTRAP stringly form; exposed after genesis resolved | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 |
| SIM-P14 | initial_state (example.ig:66) | `compute initial_state = { ..., events: [], proofs: [], violations: [] }` — empty arrays produce `Collection[Unknown]`; `structurally_assignable?` returns false when actual param = Unknown (line 1536); SimState field-name set matches but excluded due to param-depth Unknown rejection | LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 (param-depth Collection[Unknown] permissive) |

---

## Table 3: Newly Included Apps

| App | Rust status | Ruby status | Rust diags | Ruby diags | First blocker | Dominant route | Include-in-fleet verdict |
|---|---|---|---|---|---|---|---|
| igniter_parser | oof | oof | 1 | 1 | OOF-IMP2 `unknown stdlib module path 'stdlib.string'` | LANG-STDLIB-STRING-SURFACE-P1 | INCLUDED — exposes self-hosting stdlib frontier; `char_at`, string hashing, state-machine iteration are downstream once string surface unlocks; stringly call_contract("empty"/"append") also present (IP-P06) but hidden behind P01 |
| bloom_filter | oof | oof | 15 | 16 | OOF-TY0 `call_contract: unknown callee 'append'` (15 sites in InitFilter16) | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 | INCLUDED — strong fixture for stdlib.collection.append migration (15 chained append calls in InitFilter16); map/filter already usable (BF-P08); exposes collection generation gap (range, BF-P03) and indexed access gap (BF-P04); Ruby cascade `b14` Unresolved symbol behind append chain |

---

## Table 4: Next Route Ranking

| Rank | Route | Apps affected | Pressures covered | Why now |
|---|---|---|---|---|
| 1 | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 | decision_tree (4 Rust+7 Ruby), arch_patterns (8+14), vector_editor (1+3), bloom_filter (15+16), igniter_parser (hidden behind P01) | DT-P03/P09, AP-P02/P11/P13, VE-P02/P03/P09-partial, BF-P01, AP-P13 | Dominant cross-app blocker after P3 resolved all record literal gaps; 5 apps blocked; bloom_filter adds 15 clean regression sites; every remaining stringly append call now has a canonical `append(c, e)` destination |
| 2 | LANG-STDLIB-STRING-SURFACE-P1 | igniter_parser (both toolchains) | IP-P01, IP-P02, IP-P05 | igniter_parser's first blocker is OOF-IMP2 stdlib.string; unblocking it reveals the next self-hosting frontier; stdlib.string is also a prerequisite for bloom_filter's IP-P07 string hashing |
| 3 | LANG-STRING-TEXT-ALIAS-P1 | sim_framework | SIM-P10, SIM-P11 | String/Text alias still isolated to sim_framework; small surface area; clears 2 sim_framework diags and exposes SIM-P14 as the next remaining Ruby gap |
| 4 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P4 | sim_framework, vector_editor (new_obj) | SIM-P14, VE-P09 | P3's `structurally_assignable?` correctly rejects `Collection[Unknown]` at param depth; P4 would extend permissive to Collection[Unknown] → Collection[T] structural matching; small change; sim_framework initial_state and vector_editor new_obj both need this |
| 5 | LAB-DYNAMIC-CONTRACT-DISPATCH-P1 | rule_engine | RE-P02, RE-P03, RE-P04 | Dynamic variable callee still isolated to rule_engine; safety design required; unblocks RE-P04 OOF-TY1 safety resolution |

---

## Focus Question Answers

**Q: Did structural record literal inference clear the 12 ACTIVE_TRUE_INTERMEDIATE pressures?**  
Yes. All 12 symbols from Wave P5's ACTIVE_TRUE_INTERMEDIATE classification resolved in Wave P6 (DSA-P10 ×4, DF-P10 ×2, NN-P09 ×2, VM-P09 ×5, SIM-P12 ×1, SIM-P13 ×1, AP-P12-partial ×1, RE-P07-partial ×1, VE-P08-partial ×2 = 19 individual symbols). 3 new cascades appeared (VE-P09, AP-P13, SIM-P14) due to previously-hidden downstream symbols becoming visible.

**Q: Did any app regress because ambiguity is now fail-closed?**  
No. The OOF-TY0 ambiguity path in P3 did not fire in any real app. No fleet type has two declared types with exactly identical field name sets. DSA's `ArrayIndexed`/`IntSet` case (same field names, different element types) was correctly disambiguated by `structurally_assignable?` recursing into Collection params.

**Q: Which failures remain after record literals resolve?**  
Remaining blockers by category: (1) Stringly call_contract("append",...): decision_tree, arch_patterns, vector_editor, bloom_filter. (2) stdlib.string import surface: igniter_parser. (3) String/Text alias: sim_framework SIM-P10/P11. (4) Dynamic contract dispatch: rule_engine RE-P02/03/04. (5) Field name mismatch (app source): vector_math VM-P10. (6) Collection[Unknown] param-depth gap: sim_framework SIM-P14, vector_editor VE-P09.

**Q: Is stringly stdlib call migration now the dominant cross-app blocker?**  
Yes. 4 apps (decision_tree, arch_patterns, vector_editor, bloom_filter) are blocked primarily by stringly call_contract("append",...). Resolving LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1 would clear or substantially reduce diagnostics in all 4.

**Q: Is stdlib.string surface now a separate dominant blocker?**  
Yes, with igniter_parser in the fleet. Both Rust and Ruby stop at OOF-IMP2 for `import stdlib.string.{ char_at }`. LANG-STDLIB-STRING-SURFACE-P1 is a distinct single-app blocker but high-value for self-hosting progression.

**Q: Is String/Text alias still isolated to sim_framework?**  
Yes. No other app in the fleet currently uses `concat(...)` to produce a field declared as `String`. The mismatch is specific to sim_framework's `rule_name` field.

**Q: Does bloom_filter become another stringly append migration proof source?**  
Yes. bloom_filter has 15 chained `call_contract("append", ...)` sites — the largest contiguous append chain in the fleet. It also exhibits the BOOTSTRAP shape (`call_contract("append", s0, s1)` two bare values). Once the stringly migration and `stdlib.collection.empty` are available, bloom_filter's InitFilter16 contract becomes a definitive test fixture for collection initialization patterns.

**Q: Which apps are now dual-toolchain CLEAN?**  
advanced_logistics (since Wave P3), dsa (Wave P6), dataframes (Wave P6), neural_net (Wave P6) — 4 total.
