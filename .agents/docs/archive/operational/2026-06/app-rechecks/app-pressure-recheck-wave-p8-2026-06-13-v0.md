# APP-RECHECK-WAVE-P8

**Date:** 2026-06-13
**Trigger:** LANG-STDLIB-STRING-SUBSTRING-P2 CLOSED + LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 CLOSED + LANG-STRING-TEXT-ALIAS-P2 CLOSED + LANG-RUBY-RECORD-LITERAL-INFERENCE-P5 CLOSED (+ LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED — gate-resolved before wave run)
**Scope:** All 12 apps — evidence + registry updates only; no compiler or app source changes in this wave
**Prior wave:** APP-RECHECK-WAVE-P7 (LANG-RUST-TYPED-COMPUTE-BINDING-P2 + LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3)

---

## Fleet Status (Wave P8)

| App | Rust | Ruby | Status | Notes |
|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P3 |
| arch_patterns | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P7 |
| bloom_filter | ok/0 | ok/0 | DUAL-CLEAN | Unchanged; BF-P03 RESOLVED (LAB-BLOOM-FILTER-RANGE-MIGRATION-P1) |
| dataframes | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| decision_tree | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since P2 migration |
| dsa | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| neural_net | ok/0 | ok/0 | DUAL-CLEAN | Unchanged since Wave P6 |
| **sim_framework** | **ok/0** | **ok/0** | **DUAL-CLEAN** | **NEW** — SIM-P10/P11/P14 all RESOLVED |
| vector_editor | ok/0 | oof/1 | RUST-CLEAN | Ruby VE-P09 (`new_obj`) — unchanged |
| vector_math | ok/0 | oof/36 | RUST-CLEAN | Ruby VM-P10 (field name mismatch) — unchanged |
| rule_engine | oof/2 | oof/2 | BLOCKED | RE-P04+RE-P07; Rust diagnostic form changed |
| igniter_parser | oof/5 | oof/7 | BLOCKED | IP-P06 NOW-ACTIVE (was IP-P01); major progress |

**Fleet total: 8/12 DUAL-CLEAN** (+1 vs Wave P7)

---

## Delta vs Wave P7

| App | Wave P7 Rust | Wave P7 Ruby | Wave P8 Rust | Wave P8 Ruby | Net |
|---|---|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | ok/0 | ok/0 | — |
| arch_patterns | ok/0 | ok/0 | ok/0 | ok/0 | — |
| bloom_filter | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dataframes | ok/0 | ok/0 | ok/0 | ok/0 | — |
| decision_tree | ok/0 | ok/0 | ok/0 | ok/0 | — |
| dsa | ok/0 | ok/0 | ok/0 | ok/0 | — |
| neural_net | ok/0 | ok/0 | ok/0 | ok/0 | — |
| sim_framework | ok/0 | oof/3 | ok/0 | **ok/0** | **−3 Ruby → DUAL-CLEAN** |
| vector_editor | ok/0 | oof/1 | ok/0 | oof/1 | — |
| vector_math | ok/0 | oof/36 | ok/0 | oof/36 | — |
| rule_engine | oof/2 | oof/2 | oof/2 | oof/2 | diag form changed (see below) |
| igniter_parser | oof/1 | oof/1 | oof/5 | oof/7 | IP-P01 cleared; IP-P06 exposed (+4 Rust, +6 Ruby) |

**Wave P8 net change:** sim_framework newly DUAL-CLEAN (+1). igniter_parser made structural progress (IP-P01 cleared, IP-P06 newly visible). rule_engine Rust diagnostic form changed. All other apps unchanged.

---

## What Made sim_framework DUAL-CLEAN

Three pressures resolved in sequence:

1. **LANG-STRING-TEXT-ALIAS-P2** (SIM-P10 + SIM-P11): `concat(String, String)` now returns `String` when both arguments are `String`. This resolved the `rule_name` field error (`expected String, got Text` → now `expected String, got String` → clean). SIM-P11 (OOF-TY1 cascade from SIM-P10) also cleared.

2. **LANG-RUBY-RECORD-LITERAL-INFERENCE-P5** (SIM-P14): Added `empty_collection_assignable?` helper + or-clause in `infer_record_literal` structural candidate filter. `compute initial_state = { ..., events: [], proofs: [], violations: [] }` — empty arrays now accepted as compatible with `Collection[T]` in the structural matching field check. `initial_state` correctly infers as `SimState`. `RunEcosystemSim` contract now error-free.

sim_framework is the **8th app to reach DUAL-CLEAN status.**

---

## igniter_parser — Structural Progress

The app made significant forward progress despite higher raw diagnostic counts:

| Metric | Wave P7 | Wave P8 |
|---|---|---|
| Rust diagnostics | 1 (OOF-IMP2) | 5 (OOF-TY0 ×5) |
| Ruby diagnostics | 1 (OOF-IMP2) | 7 (OOF-TY0 ×5 + OOF-P1 ×2) |
| First blocker | `stdlib.string` import unrecognized | `call_contract("empty")` callee unresolved |
| Root blockers resolved | — | IP-P01, IP-P02, IP-P05 |

**IP-P01 RESOLVED**: stdlib.string import now recognized by both toolchains. OOF-IMP2 gone.
**IP-P02 RESOLVED**: `char_at(state.source, state.pos)` compiles cleanly.
**IP-P05 RESOLVED**: `substring(state.source, state.pos, 6)` compiles cleanly; token text extraction demonstrated.
**IP-P06 NOW-ACTIVE**: 3× `call_contract("empty")` + 2× `call_contract("append")` in api.ig + parser.ig + lexer.ig expose stringly stdlib constructor calls. Ruby additionally cascades to OOF-P1: `initial_tokens`, `empty_children` (downstream of 'empty' returning Unknown).

Resolved by: LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 (LANG-STDLIB-STRING-SURFACE-P3 + LANG-STDLIB-STRING-SUBSTRING-P2 both satisfied as prerequisites).

Route for IP-P06: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`.

---

## rule_engine — Diagnostic Form Change

Rust count unchanged (oof/2), but content changed:

| Diagnostic | Wave P7 | Wave P8 |
|---|---|---|
| Rust diag 1 | OOF-TY1 `expected Collection[RuleDecision], got Collection[Unknown]` | OOF-P1 `Unresolved field: Unknown.action` |
| Rust diag 2 | OOF-TY1 `expected RuleDecision, got Unknown` | OOF-TY1 `expected RuleDecision, got Unknown` |
| Ruby diag 1 | OOF-P1 `Unresolved symbol: d` | OOF-P1 `Unresolved symbol: d` |
| Ruby diag 2 | OOF-P1 `Unresolved field: Unknown.action` | OOF-P1 `Unresolved field: Unknown.action` |

The collection-level OOF-TY1 (`Collection[RuleDecision] vs Collection[Unknown]`) no longer appears in Rust. The `Unknown.action` OOF-P1 (previously Ruby-only) now also appears in Rust. Root cause unchanged: Tier 2 dynamic dispatch. Safety signal still present. Route unchanged: `LAB-DYNAMIC-CONTRACT-DISPATCH-P1`.

---

## Pressure ID Changes This Wave

| ID | App | Before | After | Cause |
|---|---|---|---|---|
| SIM-P10 | sim_framework | ACTIVE | RESOLVED | LANG-STRING-TEXT-ALIAS-P2 CLOSED |
| SIM-P11 | sim_framework | ACTIVE | RESOLVED | LANG-STRING-TEXT-ALIAS-P2 CLOSED (cascade of SIM-P10) |
| SIM-P14 | sim_framework | ACTIVE | RESOLVED | LANG-RUBY-RECORD-LITERAL-INFERENCE-P5 CLOSED |
| IP-P01 | igniter_parser | ACTIVE | RESOLVED | LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED |
| IP-P02 | igniter_parser | ACTIVE | RESOLVED | LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED |
| IP-P05 | igniter_parser | ACTIVE | RESOLVED | LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1 CLOSED |
| IP-P06 | igniter_parser | HIDDEN-BEHIND-P01 | NOW-ACTIVE | Unblocked by IP-P01 resolution |
| RE-P04 | rule_engine | OOF-TY1 (Collection form) | OOF-TY1 (single-item form) + OOF-P1 Unknown.action | Rust TC diagnostic form changed; root cause unchanged |
| BF-P03 | bloom_filter | ACTIVE-DESIGN-PRESSURE | RESOLVED | LAB-BLOOM-FILTER-RANGE-MIGRATION-P1 CLOSED |

---

## Remaining Blockers

| App | ID | Diags | Root Cause | Toolchain | Route |
|---|---|---|---|---|---|
| vector_editor | VE-P09 | Ruby oof/1 | `Unresolved symbol: new_obj` — OOF-P1; Tier 2 dynamic `call_contract` result not bound | Ruby only | `LAB-VE-NEW-OBJ-INFERENCE-P1` or app refactor |
| vector_math | VM-P10 | Ruby oof/36 | Record literal field name mismatch: `x/y/z` in source vs `r0/r1/r2` in type declarations | Ruby only | Source fix: align field names in vec2.ig/vec3.ig vs type declarations |
| rule_engine | RE-P04 | Both oof/2 | OOF-TY1 `expected RuleDecision, got Unknown` + OOF-P1 `Unresolved field: Unknown.action` (Rust) — Tier 2 dynamic dispatch result Unknown | Both | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| rule_engine | RE-P07 | Ruby oof/2 | `Unresolved symbol: d` + `Unresolved field: Unknown.action` — Tier 2 dynamic callee result unbound | Ruby | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| igniter_parser | IP-P06 | Both oof/5+7 | Stringly `call_contract("empty"/"append")` — 3 empty + 2 append sites in api.ig, parser.ig, lexer.ig; Ruby additionally cascades to OOF-P1 unresolved symbols | Both | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` |

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
| 8 | sim_framework | Wave P8 | LANG-STRING-TEXT-ALIAS-P2 + LANG-RUBY-RECORD-LITERAL-INFERENCE-P5 |

**4 apps remain not dual-clean:** vector_editor (Ruby VE-P09), vector_math (Ruby VM-P10), rule_engine (both), igniter_parser (both).

---

## Likely Next Routes

| Priority | Card | Unlocks |
|---|---|---|
| 1 | `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1` | igniter_parser IP-P06 (3×empty + 2×append sites); vector_editor VE-P09-partial if new_obj is a stringly result |
| 2 | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` | rule_engine RE-P04/RE-P07 (d/Unknown.action — Tier 2 variable callee); possibly vector_editor VE-P09 if new_obj is dynamic dispatch |
| 3 | VM-P10 source fix | vector_math (field name alignment — app edit, not compiler card) |

---

## Non-Goals

- No compiler or app source changes in this wave.
- No new pressure IDs opened (all changes are resolutions or classifications of pre-existing pressures).
- No canon record updated.
- Registries are evidence only; they do not imply work authorization.
