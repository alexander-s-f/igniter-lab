# Agent Card: LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4

**Lane:** lang / rust-compiler / stdlib / collection  
**Mode:** BOUNDED RUST IMPLEMENTATION  
**Status:** CLOSED — PROVED 67/67 PASS  
**Date closed:** 2026-06-12  
**Lab doc:** `igniter-lab/lab-docs/lang/lab-stdlib-collection-map-filter-count-rust-parity-v0.md`  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_map_filter_count_rust_parity_p4.rb`  
**Oracle:** LANG-STDLIB-COLLECTION-MAP-FILTER-P3 (Ruby 61/61 PASS)

---

## Goal

Close Rust parity gaps for `stdlib.collection.map`, `stdlib.collection.filter`, and
`stdlib.collection.count` after Ruby P3.

---

## Gaps Closed

| Gap | Before | After |
|-----|--------|-------|
| SIR fn names | bare `map` / `filter` / `count` | `stdlib.collection.*` canonical |
| map lambda param | hardcoded `Integer` | Collection element type T |
| filter predicate validation | none | OOF-COL3 for non-Bool/non-Unknown |

---

## Implementation

### typechecker.rs — two changes

**1. map lambda param binding** — replaced `Integer` hardcode with:
```rust
let elem_ty = if first_arg_name == "Collection" {
    self.get_param(&first_arg_type, 0).unwrap_or_else(|| Unknown)
} else {
    Unknown
};
for p in params { local_symbols.insert(p.clone(), elem_ty.clone()); }
```

**2. filter arm extension** — added ~50 lines: lambda param binding to element type T +
OOF-COL3 validation (predicate body inferred with `temp_errors`; non-Bool/non-Unknown →
`type_errors.push(ClassifierDiagnostic { rule: "OOF-COL3", ... })`).

### emitter.rs — two changes

**1. `COLLECTION_HOF_OPS` in `semantic_expr`** — rewrites bare fn names to canonical
`stdlib.collection.*` names (mirrors `TEXT_STDLIB_OPS` pattern).

**2. Delegation in `semantic_expr_for_compute`** — added `|| matches!(fn_val, "map" | "filter" | "count")` to the `TEXT_STDLIB_OPS_C` delegation condition so collection HOF call
nodes reach `semantic_expr`'s rewrite logic. Without this, `semantic_expr_for_compute`
processed them key-by-key and `COLLECTION_HOF_OPS` never fired.

---

## Proof Matrix

9 sections (A regression / B count / C filter / D map / E SIR names / F type inference /
G app fixtures / H lambda binding / I authority closed) — 67 checks / 0 failures.

---

## Closed Surfaces

- No Ruby changes
- No fold / no sum
- No VM / runtime
- No app fixture edits
- No stdlib-inventory.json (deferred to P5)
- No broad Rust refactor

---

## Next Route

**LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5** — stdlib-inventory.json integration +
OOF-COL1/COL2 parity in Rust TC.
