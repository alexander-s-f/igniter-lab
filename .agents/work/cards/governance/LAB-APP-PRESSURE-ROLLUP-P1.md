# LAB-APP-PRESSURE-ROLLUP-P1 — App Pressure Rollup

**Track:** governance / backlog shaping
**Route:** NO IMPLEMENTATION
**Status:** CLOSED — decisions recorded
**Date:** 2026-06-12
**Scope:** advanced_logistics, vector_editor, decision_tree, vector_math, spreadsheet, bookkeeping, erp_logistics

---

## Decision: Rollup Complete

All 7 app pressure registries and reports consolidated. Cluster analysis, ranking, 10-card sequence, and stale findings written to:

`igniter-lab/.agents/docs/app-pressure-rollup-2026-06-12-v0.md`

---

## App Status Summary

| App | Rust | Ruby | First Unblock Card |
|-----|------|------|--------------------|
| vector_math | ✅ OK (37 contracts) | ❌ call_contract × 26, `<` × 8 | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |
| spreadsheet | ✅ OK (recursion resolved) | ❌ call_contract, map | LAB-RUBY-CALL-CONTRACT-PARITY-P1 |
| advanced_logistics | ❌ OOF-IMP2 | ❌ OOF-IMP2 | LANG-STDLIB-IMPORT-SURFACE-P3 |
| vector_editor | ❌ OOF-IMP2 | ❌ OOF-IMP2 | LANG-STDLIB-IMPORT-SURFACE-P3 |
| decision_tree | ❌ OOF-IMP2 × 3, keyword | ❌ OOF-IMP2 + keyword | LANG-STDLIB-IMPORT-SURFACE-P3 |
| erp_logistics | ❌ Float `<` + `*` | ❌ call_contract, filter/fold | LAB-STDLIB-FLOAT-P1 (gated) |
| bookkeeping | ❌ Decimal == + literal | ❌ call_contract, filter/map/sum/fold | LAB-STDLIB-DECIMAL-P1 |

---

## Cluster Summary (13 clusters)

| Cluster | IDs | Apps |
|---------|-----|------|
| A — Stdlib import surface | AL-P01, VE-P01, DT-P01 | 3 (blocked at resolver) |
| B — append | VE-P02, DT-P03 | 2 |
| C — map/filter/count regular-call | AL-P02, BK-P04, ERP-P05, SS-P05 | 4 |
| D — fold/sum regular-call | BK-P04, ERP-P05 | 2 |
| E — call_contract | AL-P03, VE-P03, DT-P08, VM-P06, SS-P06, BK-P06, ERP-P06 | 7 (ALL) |
| F — text equality | VE-P04, DT-P05 | 2 |
| G1 — Integer comparison (Ruby) | AL-P04, VM-P05, VM-P07 | 2 |
| G2 — Float operators (both) | ERP-P02, ERP-P03 | 1 |
| G3 — Decimal semantics | BK-P02, BK-P03 | 1 |
| H — find_one/head | DT-P04 | 1 |
| I — ADT/variant | VE-P05, DT-P07 | 2 |
| J — app-state/assembly | VE-P06 | 1 |
| K — Ruby multi-file diag attribution | BK-P07, ERP-P08 | 2 |

---

## Mainline

| Card | Cluster | Unblocks |
|------|---------|----------|
| LANG-STDLIB-IMPORT-SURFACE-P3 | A | AL, VE, DT at OOF-IMP2 barrier |
| LAB-VECTOR-MATH-BASELINE-P1 | — | VM regression freeze (parallel) |
| LANG-STDLIB-COLLECTION-APPEND-P1 | B | VE, DT post-import |
| LANG-STDLIB-TEXT-EQUALITY-P1 | F | VE, DT (Ruby ==) |
| LAB-RUBY-CALL-CONTRACT-PARITY-P1 | E | VM, SS, BK, ERP + cascade |

---

## Near Backlog

| Card | Cluster |
|------|---------|
| LANG-NUMERIC-COMPARISON-PARITY-P1 | G1 |
| LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1 | K |
| LANG-STDLIB-FOLD-PROP-P4 + LANG-STDLIB-SUM-PROP-P4 | D |
| LAB-STDLIB-FIND-ONE-P1 | H |
| LAB-STDLIB-DECIMAL-P1 | G3 |

---

## Watch

ADT/variant (PROP-044), app-state/assembly, Float operators, Option arithmetic audit (SS-P04), unary minus (both toolchains), inline record in HOF (historical), Result constructors, Ruby parser keyword `label` (DT-P02), build closure tooling (ERP-P07).

---

## Recommended Next 10-Card Sequence

1. LANG-STDLIB-IMPORT-SURFACE-P3 — Ruby multifile stdlib table; 61-check proof
2. LAB-VECTOR-MATH-BASELINE-P1 — freeze VM Rust fixture (parallel with 1)
3. LANG-STDLIB-COLLECTION-APPEND-P1 — inventory entry + Ruby/Rust proof
4. LANG-STDLIB-TEXT-EQUALITY-P1 — Text == in Ruby (parallel with 3)
5. LAB-RUBY-CALL-CONTRACT-PARITY-P1 — decision card on typed invocation for Ruby
6. LANG-NUMERIC-COMPARISON-PARITY-P1 — Ruby `<` / `<=` / `>=` for Integer
7. LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1 — diagnostic attribution fix (parallel)
8. LANG-STDLIB-FOLD-PROP-P4 + LANG-STDLIB-SUM-PROP-P4 — inventory amendments
9. LAB-STDLIB-FIND-ONE-P1 — DT-P04 head/first/find_one
10. LAB-STDLIB-DECIMAL-P1 — BK-P02/P03 Decimal == and literal

---

## Stale / Contradictory Findings (5 items)

Full detail in rollup doc §5. Summary:

| # | Finding | Action |
|---|---------|--------|
| S1 | `Float?` arithmetic silently accepted in Rust (SS-P04) — may mask type safety gap | LAB-STDLIB-OPTION-P1 audit before trusting spreadsheet "ok" for numerics |
| S2 | VE-P05 / DT-P07 framed as ergonomic "watch" — should be CORRECTNESS gap | Re-classify; PROP-044 P2+ is required, not optional comfort |
| S3 | BK-P01 "improved" framing implies partial progress — actually correct behavior | Mark CLOSED; single-file without full closure is designed to fail |
| S4 | VM-P04 + ERP-P04 are the same unary minus pressure in separate registries | Merge → LANG-PARSER-UNARY-MINUS-P1; ERP-P04 needs fresh proof |
| S5 | AL-P05 + SS-P07 are the same inline-record-in-HOF pressure in separate registries | Merge → LAB-PARSER-RECORD-IN-HOF-P1; both need fresh minimal fixture |

**SS-P05 additional:** "Unknown function: map" may be stale after LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P3 — re-run spreadsheet Ruby before treating as active.

**BK-P07 / ERP-P08 priority note:** Ruby multi-file diagnostic attribution smear should be NEAR BACKLOG, not just "suspected" — it corrupts diagnostic context for all multi-file Ruby compiles.

---

## Authority Closed

No implementation. No app source edits. No stdlib, TC, parser, VM, or import resolver changes. Routing evidence only.

---

## Predecessor Cards

- LANG-STDLIB-IMPORT-SURFACE-P1 (CLOSED)
- LANG-STDLIB-IMPORT-SURFACE-P2 (CLOSED / READY FOR P3)

## Next Cards

**Immediate:** LANG-STDLIB-IMPORT-SURFACE-P3, LAB-VECTOR-MATH-BASELINE-P1 (parallel)
