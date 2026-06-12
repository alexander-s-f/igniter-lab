# Agent Card: LANG-STDLIB-COLLECTION-CONCAT-PROP-P3

**Lane:** lang / stdlib / collection / concat  
**Mode:** RUBY IMPLEMENTATION PROOF  
**Status:** CLOSED — PROVED 67/67 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lang/experiments/stdlib_collection_concat_proof/verify_stdlib_collection_concat_p3.rb`  
**Proposal doc:** `igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-CONCAT-collection-concat-v0.md`

---

## Goal

Bounded Ruby TC implementation of `stdlib.collection.concat`.  
`concat(Collection[T], Collection[T]) → Collection[T]`

---

## Key Changes

### `typechecker.rb`

1. **`when "concat"` dispatch arm** — added immediately BEFORE `when *TEXT_STDLIB_FNS.keys` in `infer_call`. Routes all `concat` calls through `infer_concat_call` for disambiguation.

2. **`infer_concat_call` private method** (~60 lines) — added after `infer_is_empty_call`, before `infer_or_else`:
   - Infers first arg → routing: `Collection/Unknown` → collection path; other concrete → `infer_text_call` delegation
   - OOF-COL1: arity ≠ 2 on collection path (early-return)
   - OOF-COL2: second arg not `Collection/Unknown` (early-return)
   - OOF-COL7 (first activation): both element types concrete and different
   - Unknown permissive on routing + both element type positions
   - Result type: `Collection[T]` from first arg's element type (falls back to second's if Unknown)

### `docs/spec/stdlib-inventory.json`

Updated `stdlib.collection.concat` entry:
- `lifecycle_status`: `orphaned` → `lab-implemented`
- `lowering_status`: `single-toolchain` → `ruby-only`
- `aliases`: `[]` → `[{kind: "source_alias", name: "concat"}]`
- `diagnostics`: `[]` → `["OOF-COL1", "OOF-COL2", "OOF-COL7"]`
- `semantic_stability`: `sketch` → `experiment-pass`
- `proof_lineage`: added P1 + P3 entries
- `stdlib_surface_digest`: recomputed → `9163d103e13cb99752ed017e30f19813e3b30edbcb69b14d420cdc7a5e10d65c`

---

## Disambiguation (Collection/Unknown → collection path)

| First arg resolved_type | Route |
|------------------------|-------|
| `Collection` | → `stdlib.collection.concat` |
| `Unknown` | → `stdlib.collection.concat` (permissive — DSA-P03 pattern) |
| `Text`, `String`, other concrete | → `infer_text_call` → `stdlib.text.concat` |

`infer_text_call` is still used for text concat — `TEXT_STDLIB_FNS` retains `concat` for this delegation.

---

## OOF Activation

| Code | First activation | Note |
|------|-----------------|------|
| OOF-COL1 | P3 | arity ≠ 2 on collection path |
| OOF-COL2 | P3 | second arg not Collection/Unknown |
| **OOF-COL7** | **P3 — FIRST ACTIVATION** | element type mismatch: Collection[T] ++ Collection[U], T ≠ U concrete |

---

## Proof Coverage (67/67 PASS)

| Section | Content | Checks |
|---------|---------|--------|
| A (source) | when concat arm; before TEXT_STDLIB_FNS; method defined; delegation; OOF guards | 7 |
| B (happy collection) | bare refs; field access; array literal args; SIR fn; resolved_type params | 8 |
| C (text regression) | concat(Text,Text) ok; SIR fn stdlib.text.concat; chained text concat | 7 |
| D (OOF-COL1) | one arg; three args; zero args; message content; collection path confirmed | 6 |
| E (OOF-COL2) | Integer/Text/Bool second arg; message content; routing confirmed | 7 |
| F (OOF-COL7) | Integer+Text; Bool+Integer; same type=none; non-early-return | 6 |
| G (Unknown permissive) | routing; both elem Unknown; one Unknown; OOF-COL2 absent | 5 |
| H (DSA fixture) | inline SetInsert equiv parse=ok; no mislabeling; no concat OOF; actual DSA source checks | 6 |
| I (inventory) | lifecycle; lowering; aliases; diagnostics; purity; digest | 8 |
| J (authority) | append regression; filter regression; text concat regression; closed surfaces | 7 |

---

## Notable

- **DSA compiler encoding note**: The actual `dsa/types.ig` contains Unicode box-drawing characters in comments (`─`). The Ruby compiler has a pre-existing JSON encoding limitation (separate from P3) that prevents live compilation of these files via Ruby. H section uses a structurally equivalent inline fixture for live compile checks; actual DSA source is verified by source-text checks (H-04, H-05).
- `TEXT_STDLIB_FNS` retains `"concat"` — it is used by `infer_text_call` via delegation. The new `when "concat"` arm intercepts dispatch BEFORE `when *TEXT_STDLIB_FNS.keys`.

---

## Closed Surfaces

- No Rust TC / emitter changes (P4)
- No flat_map / join / group_by
- No text concat rewrite beyond disambiguation delegation

---

## Next Route

**LANG-STDLIB-COLLECTION-CONCAT-PROP-P4** — Rust parity:
- Fix `rewrite_concat_calls` `quick_arg_type` for `Expr::FieldAccess` (closes DSA-P03)
- Add OOF-COL1 / OOF-COL2 / OOF-COL7 Rust TC arms
- Fix emitter `Vec::new()` → propagate `params[0]` from first arg (closes element type erasure)
- Upgrade inventory `lowering_status` → `dual-toolchain`
