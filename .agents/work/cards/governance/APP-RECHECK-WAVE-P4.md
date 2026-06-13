# APP-RECHECK-WAVE-P4

**Status:** CLOSED
**Date:** 2026-06-13
**Trigger:** LANG-TYPED-COMPUTE-BINDING-P2 CLOSED (48/48 PASS)
**Rollup doc:** `igniter-lab/.agents/docs/app-pressure-recheck-wave-p4-2026-06-13-v0.md`

---

## Scope

Fresh compile recheck across all 10 igniter-apps after LANG-TYPED-COMPUTE-BINDING-P2 landed. Evidence and PRESSURE_REGISTRY.md updates only. No app source edits, no compiler/typechecker/parser implementation, no stdlib proposal, no dynamic dispatch implementation.

Apps checked: dsa, vector_editor, decision_tree, arch_patterns, dataframes, rule_engine, neural_net, vector_math, advanced_logistics, sim_framework.

---

## Deliverables Completed

- [x] dsa/PRESSURE_REGISTRY.md — DSA-P10 re-routed + Wave P4 section
- [x] neural_net/PRESSURE_REGISTRY.md — NN-P09 re-routed + Wave P4 section
- [x] dataframes/PRESSURE_REGISTRY.md — DF-P10 re-routed + Wave P4 section
- [x] vector_editor/PRESSURE_REGISTRY.md — VE-P08 split + Wave P4 section
- [x] decision_tree/PRESSURE_REGISTRY.md — DT-P09 re-routed + Wave P4 section
- [x] arch_patterns/PRESSURE_REGISTRY.md — AP-P12 split + Wave P4 section
- [x] rule_engine/PRESSURE_REGISTRY.md — RE-P07 split + Wave P4 section
- [x] vector_math/PRESSURE_REGISTRY.md — VM-P09 re-routed + Wave P4 section
- [x] advanced_logistics/PRESSURE_REGISTRY.md — Wave P4 CLEAN confirmation
- [x] sim_framework/PRESSURE_REGISTRY.md — SIM-P10 through SIM-P13 added + Wave P4 section
- [x] Rollup doc written at `igniter-lab/.agents/docs/app-pressure-recheck-wave-p4-2026-06-13-v0.md`
- [x] Portfolio index updated
- [x] Governance card written (this file)

---

## Verdict

**LANG-TYPED-COMPUTE-BINDING-P2 had zero impact across all 10 apps.**

Wave P3 incorrectly attributed all "compute binding" pressures to `LANG-TYPED-COMPUTE-BINDING-P1` (annotated computes). The actual app computes are unannotated record literals or stringly call_contract returns. P2 only applies to `compute name : Type = expr` annotated bindings. No app uses this form.

Root cause re-classified into three distinct gaps:

| Gap | Root Cause | Apps Affected | New Route |
|---|---|---|---|
| A | `infer_record_literal` returns Unknown for unannotated intermediate computes | 8 apps | `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` |
| B | Stringly `call_contract("append", ...)` callee unresolved in both toolchains | VE, DT, AP | stringly stdlib migration |
| C | String/Text type name mismatch (`concat` returns "Text"; type declares "String") | sim_framework | `LANG-STRING-TEXT-ALIAS-P1` |

New pressures registered: SIM-P10, SIM-P11, SIM-P12, SIM-P13 (sim_framework first Ruby check).

advanced_logistics retains dual-toolchain CLEAN status.

---

## Next 3 Recommended Cards (Priority Order)

### 1. `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` — HIGHEST PRIORITY

Modify `infer_record_literal` in `igniter-lang/lib/igniter_lang/typechecker.rb` to infer record field types from `@type_shapes` even when no `output_type_hint` is set for the compute node. Currently returns `type_ir("Unknown")` unconditionally when `@output_type_hints[node_name]` is absent (line ~2927). Resolves or unblocks 8+ apps (DSA-P10, NN-P09, DF-P10, VE-P08 partial, AP-P12 partial, RE-P07 partial, VM-P09, SIM-P12, SIM-P13). Highest single-card leverage in the corpus.

### 2. `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1`

Define migration path from `call_contract("stdlib_fn", ...)` stringly form to direct call or typed stdlib dispatch. Resolves VE-P02/VE-P03, DT-P03, AP-P02 and unblocks cascade unresolved symbols in those apps. Should follow `LANG-RUBY-RECORD-LITERAL-INFERENCE-P1` to isolate remaining signal.

### 3. `LANG-STRING-TEXT-ALIAS-P1`

Investigate whether `String` and `Text` should be treated as aliases in the Ruby TC. `concat(...)` returns `"Text"`; `types.ig` declarations use `String`; treated as incompatible. Bounded investigation: unify under one name or add alias equivalence in `structurally_assignable?`. Resolves SIM-P10 and unblocks SIM-P11.

---

## Boundaries

- No app source edits were made.
- No compiler, typechecker, or parser implementation was performed.
- No stdlib proposal was written.
- No dynamic dispatch implementation was performed.
- Lab evidence does not create canon authority.
