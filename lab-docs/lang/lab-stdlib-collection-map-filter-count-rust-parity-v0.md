# LAB: stdlib.collection.{map,filter,count} Rust Parity — v0

**Track:** lang / rust-compiler / stdlib / collection  
**Route:** BOUNDED RUST IMPLEMENTATION / PROOF  
**Card:** LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4  
**Date:** 2026-06-12  
**Status:** CLOSED / PROVED — 67/67 PASS  
**Oracle:** LANG-STDLIB-COLLECTION-MAP-FILTER-P3 (Ruby 61/61 PASS)

---

## 1. Scope

P4 closes Rust parity gaps for `stdlib.collection.map`, `stdlib.collection.filter`, and
`stdlib.collection.count` after Ruby P3 proved the canon behavior at 61/61 PASS.

Three gaps were closed in P4:

| Gap | Before P4 | After P4 |
|-----|-----------|----------|
| SIR fn names | bare `map` / `filter` / `count` | `stdlib.collection.map` / `.filter` / `.count` |
| map lambda param binding | hardcoded `Integer` | `Collection[T]` element type via `get_param` |
| filter predicate validation | none (predicate type ignored) | OOF-COL3 for non-Bool/non-Unknown predicates |

Closed surfaces (unchanged in P4):

- No Ruby changes
- No fold / no sum dispatch
- No VM / runtime changes
- No app fixture edits
- No stdlib-inventory.json edits (deferred to P5)
- No lambda system expansion beyond collection HOF param binding

---

## 2. Changes

### 2.1 `igniter-compiler/src/typechecker.rs`

**Change 1 — map lambda param binding** (inside `"map"` arm):

Before P4, lambda params were bound to hardcoded `Integer`:
```rust
for p in params {
    local_symbols.insert(p.clone(), self.type_ir(&serde_json::Value::String("Integer".to_string())));
}
```

After P4, params are bound to `get_param(&first_arg_type, 0)` (the element type T from
`Collection[T]`), falling back to `Unknown`:
```rust
let elem_ty = if first_arg_name == "Collection" {
    self.get_param(&first_arg_type, 0)
        .unwrap_or_else(|| self.type_ir(&serde_json::Value::String("Unknown".to_string())))
} else {
    self.type_ir(&serde_json::Value::String("Unknown".to_string()))
};
for p in params {
    local_symbols.insert(p.clone(), elem_ty.clone());
}
```

Result: `map(items, x -> x.value)` on `Collection[Item]` where `Item.value: Integer`
now returns `Collection[Integer]` (was `Collection[Unknown]`).

**Change 2 — filter lambda binding + OOF-COL3** (inside `"filter" | "take"` arm):

Extended with ~50 lines adding:
- Lambda param binding to element type T (same `get_param` pattern as map)
- Lambda body inference via `infer_expr` (Expr/Block forms) using `temp_errors`
- OOF-COL3: if predicate body type is non-Bool and non-Unknown, push to outer `type_errors`

OOF-COL3 message form: `"stdlib.collection.filter: predicate must return Bool, got <type>"`

### 2.2 `igniter-compiler/src/emitter.rs`

**Change 1 — `COLLECTION_HOF_OPS` in `semantic_expr`:**

Added after the `TEXT_STDLIB_OPS` qualification block. When the call node `fn` field matches
a bare HOF name (`map` / `filter` / `count`), rewrites it to the canonical qualified name:

```rust
const COLLECTION_HOF_OPS: &[(&str, &str)] = &[
    ("map",    "stdlib.collection.map"),
    ("filter", "stdlib.collection.filter"),
    ("count",  "stdlib.collection.count"),
];
if let Some((_, qualified)) = COLLECTION_HOF_OPS.iter().find(|(bare, _)| *bare == fn_val) {
    // rewrite fn field; preserve all other fields
}
```

**Change 2 — delegation in `semantic_expr_for_compute`:**

The compute path enters `semantic_expr_for_compute` (not `semantic_expr`), which previously
only delegated to `semantic_expr` for `TEXT_STDLIB_OPS_C` and `stdlib.text.*`/concat. Added
`|| matches!(fn_val, "map" | "filter" | "count")` so these nodes reach `semantic_expr`'s
rewrite logic:

```rust
if TEXT_STDLIB_OPS_C.contains(&fn_val)
    || fn_val.starts_with("stdlib.text.")
    || fn_val == "stdlib.collection.concat"
    || matches!(fn_val, "map" | "filter" | "count")
{
    return self.semantic_expr(val);
}
```

This was the key architectural discovery: without this delegation, `semantic_expr_for_compute`
processed call nodes key-by-key in a generic fallthrough loop — `semantic_expr` was never
called with the whole call node, so `COLLECTION_HOF_OPS` rewrites never fired.

---

## 3. Verification Results

Manual fixtures confirmed before proof run:

| Fixture | Before P4 | After P4 |
|---------|-----------|----------|
| `map(items, x -> x.value)` on `Collection[Item]` | `Collection[Unknown]` | `Collection[Integer]` ✓ |
| `map` SIR fn name | `map` (bare) | `stdlib.collection.map` ✓ |
| `filter(items, x -> x.active)` SIR fn | `filter` (bare) | `stdlib.collection.filter` ✓ |
| `filter(items, x -> x.value)` (Integer pred) | `status: ok` (silent) | `status: oof`, OOF-COL3 ✓ |
| `count(items)` SIR fn | `count` (bare) | `stdlib.collection.count` ✓ |

---

## 4. Proof Matrix (67 checks, 9 sections)

| Section | Checks | Focus |
|---------|--------|-------|
| A — Regression | 7 | Source presence; byte_length still qualified |
| B — count dispatch | 8 | Canonical fn; Integer type; arity; T3 coexistence |
| C — filter dispatch | 9 | Canonical fn; passthrough type; OOF-COL3 |
| D — map dispatch | 9 | Canonical fn; result type wrapping; no OOF-COL3 |
| E — SIR qualified names | 7 | All three qualified; none bare; chain fixture |
| F — Type inference | 8 | Result types; Unknown permissive; chain consistency |
| G — App fixture parity | 6 | bookkeeping/ERP: no Unknown function; fold unaffected |
| H — Lambda element binding | 6 | Field access works; Decimal[2]; get_param used |
| I — Authority closed | 7 | fold bare; sum untouched; inventory unchanged; no VM |

---

## 5. Pre-existing Gaps (Not P4 Scope)

**`==` operator returns Unknown:** Filter predicates using `==` (e.g., `x.label == "active"`)
do not trigger OOF-COL3 because `==` returns `Unknown` in the Rust TC and Unknown passes
OOF-COL3 permissively. The same gap exists in the Ruby TC. The `==` operator is a separate
track.

**OOF-COL1 / OOF-COL2 for Rust:** Ruby P3 added arity (OOF-COL1) and non-Collection
(OOF-COL2) checks. The Rust TC does not emit these yet. P4 proof checks that no crash
occurs and no "Unknown function" error appears — the arity/collection-type validation is
deferred to a future card.

---

## 6. Proof Runner

```
igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_map_filter_count_rust_parity_p4.rb
```

67 checks, 9 sections A–I.

---

## 7. Files Changed in P4

| File | Change |
|------|--------|
| `igniter-compiler/src/typechecker.rs` | ~55 new lines: map elem_ty binding; filter lambda binding + OOF-COL3 |
| `igniter-compiler/src/emitter.rs` | ~20 new lines: COLLECTION_HOF_OPS in semantic_expr; delegation in semantic_expr_for_compute |
| `igniter-view-engine/proofs/verify_lab_stdlib_collection_map_filter_count_rust_parity_p4.rb` | New proof runner (67 checks) |

---

## 8. Next Route

**LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P5** — stdlib-inventory.json integration +
OOF-COL1/COL2 parity in Rust TC (arity/non-Collection validation).
