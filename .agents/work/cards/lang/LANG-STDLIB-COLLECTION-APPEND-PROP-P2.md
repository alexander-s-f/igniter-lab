# Agent Card: LANG-STDLIB-COLLECTION-APPEND-PROP-P2

**Lane:** lang / stdlib / collection / append  
**Mode:** IMPLEMENTATION PLANNING ONLY / NO CODE CHANGES  
**Status:** CLOSED — READY FOR P3  
**Date:** 2026-06-12  
**Planning doc:** `igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-APPEND-PROP-P2-implementation-planning-v0.md`

---

## Goal

Plan the Ruby TC implementation for `stdlib.collection.append` so P3 can be executed without
ambiguity: exact insertion points, OOF trigger conditions, return type construction,
inventory entry shape, and proof matrix.

---

## Decisions Made

| Question | Decision |
|----------|----------|
| Insertion point | After `when "fold"` / before `when "or_else"` (~line 897); method after `infer_fold_call` (~line 2524) |
| Dispatch structure | Separate `when "append"` arm + `def infer_append_call` — NOT in `COLLECTION_HOF_FNS` (no lambda; sum/fold precedent) |
| Element type extraction | `element_type_from_collection(collection_arg.fetch("resolved_type"))` — existing helper, zero new infrastructure |
| Return type | `collection_type_ir_from(elem_type)` — preserves input element type; `Collection[Unknown]` when collection Unknown |
| OOF-COL1 trigger | `args.length != 2` → early-return with Unknown result |
| OOF-COL2 trigger | first arg type_name not "Collection" and not "Unknown" → early-return |
| OOF-COL6 trigger | both `elem_name` and `item_name` concrete AND `elem_name != item_name` → non-early-return |
| Unknown permissive | Either side Unknown → skip OOF-COL6; no false OOF-COL2 on Unknown collection |
| SIR fn name | `"stdlib.collection.append"` — qualified in typed_expr, bare "append" never in SIR |
| Bootstrap form | `call_contract("append", item_a, item_b)` bypasses infer_call entirely — unaffected |
| Inventory timing | P3 deliverable: lifecycle=lab-implemented, lowering=ruby-only; activates importability |
| Proof matrix | 65 checks / 10 sections (A source / B COL1 / C COL2 / D COL6 / E Unknown / F happy / G bootstrap / H inventory / I authority / J regression) |

---

## Authorized Files for P3

1. `igniter-lang/lib/igniter_lang/typechecker.rb` — ~38 lines
2. `igniter-lang/docs/spec/stdlib-inventory.json` — 1 entry + digest recompute
3. `igniter-lang/experiments/stdlib_collection_append_proof/verify_stdlib_collection_append_p3.rb` — proof runner

---

## Closed Surfaces

- No emitter changes (Ruby or Rust)
- No Rust TC changes (P4 scope)
- No parser / classifier / assembler changes
- No VM / runtime / capability authority
- No `stdlib.collection.empty` / concat / fold / sum changes
- No app fixture edits

---

## Next Route

**LANG-STDLIB-COLLECTION-APPEND-PROP-P3** — bounded Ruby implementation + proof runner ≥65 checks.
