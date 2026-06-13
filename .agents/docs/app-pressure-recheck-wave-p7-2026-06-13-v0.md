# APP-RECHECK-WAVE-P7

**Date:** 2026-06-13  
**Trigger:** LANG-RUST-TYPED-COMPUTE-BINDING-P2 CLOSED + LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 CLOSED  
**Scope:** All 12 apps — evidence + registry updates only; no compiler or app source changes in this wave  
**Prior wave:** APP-RECHECK-WAVE-P6 (LANG-RUBY-RECORD-LITERAL-INFERENCE-P3)

---

## Fleet Status (Wave P7)

| App | Rust | Ruby | Status | Notes |
|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P3 |
| arch_patterns | **ok/0** | **ok/0** | **DUAL-CLEAN** | **NEW** — P2+P3 migration |
| bloom_filter | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since P2 migration |
| dataframes | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| decision_tree | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since P2 migration |
| dsa | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| neural_net | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| vector_editor | ok/0 | oof/1 | RUST-CLEAN | Ruby VE-P09 (`new_obj`) |
| vector_math | ok/0 | oof/36 | RUST-CLEAN | Ruby VM-P10 (field name mismatch) |
| sim_framework | ok/0 | oof/3 | RUST-CLEAN | Ruby SIM-P10/P11/P14 |
| rule_engine | oof/2 | oof/2 | BLOCKED | RE-P04 + RE-P07 partial |
| igniter_parser | oof/1 | oof/1 | BLOCKED | IP-P01 (stdlib.string) |

**Fleet total: 7/12 DUAL-CLEAN**

---

## Delta vs Wave P6

| App | Wave P6 Rust | Wave P6 Ruby | Wave P7 Rust | Wave P7 Ruby | Net |
|---|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | ok/0 | ok/0 | — |
| arch_patterns | oof/8 | oof/14 | ok/0 | ok/0 | **−8 Rust, −14 Ruby** |
| bloom_filter | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dataframes | ok/0 | ok/0 | ok/0 | ok/0 | — |
| decision_tree | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dsa | ok/0 | ok/0 | ok/0 | ok/0 | — |
| neural_net | ok/0 | ok/0 | ok/0 | ok/0 | — |
| vector_editor | ok/0 | oof/1 | ok/0 | oof/1 | — |
| vector_math | ok/0 | oof/36 | ok/0 | oof/36 | — |
| sim_framework | ok/0 | oof/3 | ok/0 | oof/3 | — |
| rule_engine | oof/2 | oof/2 | oof/2 | oof/2 | — |
| igniter_parser | oof/1 | oof/1 | oof/1 | oof/1 | — |

**Wave P7 net change:** arch_patterns newly DUAL-CLEAN (+1). All other apps unchanged from Wave P6.

The P2 Rust TC fix + P3 source migration together cleared arch_patterns' 22 accumulated diagnostics (8 Rust + 14 Ruby). No regressions in any previously-clean app.

---

## What Made arch_patterns Clean

Two cards closed in sequence:

1. **LANG-RUST-TYPED-COMPUTE-BINDING-P2**: Added `fn unknown_or_unknown_bearing` helper + annotation override block to Rust TC's compute arm. When the inferred RHS type is Unknown or Unknown-bearing, the explicit annotation is authoritative and propagated into `symbol_types`. This unblocked the BOOTSTRAP migration shape.

2. **LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3**: Migrated 5 deferred stringly `call_contract("append", ...)` sites in `BuildTransitionTable` (arch_patterns/example.ig):
   - `c0`: BOOTSTRAP shape → `compute c0 : Collection[Transition] = [t0, t1]`
   - `c1–c4`: ACCUMULATING shape → `append(cx, ty)`
   
   With the P2 Rust fix active, the `Collection[Transition]` annotation on `c0` is authoritative even though `[t0, t1]` infers to Unknown (t0/t1 are unannotated record literals). c1–c4 then accumulate correctly via the OOF-COL6 guard (`item_name == "Unknown"` → guard skipped → result `Collection[Transition]`).

---

## Remaining Blockers

| App | ID | Diags | Root Cause | Toolchain | Route |
|---|---|---|---|---|---|
| vector_editor | VE-P09 | Ruby oof/1 | `Unresolved symbol: new_obj` — OOF-P1; `new_obj` is a Tier 2 dynamic `call_contract` result not bound in symbol_types; no structural candidate | Ruby only | `LAB-VE-NEW-OBJ-INFERENCE-P1` or app refactor |
| vector_math | VM-P10 | Ruby oof/36 | Record literal field name mismatch: `x/y/z` in source vs `r0/r1/r2` in type declarations (or vice versa); not a compiler feature gap — field names must align | Ruby only | Source fix: align field names in vec2.ig/vec3.ig vs type declarations |
| sim_framework | SIM-P10 | Ruby oof/1 | `record literal field 'rule_name': expected String, got Text`; `concat(...)` returns type "Text", declaration expects "String" | Ruby only | `LANG-STRING-TEXT-ALIAS-P1` |
| sim_framework | SIM-P11 | Ruby oof/1 | OOF-TY1 cascade from SIM-P10 String/Text mismatch | Ruby only | Clears when SIM-P10 resolves |
| sim_framework | SIM-P14 | Ruby oof/1 | `Unresolved symbol: initial_state` — `compute initial_state = { ... events: [], proofs: [], violations: [] }` produces `Collection[Unknown]` for empty array fields; `structurally_assignable?(Collection[Unknown], Collection[SimEvent])` returns false at param depth | Ruby only | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` (param-depth permissive) or app annotation |
| rule_engine | RE-P04 | Rust oof/2 | OOF-TY1: `Output type mismatch: expected Collection[RuleDecision], got Collection[Unknown]` + `expected RuleDecision, got Unknown` — safety-positive; Tier 2 dynamic dispatch result is Unknown and not coerceable | Both | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` + `LAB-OUTPUT-TYPE-PARAMETER-CHECK-P2` |
| rule_engine | RE-P07 | Ruby oof/2 | `Unresolved symbol: d` + `Unresolved field: Unknown.action` — Tier 2 dynamic `call_contract(variable_callee, ...)` result not bound; `tx1` sub-pressure RESOLVED (Wave P6) | Ruby | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| igniter_parser | IP-P01 | Both oof/1 | `OOF-IMP2: unknown stdlib module path 'stdlib.string'` — `stdlib.string` not in compiler stdlib inventory | Both | `LANG-STDLIB-STRING-SURFACE-P1` |

---

## Pressure ID Changes This Wave

| ID | App | Before | After | Cause |
|---|---|---|---|---|
| AP-P02 | arch_patterns | PARTIALLY-RESOLVED | RESOLVED | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 |
| AP-P11 | arch_patterns | ACTIVE | RESOLVED | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 |

*(All other pressure ID changes — VM-P09, SIM-P12, SIM-P13, NN-P09, DSA-P10, DF-P10, RE-P07-tx1 — occurred in Wave P6 via LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 and are now reflected in the registry table rows for the first time.)*

---

## Clean App Scoreboard

| # | App | Achieved At | Card |
|---|---|---|---|
| 1 | advanced_logistics | Wave P3 | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| 2 | bloom_filter | P2 migration | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 |
| 3 | decision_tree | P2 migration | LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2 |
| 4 | dataframes | Wave P6 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| 5 | dsa | Wave P6 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| 6 | neural_net | Wave P6 | LANG-RUBY-RECORD-LITERAL-INFERENCE-P3 |
| 7 | arch_patterns | Wave P7 | LANG-RUST-TYPED-COMPUTE-BINDING-P2 + LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 |

**5 apps remain not dual-clean:** vector_editor (Ruby VE-P09), vector_math (Ruby VM-P10), sim_framework (Ruby SIM-P10/P11/P14), rule_engine (both), igniter_parser (both).

---

## Likely Next Routes

| Priority | Card | Unlocks |
|---|---|---|
| 1 | `LANG-STDLIB-STRING-SURFACE-P1` | igniter_parser IP-P01 (5 additional stringly sites then migratable); sim_framework SIM-P10 if alias is resolved there |
| 2 | `LANG-STRING-TEXT-ALIAS-P1` | sim_framework SIM-P10/P11 (String/Text alias in `concat` return type) |
| 3 | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` | sim_framework SIM-P14 (param-depth `Collection[Unknown]` permissive extension) |
| 4 | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` | rule_engine RE-P07 (d/Unknown.action); vector_editor VE-P09 (new_obj if it is Tier 2) |
| 5 | VM-P10 source fix | vector_math (field name alignment — app edit, not compiler card) |

---

## Non-Goals

- No compiler or app source changes in this wave.
- No new pressure IDs opened (all blockers were already documented).
- No canon record updated.
- Registries are evidence only; they do not imply work authorization.
