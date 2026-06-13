# APP-RECHECK-WAVE-P3 Rollup

**Date:** 2026-06-13
**Recheck scope:** 9 apps — dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net, vector_math, advanced_logistics
**Governance card:** `igniter-lab/.agents/work/cards/governance/APP-RECHECK-WAVE-P3.md`
**Status:** CLOSED

---

## Gate Check

All 3 grounding cards confirmed CLOSED before recheck:

| Card | Status | Impact |
|---|---|---|
| LAB-RUBY-CALL-CONTRACT-PARITY-P3 | CLOSED 56/56 | Ruby TC `when "call_contract"` arm; Tier 1 literal same-module lookup + Tier 2 dynamic → Unknown |
| LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 | CLOSED 61/61 | Ruby parser `name_token!` accepts `%i[ident keyword]` in all binding positions |
| LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 | CLOSED 45/45 | Rust TC rejects Collection[Unknown]→Collection[T] at output boundary (OOF-TY1) |

---

## Compile Results

| App | Rust status | Rust diags | Ruby status | Ruby diags |
|---|---|---|---|---|
| dsa | ok | 0 | oof | 4 (Unresolved: e0/s/edge1/c_h) |
| vector_editor | oof | 1 (append callee) | oof | 4 (1× append + 3× unresolved) |
| decision_tree | oof | 4 (all append callee) | oof | 7 (4× append + 3× unresolved) |
| arch_patterns | oof | 8 (7× append + 1× OOF-TY1) | oof | 14 (9× append + 1× OOF-TY1 + 4× unresolved) |
| dataframes | ok | 0 | oof | 2 (Unresolved: c00/p1) |
| rule_engine | oof | 2 (2× OOF-TY1) | oof | 3 (Unresolved: d; Unknown.action; Unresolved: tx1) |
| neural_net | ok | 0 | oof | 2 (Unresolved: w1/x1) |
| vector_math | ok | 0 | oof | 41 (5× unresolved + 36× record literal mismatch) |
| advanced_logistics | ok | 0 | ok | 0 **CLEAN** |

---

## Status Changes

### Resolved pressures (9 total)

| ID | App | Pressure | Resolved by |
|---|---|---|---|
| DT-P02 | decision_tree | Ruby parser keyword hygiene (`label`) | LANG-PARSER-CONTEXTUAL-KEYWORDS-P2 |
| DSA-P08 | dsa | Ruby call_contract parity (9 errors → 0) | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| DF-P08 | dataframes | Ruby call_contract parity (6 errors → 0) | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| NN-P08 | neural_net | Ruby call_contract parity (7 errors → 0; 3 cascade output mismatches also cleared) | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| VM-P06 | vector_math | Ruby call_contract parity (26 errors → 0) | LAB-RUBY-CALL-CONTRACT-PARITY-P3 |
| VM-P07 | vector_math | Ruby `<` operator (8 errors → 0) | LANG-STDLIB-NUMERIC-COMPARISON-P3 |
| VM-P04 | vector_math | Unary negative literal workaround | LANG-UNARY-OPERATORS-P3/P4 |
| AL-P01 | advanced_logistics | stdlib.collection import surface (OOF-IMP2 → CLEAN) | LANG-STDLIB-COLLECTION-APPEND-PROP-P3/P4 + LANG-STDLIB-IS-EMPTY-PROP-P3/P4 |
| AL-P04 | advanced_logistics | Ruby comparison operator parity (`<`) | LANG-STDLIB-NUMERIC-COMPARISON-P3 |

### Status changes (non-resolution)

| ID | App | Change | Reason |
|---|---|---|---|
| RE-P01 | rule_engine | Rust baseline superseded (was CLEAN; now oof/2) | LANG-OUTPUT-TYPE-ASSIGNABILITY-P4 now fires OOF-TY1 in Rust — safety-positive, not regression |
| RE-P04 | rule_engine | ACTIVE/CONFIRMED in Rust (was Ruby-only) | LANG-OUTPUT-TYPE-ASSIGNABILITY-P4; Rust now emits 2× OOF-TY1 |
| VE-P03 | vector_editor | Evidence updated (7 → 4 Ruby diags) | 4 Tier 1 same-module calls resolved; stdlib-form 'append' still blocked |
| AP-P02 | arch_patterns | Evidence updated (39 → 14 Ruby diags) | 25 Tier 1 calls resolved; stdlib-form still blocked; new OOF-TY1 |

### New pressures opened

| ID | App | Pressure | Route |
|---|---|---|---|
| DSA-P10 | dsa | Typed compute binding gap (4 unresolved: e0/s/edge1/c_h) | LANG-TYPED-COMPUTE-BINDING-P1 |
| VE-P08 | vector_editor | Typed compute binding gap (3 unresolved: new_objects/default_style/new_pos) | LANG-TYPED-COMPUTE-BINDING-P1 |
| DT-P09 | decision_tree | Typed compute binding gap (3 unresolved: new_nodes/nodes_0/features_good) | LANG-TYPED-COMPUTE-BINDING-P1 |
| AP-P11 | arch_patterns | OOF-TY1 cascade from append failure → Collection[Transition] output boundary | stdlib migration clears cascade |
| AP-P12 | arch_patterns | Typed compute binding gap (genesis + new_trail ×3) | LANG-TYPED-COMPUTE-BINDING-P1 |
| DF-P10 | dataframes | Typed compute binding gap (2 unresolved: c00/p1) | LANG-TYPED-COMPUTE-BINDING-P1 |
| RE-P07 | rule_engine | Typed compute binding gap for Tier 2 dynamic dispatch (d/tx1 unbound; Unknown.action cascade) | LANG-TYPED-COMPUTE-BINDING-P1 + LAB-DYNAMIC-CONTRACT-DISPATCH-P1 |
| NN-P09 | neural_net | Typed compute binding gap (2 unresolved: w1/x1) | LANG-TYPED-COMPUTE-BINDING-P1 |
| VM-P09 | vector_math | Typed compute binding gap (5 unresolved: gravity/point/b/a_min/min_pt) | LANG-TYPED-COMPUTE-BINDING-P1 |
| VM-P10 | vector_math | Record literal field name mismatch (36 diags: missing r0/r1/r2; unexpected x/y/z) | field name alignment investigation |

---

## Cross-App Analysis

### Dominant pattern: Typed Compute Binding gap

The most significant cross-app pattern surfaced in Wave P3 is the **Typed Compute Binding gap**. When LAB-RUBY-CALL-CONTRACT-PARITY-P3 resolves Tier 1 same-module calls and returns properly typed output, the output variable is not registered in `symbol_types` for subsequent expressions. This causes "Unresolved symbol" cascades wherever those output variables are referenced downstream.

**Affects:** dsa, vector_editor, decision_tree, arch_patterns, dataframes, neural_net, vector_math, rule_engine (8 of 9 apps)
**Route:** `LANG-TYPED-COMPUTE-BINDING-P1`

This is the next highest-priority language gap after stdlib-form call_contract.

### Dominant structural blocker: STDLIB-form call_contract

`call_contract("append", ...)` is still not dispatched in either toolchain. This is the STDLIB_FORM tier documented in LAB-RUBY-CALL-CONTRACT-PARITY-P1. All apps that use `append` via stringly call_contract are blocked:

- **Rust:** VE (1 diag), DT (4 diags), AP (7 diags)
- **Ruby:** VE (1 diag), DT (4 diags), AP (9 diags)

Route: stringly stdlib migration (LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1) after LANG-STDLIB-COLLECTION-EMPTY-P1.

### OOF-TY1 cascade pattern

LANG-OUTPUT-TYPE-ASSIGNABILITY-P3/P4 now correctly fires OOF-TY1 when Unknown propagates to a typed output boundary. This surfaces two ways:
1. **Append failure cascade** (AP-P11): append returns Unknown → output annotated as Collection[Transition] → OOF-TY1 in both toolchains. Clears when stdlib append resolves.
2. **Dynamic dispatch** (RE-P04): call_contract with variable callee returns Unknown → Collection[RuleDecision] output boundary → OOF-TY1 in Rust. Route: LAB-DYNAMIC-CONTRACT-DISPATCH-P1.

Both are safety-positive signals.

### Advanced logistics: CLEAN

`advanced_logistics` achieved **dual-toolchain CLEAN status** in Wave P3 — the first app in the fleet to do so. AL-P01 (import surface) and AL-P04 (comparison operator) resolved. AL-P03 (stringly call_contract for FindFeasibleOrders) also CLEAN because Tier 1 literal callee lookup now works in both toolchains.

### vector_math: record literal mismatch

After call_contract P3 resolves Tier 1 calls and propagates proper types downstream, `vector_math` surfaces 36 new diagnostics: "missing required field: r0/r1/r2" + "unexpected field: x/y/z". These were previously masked by Unknown propagation. This may be an app-source field-naming inconsistency between type declarations and record literal call sites, not a language feature gap.

---

## Per-App Summary

### dsa
Wave P3: Rust CLEAN / Ruby oof/4. DSA-P08 RESOLVED (call_contract parity P3; 9 errors gone). New: DSA-P10 ACTIVE (typed compute binding; 4 unresolved symbols).

### vector_editor
Wave P3: Rust oof/1 / Ruby oof/4. 4 Tier 1 Ruby calls resolved; VE-P03 updated. VE-P02 still ACTIVE (stdlib append in Rust). New: VE-P08 ACTIVE (typed compute binding cascade).

### decision_tree
Wave P3: Rust oof/4 / Ruby oof/7. DT-P02 RESOLVED (label keyword parse fix). Ruby now progresses to TC; surfaces stdlib append + typed compute binding. New: DT-P09 ACTIVE.

### arch_patterns
Wave P3: Rust oof/8 / Ruby oof/14. Ruby reduced from 39 to 14 diags (25 Tier 1 calls resolved). New: AP-P11 ACTIVE (OOF-TY1 cascade), AP-P12 ACTIVE (typed compute binding).

### dataframes
Wave P3: Rust CLEAN / Ruby oof/2. DF-P08 RESOLVED (all 6 call_contract errors gone). New: DF-P10 ACTIVE (typed compute binding; 2 unresolved).

### rule_engine
Wave P3: Rust oof/2 / Ruby oof/3. RE-P01 baseline superseded (Rust now oof/2 from OOF-TY1 — safety-positive). RE-P04 CONFIRMED in both toolchains. Ruby call_contract errors resolved (9 → 3). New: RE-P07 ACTIVE (Tier 2 dynamic dispatch typed compute binding).

### neural_net
Wave P3: Rust CLEAN / Ruby oof/2. NN-P08 RESOLVED (7 call_contract errors + 3 cascade output mismatches gone). New: NN-P09 ACTIVE (typed compute binding; 2 unresolved).

### vector_math
Wave P3: Rust CLEAN / Ruby oof/41. VM-P06 RESOLVED (26 call_contract errors gone). VM-P07 RESOLVED (8 `<` operator errors gone). New: VM-P09 ACTIVE (typed compute binding; 5 unresolved), VM-P10 ACTIVE (record literal mismatch; 36 diags).

### advanced_logistics
Wave P3: Rust CLEAN / Ruby CLEAN. AL-P01 RESOLVED (import surface). AL-P04 RESOLVED (comparison operator). First dual-toolchain CLEAN app in the fleet.

---

## Recommended Next Cards

1. **LANG-TYPED-COMPUTE-BINDING-P1** — highest-priority gap; affects 8 of 9 apps; typed call_contract outputs not registered in symbol_types; resolves dozens of cascade "Unresolved symbol" errors.
2. **LANG-STDLIB-COLLECTION-EMPTY-P1** — prerequisite for stringly stdlib migration; `empty()` constructor needed for 9 BOOTSTRAP/EMPTY_CONSTRUCTOR call sites.
3. **LANG-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1** — 25 ACCUMULATING `call_contract("append",...)` sites can migrate to direct `append(...)` after empty() is available; clears VE/DT/AP dominant blockers.
4. **LAB-DYNAMIC-CONTRACT-DISPATCH-P1** — RE-P02/P04/P07 typed dispatch with receipt semantics.
5. **VM-P10 investigation** — verify whether record literal field mismatch is an app-source hygiene issue or a type declaration inconsistency; not a language gap.
