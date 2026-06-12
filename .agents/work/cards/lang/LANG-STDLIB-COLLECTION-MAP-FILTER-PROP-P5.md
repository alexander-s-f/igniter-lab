# Agent Card: LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5

**Lane:** lang / stdlib / collection / inventory  
**Mode:** BOUNDED IMPLEMENTATION — inventory + OOF parity  
**Status:** CLOSED — PROVED 86/86 PASS  
**Date closed:** 2026-06-12  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_map_filter_count_inventory_p5.rb`

---

## Goal

Finish map/filter/count stabilization after Ruby P3 + Rust P4:
- Integrate map/filter/count with stdlib-inventory.json
- Add OOF-COL1/COL2 parity to Rust TC (arity + non-Collection checks)
- Prove bidirectional consistency (dispatch keys ↔ inventory aliases)

---

## Changes

### stdlib-inventory.json (26 entries, was 24)

**Added** `stdlib.collection.map`:
- `lifecycle_status`: lab-implemented, `lowering_status`: dual-toolchain
- `type_params`: ["T","U"], `output_signature`: "Collection[U]"
- `diagnostics`: ["OOF-COL1","OOF-COL2"]
- `aliases`: [{"kind":"source_alias","name":"map"}]

**Added** `stdlib.collection.filter`:
- `lifecycle_status`: lab-implemented, `lowering_status`: dual-toolchain
- `type_params`: ["T"], `output_signature`: "Collection[T]"
- `diagnostics`: ["OOF-COL1","OOF-COL2","OOF-COL3"]
- `aliases`: [{"kind":"source_alias","name":"filter"}]

**Updated** `stdlib.collection.count`:
- `proof_lineage`: extended with P3 + P4 entries
- `compatibility_note`: clarifies T3 path independence

**Recomputed** `stdlib_surface_digest`: `34671fb37f3ba302e906148aa433c313da1968a0cd9d019f8f4a5b4ac92136c4`

### typechecker.rs — OOF-COL1/COL2 for count/filter/map

`count` arm: `args.len() != 1` → OOF-COL1; non-Collection/non-Unknown first arg → OOF-COL2  
`filter | take` arm: guarded by `fn_name.as_str() == "filter"`: same OOF-COL1/COL2 pattern  
`map` arm: `args.len() != 2` → OOF-COL1; non-Collection/non-Unknown first arg → OOF-COL2

---

## Proof Matrix

10 sections (A schema / B digest / C map entry / D filter entry / E count update /
F bidirectional / G OOF-COL1 / H OOF-COL2 / I P4 regression / J authority) — 86 checks / 0 failures.

---

## Closed Surfaces

- No Ruby changes (Ruby TC already has OOF-COL1/COL2 via infer_collection_hof_call)
- No fold / no sum
- No VM / runtime
- No app fixture edits
- No new stdlib import authority

---

## Next Route

P5 closes map/filter/count stabilization. If further work is needed, possible routes:
- OOF-COL1 non-lambda second arg (map/filter) in Rust TC
- stdlib-inventory promotion from lab-implemented to production-implemented
