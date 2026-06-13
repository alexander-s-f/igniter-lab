# APP-RECHECK-WAVE-P7

**Status:** CLOSED  
**Date closed:** 2026-06-13  
**Lane:** governance / app-pressure recheck  
**Trigger:** LANG-RUST-TYPED-COMPUTE-BINDING-P2 CLOSED + LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 CLOSED  
**Rollup doc:** `igniter-lab/.agents/docs/app-pressure-recheck-wave-p7-2026-06-13-v0.md`

---

## Summary

Rechecked all 12 apps after the Rust TC typed compute binding fix (P2) and the arch_patterns stringly migration (P3). Updated all 12 PRESSURE_REGISTRY.md files with Wave P7 check sections and brought stale table rows up to date.

**arch_patterns is now DUAL-TOOLCHAIN CLEAN** — the 7th app in the fleet.

All other apps: unchanged from Wave P6 state.

---

## Fleet Result

| App | Rust | Ruby | Status |
|---|---|---|---|
| advanced_logistics | ok/0 | ok/0 | DUAL-CLEAN |
| arch_patterns | ok/0 | ok/0 | **DUAL-CLEAN (NEW)** |
| bloom_filter | ok/0 | ok/0 | DUAL-CLEAN |
| dataframes | ok/0 | ok/0 | DUAL-CLEAN |
| decision_tree | ok/0 | ok/0 | DUAL-CLEAN |
| dsa | ok/0 | ok/0 | DUAL-CLEAN |
| neural_net | ok/0 | ok/0 | DUAL-CLEAN |
| vector_editor | ok/0 | oof/1 | RUST-CLEAN / Ruby VE-P09 |
| vector_math | ok/0 | oof/36 | RUST-CLEAN / Ruby VM-P10 |
| sim_framework | ok/0 | oof/3 | RUST-CLEAN / Ruby SIM-P10/P11/P14 |
| rule_engine | oof/2 | oof/2 | BLOCKED (RE-P04 + RE-P07 partial) |
| igniter_parser | oof/1 | oof/1 | BLOCKED (IP-P01 stdlib.string) |

**7/12 DUAL-CLEAN** (up from 6/12 at Wave P6).

---

## Pressure ID Updates

| ID | App | Before | After |
|---|---|---|---|
| AP-P02 | arch_patterns | PARTIALLY-RESOLVED | RESOLVED |
| AP-P11 | arch_patterns | ACTIVE | RESOLVED |
| VM-P09 | vector_math | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| SIM-P12 | sim_framework | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| SIM-P13 | sim_framework | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| DSA-P10 | dsa | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| NN-P09 | neural_net | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| DF-P10 | dataframes | ACTIVE *(table stale)* | RESOLVED *(P6, now recorded)* |
| RE-P07 | rule_engine | ACTIVE *(table stale)* | PARTIALLY-RESOLVED *(tx1 RESOLVED P6; d/Unknown.action active)* |

---

## Remaining Blockers Summary

| App | Blocker | Route |
|---|---|---|
| vector_editor | VE-P09 (`new_obj` — OOF-P1) | `LAB-VE-NEW-OBJ-INFERENCE-P1` |
| vector_math | VM-P10 (36× field name mismatch) | Source fix: align x/y/z ↔ r0/r1/r2 |
| sim_framework | SIM-P10 (String/Text alias) + SIM-P11 cascade + SIM-P14 (Collection[Unknown] param-depth) | `LANG-STRING-TEXT-ALIAS-P1` + `LANG-RUBY-RECORD-LITERAL-INFERENCE-P4` |
| rule_engine | RE-P04 (Rust OOF-TY1) + RE-P07 partial (d/Unknown.action) | `LAB-DYNAMIC-CONTRACT-DISPATCH-P1` |
| igniter_parser | IP-P01 (`stdlib.string` import) | `LANG-STDLIB-STRING-SURFACE-P1` |

---

## Acceptance Criteria Met

- [x] All 12 PRESSURE_REGISTRY.md files updated with Wave P7 check section
- [x] Stale table rows (P6 resolutions not recorded) corrected in all affected registries
- [x] arch_patterns DUAL-CLEAN status confirmed and recorded (AP-P02 / AP-P11 RESOLVED)
- [x] Rollup doc written with fleet status, delta vs P6, blocker table, clean app scoreboard
- [x] No compiler or app source changes made
- [x] Portfolio index updated
