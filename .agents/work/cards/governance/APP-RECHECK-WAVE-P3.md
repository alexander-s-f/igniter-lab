# APP-RECHECK-WAVE-P3

**Status:** CLOSED
**Date:** 2026-06-13
**Type:** governance / recheck

---

## Scope

Compile-and-report recheck of 9 apps after 3 infrastructure grounding cards landed since Wave P2.

Apps: dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net, vector_math, advanced_logistics.

---

## Grounding Cards (Gate)

All 3 confirmed CLOSED before recheck:

| Card | Status |
|---|---|
| LAB-RUBY-CALL-CONTRACT-PARITY-P3 | CLOSED 56/56 |
| LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 | CLOSED 61/61 |
| LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 | CLOSED 45/45 |

---

## Deliverables

- [x] Rollup doc: `igniter-lab/.agents/docs/app-pressure-recheck-wave-p3-2026-06-13-v0.md`
- [x] PRESSURE_REGISTRY.md updated for all 9 apps
- [x] Portfolio index updated (APP-RECHECK-WAVE-P3 CLOSED entry added)

---

## Resolved Pressures (9)

| ID | App | Resolution |
|---|---|---|
| DT-P02 | decision_tree | LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 — `label` in binding positions |
| DSA-P08 | dsa | LAB-RUBY-CALL-CONTRACT-PARITY-P3 — 9 call_contract errors → 0 |
| DF-P08 | dataframes | LAB-RUBY-CALL-CONTRACT-PARITY-P3 — 6 call_contract errors → 0 |
| NN-P08 | neural_net | LAB-RUBY-CALL-CONTRACT-PARITY-P3 — 7 call_contract errors + 3 cascade mismatches → 0 |
| VM-P06 | vector_math | LAB-RUBY-CALL-CONTRACT-PARITY-P3 — 26 call_contract errors → 0 |
| VM-P07 | vector_math | LANG-STDLIB-NUMERIC-COMPARISON-P3 — 8 `<` operator errors → 0 |
| VM-P04 | vector_math | LANG-UNARY-OPERATORS-P3/P4 — unary minus dual-toolchain |
| AL-P01 | advanced_logistics | LANG-STDLIB-COLLECTION-APPEND-PROP-P3/P4 + LANG-STDLIB-IS-EMPTY-PROP-P3/P4 — import surface CLEAN |
| AL-P04 | advanced_logistics | LANG-STDLIB-NUMERIC-COMPARISON-P3 — `<` operator Ruby |

---

## New Pressures Opened (10)

| ID | App | Pressure |
|---|---|---|
| DSA-P10 | dsa | Typed compute binding gap — 4 unresolved symbols |
| VE-P08 | vector_editor | Typed compute binding gap — 3 unresolved symbols |
| DT-P09 | decision_tree | Typed compute binding gap — 3 unresolved symbols |
| AP-P11 | arch_patterns | OOF-TY1 cascade from append failure |
| AP-P12 | arch_patterns | Typed compute binding gap — 4 unresolved symbols |
| DF-P10 | dataframes | Typed compute binding gap — 2 unresolved symbols |
| RE-P07 | rule_engine | Typed compute binding gap for Tier 2 dynamic dispatch |
| NN-P09 | neural_net | Typed compute binding gap — 2 unresolved symbols |
| VM-P09 | vector_math | Typed compute binding gap — 5 unresolved symbols |
| VM-P10 | vector_math | Record literal field name mismatch — 36 diags |

---

## Key Findings

- **advanced_logistics** achieved dual-toolchain CLEAN — first app in the fleet.
- **Typed Compute Binding gap** is the new dominant cross-app pattern (8 of 9 apps). Route: `LANG-TYPED-COMPUTE-BINDING-P1`.
- **STDLIB-form call_contract** (`call_contract("append",...)`) still blocked in both toolchains; affects VE/DT/AP. Route: stdlib migration after `LANG-STDLIB-COLLECTION-EMPTY-P1`.
- **OOF-TY1** from output assignability now correctly fires in both toolchains (AP-P11, RE-P04) — safety-positive.
- **vector_math** newly surfaces 36 record literal field name mismatch diagnostics (VM-P10) after upstream Unknown is resolved — may be app-source hygiene, not a language gap.

---

## Closed Surfaces

- No app source edits made.
- No proposals authored.
- No implementations written.
- No baseline hashes changed.
