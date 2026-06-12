# Agent Card: LANG-STDLIB-COLLECTION-APPEND-PROP-P3

**Lane:** lang / stdlib / collection / append  
**Mode:** BOUNDED RUBY IMPLEMENTATION — proof  
**Status:** CLOSED — PROVED 65/65 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/stdlib_collection_append_proof/verify_stdlib_collection_append_p3.rb`  
**Lab doc:** `igniter-lab/lab-docs/lang/lab-stdlib-collection-append-ruby-p3-v0.md`

---

## Goal

Implement `stdlib.collection.append` in the Ruby TypeChecker and prove correctness with
≥60 checks covering all three OOF codes, Unknown permissive rule, happy path, bootstrap
safety, and regressions.

---

## Changes

### `typechecker.rb` — 2 insertions, ~40 new lines

**Dispatch arm** added after `when "fold"`, before `when "or_else"`:
```ruby
when "append"
  # LANG-STDLIB-COLLECTION-APPEND-PROP-P3: stdlib.collection.append
  infer_append_call(fn, args, symbol_types, type_errors, type_warnings, node_name)
```

**Method `infer_append_call`** after `infer_fold_call`:
- OOF-COL1: arity ≠ 2 → early-return Unknown
- OOF-COL2: first arg not Collection/Unknown → early-return
- OOF-COL6: both concrete, different type names → non-early-return (first activation)
- Unknown permissive: either side Unknown → no COL6
- SIR fn: `"stdlib.collection.append"` (qualified inline, zero emitter changes)
- Return type: `collection_type_ir_from(elem_type)` — preserves input element type

### `stdlib-inventory.json` — 1 new entry + digest update

- `lifecycle_status`: `lab-implemented`
- `lowering_status`: `ruby-only`
- `type_params`: `["T"]`
- `input_signature`: `["Collection[T]", "T"]`
- `output_signature`: `"Collection[T]"`
- `diagnostics`: `["OOF-COL1", "OOF-COL2", "OOF-COL6"]`
- Entry count: 26 → 27
- `stdlib_surface_digest`: `f0e592fc5c6781dff24cf5a590b7938f21b80bdb0dc5c6aceb1b907cc5391a75`

---

## OOF-COL6 First Activation

`append(Collection[String], Integer)` → `OOF-COL6: item type Integer does not match collection element type String`. Previously reserved in P1; activated here for the first time.

---

## Proof Matrix

| Section | Checks |
|---------|--------|
| A (source structure) | 8 |
| B (OOF-COL1) | 6 |
| C (OOF-COL2) | 6 |
| D (OOF-COL6) | 6 |
| E (Unknown permissive) | 5 |
| F (happy path) | 8 |
| G (bootstrap safety) | 4 |
| H (inventory) | 8 |
| I (authority closed) | 6 |
| J (regression) | 8 |
| **Total** | **65 / 65 PASS** |

---

## Closed Surfaces

- No emitter changes (Ruby or Rust)
- No Rust TC changes (P4 scope)
- No parser / classifier / assembler changes
- No VM / runtime / capability authority
- No app fixture edits
- No concat / fold / sum / map / filter changes
- No `stdlib.collection.empty`

---

## Next Route

**LANG-STDLIB-COLLECTION-APPEND-PROP-P4** — Rust TC parity:
- `"append"` arm in `typechecker.rs` (OOF-COL1/COL2/COL6)
- `("append", "stdlib.collection.append")` in `COLLECTION_HOF_OPS` in `emitter.rs`
- `|| matches!(fn_val, "map" | "filter" | "count" | "append")` in `semantic_expr_for_compute`
- Inventory `lowering_status` upgrade to `dual-toolchain` + digest recompute
