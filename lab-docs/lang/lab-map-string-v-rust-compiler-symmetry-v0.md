# Lab: Map[String,V] Rust Compiler Symmetry

**Track:** `lab-map-string-v-rust-compiler-symmetry-v0`
**Card:** `LAB-MAP-RUST-P1`
**Status:** ✅ PROVED — 32/32 PASS
**Date:** 2026-06-09
**Depends on:** PROP-043-P5, LAB-RECORD-MAP-P1, LAB-RECORD-VM-P3
**Authority:** Lab-only. Lab behavior does NOT create canon authority.

---

## Goal

Implement and prove Rust lab compiler symmetry for `Map[String,V]`, matching the
production Ruby compiler surface established by PROP-043-P5:

- `Map[String,V]` annotation validation: OOF-MAP1/2/3 equivalents
- Record field parameter preservation: `headers: Map[String,String]` survives type shape path
- Map stdlib type inference: `map_get`, `map_has_key`, `map_from_pairs`, `map_empty`, `or_else`
- Record/Map bridge: `FullRackResponse.headers` → `Map[String,String]` → `map_get` → `Option[String]`

---

## Gate Result

```
MAP-A: Annotation acceptance    —  4/ 4 PASS
MAP-B: Diagnostic codes         —  6/ 6 PASS  (OOF-MAP1/2/3 + message format)
MAP-C: Stdlib type inference    —  8/ 8 PASS  (map_get/has_key/empty/or_else)
MAP-D: Record/Map bridge        —  5/ 5 PASS  (FullRackResponse.headers chain)
MAP-E: SIR resolved_type shapes —  4/ 4 PASS
MAP-F: Regression               —  5/ 5 PASS  (arith/find/or_else/no-map)

Total: 32/32 PASS

Regression suites (unchanged):
  verify_oof_r3.rb                       34/34 PASS
  verify_g5_recur.rb                     18/18 PASS
  verify_g4_body_semantics.rb            18/18 PASS
  verify_str_core.rb                     29/29 PASS
  verify_t3_numeric_measure.rb           all PASS
  verify_t2_structural_size_relation.rb  52/52 PASS
```

---

## Changes to `igniter-compiler/src/typechecker.rs`

### 1. Fixed `or_else` — proper Option[V] extraction (line ~2456)

**Before (existing behavior):**
```rust
"unwrap_or" | "or_else" => {
    is_resolved = true;
    if typed_args.len() >= 2 {
        resolved_type = typed_args[1].resolved_type.clone();  // returned default's type
    }
}
```

**After (LAB-MAP-RUST-P1):**
```rust
"unwrap_or" | "or_else" => {
    is_resolved = true;
    if typed_args.len() >= 2 {
        // LAB-MAP-RUST-P1: proper or_else — extract V from Option[V] params[0]
        let first_name = self.type_name(&typed_args[0].resolved_type);
        resolved_type = if first_name == "Option" || first_name == "Result" {
            self.get_param(&typed_args[0].resolved_type, 0)
                .unwrap_or_else(|| typed_args[1].resolved_type.clone())
        } else {
            typed_args[1].resolved_type.clone()
        };
    }
}
```

This fixes the semantic: `or_else(Option[String], "text/plain") → String` by extracting
V from `Option[V]` params[0], not from the default arg's type. The fallback to
`typed_args[1].resolved_type` preserves backward compat for non-Option first args.

### 2. Added OOF-MAP1/2/3 annotation scan in `typecheck_contract`

Added scan after `output_type_hints` pre-scan, before the main declarations loop.
Checks all declarations (input, compute, output, read) for Map annotation violations.

| Rule | Condition | Scope |
|------|-----------|-------|
| OOF-MAP1 | Non-String key (exempts Unknown) | All decls |
| OOF-MAP2 | `Any` value (permanently closed) | All decls |
| OOF-MAP3 | `Unknown` value | Output decls only |

### 3. Added Map stdlib handlers in `infer_call`

Added before the `_ => {}` wildcard arm:

| Function | Return type |
|----------|------------|
| `map_get` / `stdlib.map.get` | `Option[V]` — extracts params[1] from Map arg |
| `map_has_key` / `stdlib.map.has_key` | `Bool` |
| `map_from_pairs` / `stdlib.map.from_pairs` | `Map[String,V]` — V from Collection[Pair].params[0].params[1] |
| `map_empty` / `stdlib.map.empty` | `Map[String,Unknown]` |

### 4. Added helper methods

Three new private methods added before `infer_field_expr_type`:

- `make_map_type_ir(key, val)` — builds `{name:"Map", params:[key_ir, val_ir]}`
- `make_option_type_ir(inner)` — builds `{name:"Option", params:[inner_ir]}`
- `check_map_annotation(ann, node, kind, errors)` — OOF-MAP1/2/3 check for a single annotation

---

## Record/Map Bridge — Key Finding

With `build_type_shapes` already using `type_ir(&f.type_annotation)` (which preserves
Hash annotations as-is via the early return at line 1774), the Rust lab did NOT have
the C1 bug present in the Ruby classifier. `FullRackResponse.headers` was already
correctly typed as `Map[String,String]` in `local_type_shapes`.

The gap was purely in `infer_call`:
- Before LAB-MAP-RUST-P1: `map_get` → OOF-TY0 "Unknown function: map_get"
- After LAB-MAP-RUST-P1: `map_get(response.headers, key)` → `Option[String]`

| Step | Result |
|------|--------|
| `build_type_shapes["FullRackResponse"]["headers"]` | `Map[String,String]` (already correct — no C1 bug in Rust) |
| `response.headers` field access | `Map[String,String]` in SIR |
| `map_get(response.headers, key)` | `Option[String]` ✓ (was: OOF-TY0 "Unknown function") |
| `or_else(raw_ct, "text/plain")` | `String` ✓ (was: Unknown or default's type for non-Option) |
| `map_has_key(response.headers, key)` | `Bool` ✓ (was: OOF-TY0 "Unknown function") |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| C1 analog needed in Rust? | NO — `build_type_shapes` calls `type_ir(ann)` directly, which preserves Hash annotations unchanged (early return at line 1774). The C1 bug was Ruby-specific. |
| `map_get` produces `Option[String]` from `Map[String,String]`? | ✅ YES — MAP-C1b/MAP-D2 confirmed |
| `or_else` extracts V from `Option[V]`? | ✅ YES — MAP-C4b/MAP-D3 confirmed |
| `map_has_key` returns `Bool`? | ✅ YES — MAP-C2b/MAP-D4 confirmed |
| `map_empty` returns `Map[String,Unknown]`? | ✅ YES — MAP-C3b confirmed |
| OOF-MAP1/2/3 fire correctly? | ✅ YES — MAP-B1..B5 confirmed |
| OOF-MAP3 fires on output only (not input)? | ✅ YES — MAP-B4/B5 |
| Existing type inference regressions? | ✅ NONE — all regression suites pass |
| SIR resolved_type stored as `node["type"]`? | YES — not `node["expr"]["resolved_type"]` |

---

## Closed Surfaces (Lab Scope)

| Surface | Status |
|---------|--------|
| VM map execution | **Closed** — no runtime data structure |
| `Map[String,Any]` | **Closed** — OOF-MAP2 permanently closed |
| Non-String key types | **Closed** — OOF-MAP1 |
| Map literal syntax | **Closed** — deferred to v1 |
| v1 expansion (keys/values/merge/size/to_pairs) | **Closed** — v1 scope |
| JSON / JsonValue integration | **Closed** — not part of Map[String,V] |
| `map_from_pairs` in verify | **Note** — tested via MAP-C; no bridge fixture (Pair construction is out of scope for v0) |

---

## Gap Packet

```
proof:        lab-map-string-v-rust-compiler-symmetry / v0
status:       CLOSED / PROVED — 32/32 PASS

rust_lab_symmetry:
  map_get_option_v:        PROVED (MAP-C1; MAP-D2)
  map_has_key_bool:        PROVED (MAP-C2)
  map_empty_map_unknown:   PROVED (MAP-C3)
  or_else_option_v_to_v:   PROVED (MAP-C4; MAP-D3)
  oof_map1_non_string_key: PROVED (MAP-B1; MAP-B2)
  oof_map2_any_value:      PROVED (MAP-B3)
  oof_map3_unknown_output: PROVED (MAP-B4; MAP-B5 negative)
  record_map_bridge:       PROVED (MAP-D1..D5 — full chain Option[String] + String)
  sir_resolved_type:       PROVED (MAP-E1..E4)
  c1_not_needed_rust:      CONFIRMED (build_type_shapes uses type_ir directly)

still_open:
  vm_map_execution:        CLOSED (no bytecode; no runtime map structure)
  v1_expansion:            CLOSED (keys/values/merge/size/to_pairs)
  map_literal_syntax:      CLOSED (grammar production deferred)
  non_string_keys:         CLOSED (OOF-MAP1 guards)

no_next_authorized_route: lab proof complete; production graduation for VM map is
                          a separate gate decision
```
