# LAB-MAP-RUST-P1: Map[String,V] Rust Lab Compiler Symmetry

**Card:** LAB-MAP-RUST-P1
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Category:** lang
**Track:** `lab-map-string-v-rust-compiler-symmetry-v0`
**Route:** EXPERIMENTAL / LAB-ONLY
**Status:** ✅ CLOSED 2026-06-09
**Depends on:** PROP-043-P5, LAB-RECORD-MAP-P1, LAB-RECORD-VM-P3

---

## Goal

Implement and prove Rust lab compiler symmetry for `Map[String,V]`, making the Rust
lab typechecker match the production Ruby compiler surface established by PROP-043-P5.

---

## Gate Result

```
MAP-A: Annotation acceptance    —  4/ 4 PASS
MAP-B: Diagnostic codes         —  6/ 6 PASS
MAP-C: Stdlib type inference    —  8/ 8 PASS
MAP-D: Record/Map bridge        —  5/ 5 PASS
MAP-E: SIR resolved_type shapes —  4/ 4 PASS
MAP-F: Regression               —  5/ 5 PASS

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

## Deliverables

| File | Change |
|------|--------|
| `igniter-compiler/src/typechecker.rs` | Fix `or_else` (proper Option[V] extraction); OOF-MAP1/2/3 scan; `map_get/has_key/from_pairs/empty` handlers; `make_map_type_ir`, `make_option_type_ir`, `check_map_annotation` helpers |
| `igniter-compiler/verify_lab_map_rust_p1.rb` | Proof runner — 32/32 PASS |
| `igniter-lab/lab-docs/lang/lab-map-string-v-rust-compiler-symmetry-v0.md` | Lab doc |
| `igniter-lab/.agents/work/cards/lang/LAB-MAP-RUST-P1.md` | This card |
| `igniter-lab/.agents/portfolio-index.md` | Portfolio index update |

**Not touched:** `classifier.rs` (C1 analog not needed — Rust already correct),
`emitter.rs` (already preserves Map params), VM/runtime files.

---

## Changes Summary

### `typechecker.rs`

**`or_else` fix:** The existing handler returned `typed_args[1].resolved_type` (the
default value's type). Fixed to extract V from `Option[V]` params[0]:
- `or_else(Option[String], "text/plain") → String` (via params[0], not default's type)
- Fallback: for non-Option first arg, returns default's type (backward compat)
- Symmetric with Ruby production `infer_or_else`

**OOF-MAP annotation scan:** Added after `output_type_hints` pre-scan in
`typecheck_contract`. Checks all declarations using `check_map_annotation` helper.

**Map stdlib handlers** (before `_ => {}` wildcard):
- `map_get` / `stdlib.map.get` → `Option[V]` (V = params[1] from Map)
- `map_has_key` / `stdlib.map.has_key` → `Bool`
- `map_from_pairs` / `stdlib.map.from_pairs` → `Map[String,V]` (V from Pair params[1])
- `map_empty` / `stdlib.map.empty` → `Map[String,Unknown]`

**Helper methods** (before `infer_field_expr_type`):
- `make_map_type_ir(key, val)` — builds Map type IR
- `make_option_type_ir(inner)` — builds Option type IR
- `check_map_annotation(ann, node, kind, errors)` — OOF-MAP1/2/3

### C1 Not Needed in Rust

The Ruby C1 bug existed because `normalize_type` stripped Hash annotations to strings.
Rust's `build_type_shapes` calls `self.type_ir(&f.type_annotation)` directly, which
has an early-return for objects with a `"name"` key — preserving Map params correctly.
`FullRackResponse.headers` was already `Map[String,String]` in Rust `local_type_shapes`
before LAB-MAP-RUST-P1. The gap was only in `infer_call` (no handlers for map stdlib).

---

## Record/Map Bridge Finding

| Step | Before P1 | After P1 |
|------|-----------|----------|
| `build_type_shapes["FullRackResponse"]["headers"]` | `Map[String,String]` (already correct) | `Map[String,String]` |
| `response.headers` field access | `Map[String,String]` (already in SIR) | `Map[String,String]` |
| `map_get(response.headers, key)` | OOF-TY0 "Unknown function: map_get" | `Option[String]` ✓ |
| `or_else(Option[String], default)` | Returned default's type | `String` ✓ |
| `map_has_key(response.headers, key)` | OOF-TY0 "Unknown function" | `Bool` ✓ |

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| C1 analog needed in Rust classifier? | ❌ NO — Rust `build_type_shapes` already correct |
| `map_get(Map[String,String], key)` → `Option[String]`? | ✅ YES — MAP-C1b/MAP-D2 |
| `or_else(Option[String], default)` → `String`? | ✅ YES — MAP-C4b/MAP-D3 |
| `map_has_key` → `Bool`? | ✅ YES — MAP-C2b/MAP-D4 |
| `map_empty` → `Map[String,Unknown]`? | ✅ YES — MAP-C3b |
| OOF-MAP1/2/3 parity with production? | ✅ YES — MAP-B1..B5 |
| OOF-MAP3 fires on output only? | ✅ YES — MAP-B4/B5 negative |
| All regressions clean? | ✅ YES |
| VM/runtime map execution? | ❌ NO — out of scope |
| Rust SIR `resolved_type` field? | `node["type"]` (not `node["expr"]["resolved_type"]`) |

---

## Boundary

Lab-only. No production Ruby changes. No VM/runtime authority. Lab behavior does NOT
create canon authority. Proof demonstrates Rust lab typechecker symmetry with the
production compiler surface for `Map[String,V]` type inference.

---

## Gap Packet

```
proof:        lab-map-string-v-rust-compiler-symmetry / v0
status:       CLOSED / PROVED — 32/32 PASS
authority:    lab_only
date:         2026-06-09

rust_symmetry:
  map_get:    PROVED (Option[V] from Map[String,V] params[1])
  map_has_key: PROVED (Bool)
  map_empty:  PROVED (Map[String,Unknown])
  or_else:    PROVED (V from Option[V] params[0])
  oof_map1:   PROVED (OOF-MAP1 fires on non-String key)
  oof_map2:   PROVED (OOF-MAP2 fires on Any value)
  oof_map3:   PROVED (OOF-MAP3 fires on Unknown output; not on input)
  bridge:     PROVED (FullRackResponse.headers → map_get → Option[String] → or_else → String)

c1_finding: No C1 analog needed — Rust build_type_shapes already preserves Map params.
            Gap was exclusively in infer_call (no map stdlib handlers).

next_authorized_route: none (lab proof complete; VM map is a separate gate decision)
```
