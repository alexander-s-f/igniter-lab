# Agent Card: LANG-STDLIB-COLLECTION-APPEND-PROP-P4

**Lane:** lang / stdlib / collection / append  
**Mode:** BOUNDED RUST PARITY — proof  
**Status:** CLOSED — PROVED 66/66 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_append_rust_parity_p4.rb`  
**Lab doc:** `igniter-lab/lab-docs/lang/lab-stdlib-collection-append-rust-parity-p4-v0.md`

---

## Goal

Implement Rust TC parity for `stdlib.collection.append` — matching Ruby P3 behavior across
OOF-COL1/COL2/COL6, Unknown permissive rule, happy path, and SIR qualification
(`"stdlib.collection.append"` in emitted SIR).

---

## Changes

### `igniter-lab/igniter-compiler/src/typechecker.rs`

`"append"` arm added after `"fold"`, before `"avg" | "min" | "max"`:
- OOF-COL1: arity ≠ 2 → Unknown result
- OOF-COL2: first arg not Collection/Unknown → Unknown result
- Element type via `get_param(&typed_args[0].resolved_type, 0)`
- OOF-COL6: both concrete, different names → non-early-return diagnostic
- Return type: `Collection[elem_type]`

### `igniter-lab/igniter-compiler/src/emitter.rs`

- `("append", "stdlib.collection.append")` added to `COLLECTION_HOF_OPS` (4 entries total)
- `"append"` added to `TEXT_STDLIB_OPS_C` delegation guard (`matches!(fn_val, "map" | "filter" | "count" | "append")`)

### `igniter-lang/docs/spec/stdlib-inventory.json`

- `lowering_status`: `ruby-only` → `dual-toolchain`
- P4 proof_lineage entry added
- `stdlib_surface_digest`: `a94ef6fea90bd8d14f210df323bc4250086c52f9ffe62909f2323702a2521c44`

---

## Proof Matrix

| Section | Checks |
|---------|--------|
| A (Rust source structure) | 8 |
| B (OOF-COL1) | 6 |
| C (OOF-COL2) | 6 |
| D (OOF-COL6) | 6 |
| E (Unknown permissive) | 5 |
| F (happy path + SIR) | 8 |
| G (Ruby P3 parity) | 6 |
| H (inventory) | 7 |
| I (authority closed) | 6 |
| J (regression) | 8 |
| **Total** | **66 / 66 PASS** |

---

## Closed Surfaces

- No parser / classifier / assembler changes
- No VM / runtime / capability authority
- No new OOF-IMP codes
- No app fixture edits
- No map / filter / count / fold / sum regressions

---

## Previous

**LANG-STDLIB-COLLECTION-APPEND-PROP-P3** — Ruby TC implementation, 65/65 PASS

## Next Route

**LANG-STDLIB-IMPORT-SURFACE-P3** or **LANG-STDLIB-COLLECTION-APPEND-PROP-P5** (VM lowering)
