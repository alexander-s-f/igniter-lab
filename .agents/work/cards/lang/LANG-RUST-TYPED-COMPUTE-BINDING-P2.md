# LANG-RUST-TYPED-COMPUTE-BINDING-P2

**Status:** CLOSED  
**Date closed:** 2026-06-13  
**Lane:** lang / rust-typechecker / parity  
**Scope:** Implementation (one file: `igniter-lab/igniter-compiler/src/typechecker.rs`)  
**Proof:** 45/45 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p2.rb`  
**P1 Proof (updated):** 46/46 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p1.rb`  
**Lab doc:** `igniter-lab/lab-docs/lang/lab-rust-typed-compute-binding-p2-proof-v0.md`  
**Predecessor:** `LANG-RUST-TYPED-COMPUTE-BINDING-P1` (CLOSED — research + gap proof)

---

## What Was Implemented

Two additions to `igniter-lab/igniter-compiler/src/typechecker.rs`:

**1. `fn unknown_or_unknown_bearing` helper** (after `fn type_display`, ~line 2057):
- Returns `true` if a type IR is scalar `Unknown` OR any param at any depth is Unknown-bearing
- Mirrors Ruby `unknown_or_unknown_bearing?` exactly

**2. Annotation override block in the compute arm** (before `symbol_types.insert`, ~line 1187):
- Three-way branch:
  - (a) Unknown-bearing inferred → annotation authoritative, no error
  - (b) Concrete match (`structurally_assignable`) → keep inferred type
  - (c) Concrete mismatch → emit `OOF-TY0`, use annotation to prevent cascade
- Only fires when `decl.type_annotation` is `Some(ann)` — no annotation → no change

**Build:** `cargo build --release` succeeded (warnings only).

---

## Gap Closed

Before P2, `compute c0 : Collection[T] = [...]` where `[...]` infers `Unknown` → `symbol_types["c0"] = Unknown` → `append(c0, elem)` → `Collection[Unknown]` → OOF-TY1 at output boundary.

After P2: annotation override sets `symbol_types["c0"] = Collection[T]` → downstream `append(Collection[T], Unknown)` → `Collection[T]` (OOF-COL6 guard skips item=Unknown) → output passes → `ok/0`.

---

## Key Behavioral Changes

| Scenario | Before | After |
|---|---|---|
| Annotated `[]` intermediate + downstream append | oof/1 OOF-TY1 | **ok/0** |
| Multi-hop annotated chain | oof/1 OOF-TY1 | **ok/0** |
| `compute c : Collection[Unknown]` annotated | oof/1 OOF-TY1 | **ok/0** |
| Concrete mismatch (`compute n : String = 42`) | oof/1 OOF-TY1 | **oof/1 OOF-TY0** (binding-time) |
| Unannotated compute | oof/1 OOF-TY1 | oof/1 OOF-TY1 (unchanged) |
| Direct-output annotated `[]` (LAB-TC-ARRAY-P1) | ok/0 | ok/0 (unchanged) |

---

## arch_patterns

Stringly `call_contract("append", ...)` sites (c0-c4 in `example.ig`) have no type annotation → override block skipped → still `oof/6` (5×OOF-TY0 + 1×OOF-TY1) in both TCs. **Migration route unblocked:** after `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3` rewrites c0-c4 to canonical form with annotations, both TCs will be clean.

---

## Non-Goals

- No parser change (annotation already parsed)
- No emitter change
- No stdlib change
- No app source changes
- No Ruby TC changes
- No change to `collection_output_hints` (LAB-TC-ARRAY-P1/P2 unchanged)
- No change to output boundary check behavior for unannotated cases

---

## Acceptance Criteria Met

- [x] `cargo build --release` succeeds
- [x] P2 proof runner 45/45 PASS
- [x] P1 proof runner updated to 46/46 PASS (14 gap-documenting checks flipped to fixed-state)
- [x] arch_patterns gap resolved/reclassified (shape unblocked; migration pending)
- [x] No parser/emitter/stdlib/app source changes

---

## Next

`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3` — migrate arch_patterns c0-c4 stringly sites to canonical form → arch_patterns `DUAL-CLEAN`.
