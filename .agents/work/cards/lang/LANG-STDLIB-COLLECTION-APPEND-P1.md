# Agent Card: LANG-STDLIB-COLLECTION-APPEND-P1

**Lane:** lang / stdlib / collection / append  
**Mode:** PROPOSAL AUTHORING ONLY / NO IMPLEMENTATION  
**Status:** CLOSED — AUTHORED  
**Date:** 2026-06-12  
**Proposal doc:** `igniter-lang/.agents/work/proposals/LANG-STDLIB-COLLECTION-APPEND-collection-append-v0.md`

---

## Goal

Define `stdlib.collection.append` governance: canonical name, type signature, OOF codes,
entry contract, and implementation route — answering all P1 questions before P2.

---

## Questions Answered

| Question | Answer |
|----------|--------|
| Source alias | `append` (bare) — `append(collection, item)` direct call |
| Canonical name | `stdlib.collection.append` |
| Type | `Collection[T] × T → Collection[T]` |
| Item type equality strict? | Yes — concrete mismatch → OOF-COL6; Unknown permissive |
| Order preserved? | Yes — item at end; semantic guarantee |
| Pure/deterministic? | Yes — both |
| Runtime allocation authority? | No — pure value construction |
| OOF code | COL1 (arity), COL2 (non-Collection), COL6 new (item mismatch) |
| SIR lowering name | `stdlib.collection.append` |
| Import surface | `import stdlib.collection.{ append }` — already used in app fixtures |

---

## Key Findings

**Evidence breadth:** 6+ distinct app fixtures across vector_editor, decision_tree,
igniter_parser, bloom_filter, arch_patterns — all use `call_contract("append", ...)`.

**Bootstrap pattern:** Some fixtures call `append(item_a, item_b)` — both non-Collection —
to create an initial collection. This is outside the canonical `Collection[T] × T → Collection[T]`
type. It continues via `call_contract` until `stdlib.collection.empty` is available.

**concat distinction:** `stdlib.collection.concat` (orphaned, `Collection[T] × Collection[T]`)
is a distinct operation. `append` is not a concat alias.

**OOF-COL6 (new):** Item type mismatch when collection element type and item type are both
concrete and different. Unknown is always permissive.

**No Rust dispatch yet:** `append` has no arm in the Rust TC match block.
Rust parity is P3+ scope after Ruby TC proof.

---

## Entry Contract (summary)

- `lifecycle_status`: proof-local (no implementation yet)
- `lowering_status`: none (no toolchain dispatch)
- `semantic_stability`: experiment-pass (evidence-grounded)
- `fragment_class`: core
- `purity`: pure
- `authority_surface`: none
- `diagnostics`: ["OOF-COL1", "OOF-COL2", "OOF-COL6"]

---

## Closed Surfaces

- No Ruby TC implementation
- No Rust TC changes
- No inventory edits
- No app fixture changes
- No `stdlib.collection.empty` / collection literals
- No `concat` changes

---

## Next Route

**LANG-STDLIB-COLLECTION-APPEND-PROP-P2** — bounded Ruby TC implementation planning.  
`when "append"` arm + `infer_append_call` (~40 lines). Proof runner ≥50 checks.
