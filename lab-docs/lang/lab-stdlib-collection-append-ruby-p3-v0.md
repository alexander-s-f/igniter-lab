# Lab Doc: stdlib.collection.append Ruby Implementation
## LANG-STDLIB-COLLECTION-APPEND-PROP-P3

**Lane:** lang / stdlib / collection / append  
**Track:** Ruby TC implementation proof  
**Status:** CLOSED — PROVED 65/65 PASS  
**Date:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/stdlib_collection_append_proof/verify_stdlib_collection_append_p3.rb`  
**Card:** `igniter-lab/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-APPEND-PROP-P3.md`

---

## Summary

P3 implements `stdlib.collection.append` in the Ruby TypeChecker — the canonical
`append(Collection[T], T) → Collection[T]` function. Two insertions in `typechecker.rb`,
one new inventory entry in `stdlib-inventory.json`, and a 65-check proof runner reaching
65/65 PASS.

This is the first activation of OOF-COL6 (item type concrete mismatch).

---

## Changes

### `igniter-lang/lib/igniter_lang/typechecker.rb`

**Insertion 1** — dispatch arm after `when "fold"`, before `when "or_else"` (~line 900):

```ruby
when "append"
  # LANG-STDLIB-COLLECTION-APPEND-PROP-P3: stdlib.collection.append
  infer_append_call(fn, args, symbol_types, type_errors, type_warnings, node_name)
```

**Insertion 2** — `def infer_append_call` (~38 lines) placed after `infer_fold_call`,
before `# Rule OR-ELSE`:

- OOF-COL1: `args.length != 2` → early-return with Unknown result
- OOF-COL2: first arg not Collection and not Unknown → early-return
- Item inference via `infer_expr(args[1], ...)`
- Element type extraction via existing `element_type_from_collection`
- OOF-COL6: both concrete and different → non-early-return (error recorded, inference continues)
- Return type: `collection_type_ir_from(elem_type)` — preserves input element type
- SIR fn: `"stdlib.collection.append"` (qualified directly, zero emitter changes)

### `igniter-lang/docs/spec/stdlib-inventory.json`

New entry added:

| Field | Value |
|-------|-------|
| `canonical_name` | `stdlib.collection.append` |
| `lifecycle_status` | `lab-implemented` |
| `lowering_status` | `ruby-only` |
| `type_params` | `["T"]` |
| `input_signature` | `["Collection[T]", "T"]` |
| `output_signature` | `"Collection[T]"` |
| `diagnostics` | `["OOF-COL1", "OOF-COL2", "OOF-COL6"]` |
| `purity` | `pure` |
| `fragment_class` | `core` |
| `authority_surface` | `none` |

Entry count: 26 → 27  
New `stdlib_surface_digest`: `f0e592fc5c6781dff24cf5a590b7938f21b80bdb0dc5c6aceb1b907cc5391a75`

---

## OOF-COL6 — First Activation

OOF-COL6 was reserved in LANG-STDLIB-COLLECTION-APPEND-P1 (proposal). P3 is the first
proof that activates it.

Trigger: `append(Collection[String], Integer)` → `OOF-COL6: item type Integer does not
match collection element type String`.

Rule: fires only when both element type and item type are concrete (non-Unknown) and differ
by `type_name`. Unknown on either side is permissive (no error). Non-early-return: the error
is recorded but the method still returns `collection_type_ir_from(elem_type)` rather than
Unknown, preserving the collection type for downstream inference.

---

## Bootstrap Safety

`call_contract("append", item_a, item_b)` is NOT intercepted by the new `when "append"` arm.
The parser produces a `call` AST node with `fn == "call_contract"` (not `"append"`), so
`infer_call` routes it to the `else` branch (OOF-TY0 unknown function). No COL codes are
emitted from the bootstrap form. G section (4 checks) verifies this.

---

## Proof Matrix

| Section | Content | Checks |
|---------|---------|--------|
| A (source structure) | arm/method/OOF codes/comment/HOF table invariant | 8 |
| B (OOF-COL1) | 0 args / 1 arg / 3 args | 6 |
| C (OOF-COL2) | String/Integer/custom type first arg | 6 |
| D (OOF-COL6) | Collection[String]+Integer / Collection[Integer]+String | 6 |
| E (Unknown permissive) | Unknown collection / Unknown item / matching types | 5 |
| F (happy path) | String/Integer/custom; SIR fn name; bare name absent; status ok | 8 |
| G (bootstrap safety) | call_contract form: no COL codes (4 checks) | 4 |
| H (inventory) | entry exists / fields / digest stable | 8 |
| I (authority closed) | no emitter / no Rust / authority_surface / purity / HOF table | 6 |
| J (regression) | map/filter/count/fold/sum all pass | 8 |
| **Total** | | **65 / 65 PASS** |

---

## Closed Surfaces

- No emitter changes (Ruby or Rust)
- No Rust TC changes (P4 scope)
- No parser / classifier / assembler changes
- No VM / runtime / capability authority
- No `stdlib.collection.empty` / concat / fold / sum changes
- No app fixture edits

---

## Next Routes

- **LANG-STDLIB-COLLECTION-APPEND-PROP-P4** — Rust TC parity: `"append"` arm in
  `typechecker.rs` + `COLLECTION_HOF_OPS` entry in `emitter.rs` + `TEXT_STDLIB_OPS_C`
  delegation guard + inventory `lowering_status` upgrade to `dual-toolchain`
- **LANG-STDLIB-IMPORT-SURFACE-P3** — Once live, `import stdlib.collection.{ append }`
  resolves without OOF-IMP3 (append is now in inventory at `lab-implemented`)
