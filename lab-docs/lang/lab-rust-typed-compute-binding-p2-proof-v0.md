# LANG-RUST-TYPED-COMPUTE-BINDING-P2

**Card:** `LANG-RUST-TYPED-COMPUTE-BINDING-P2`  
**Date:** 2026-06-13  
**Status:** CLOSED — implementation complete  
**Scope:** Rust TC implementation (one file: `typechecker.rs`)  
**Proof:** 45/45 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p2.rb`  
**P1 Proof (updated):** 46/46 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p1.rb`

---

## What Was Done

Ported Ruby `LANG-TYPED-COMPUTE-BINDING-P2` behavior to the Rust TC. Added two items to `typechecker.rs`:

### 1. `fn unknown_or_unknown_bearing` helper

Added immediately after `fn type_display` (~line 2057). Mirrors Ruby `unknown_or_unknown_bearing?`:

```rust
fn unknown_or_unknown_bearing(&self, t: &serde_json::Value) -> bool {
    if self.type_name(t) == "Unknown" {
        return true;
    }
    t.get("params")
        .and_then(|p| p.as_array())
        .map(|params| params.iter().any(|p| self.unknown_or_unknown_bearing(&self.type_ir(p))))
        .unwrap_or(false)
}
```

Returns `true` if the type is scalar `Unknown` **or** any param at any recursion depth contains `Unknown`. Handles both `Unknown` (e.g., from `ArrayLiteral` inference) and `Collection[Unknown]` (e.g., from `append(Unknown, elem)`).

### 2. Annotation override block in the compute arm

Inserted immediately before `symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())` (~line 1187), after the existing LAB-RACK-P13 and LAB-TC-ARRAY-P1 upgrade blocks:

```rust
// LANG-RUST-TYPED-COMPUTE-BINDING-P2: if the compute has a declared
// type annotation, apply annotation-based bind-type resolution.
// Mirrors Ruby LANG-TYPED-COMPUTE-BINDING-P2 three-way branch:
// (a) Unknown-bearing inferred → annotation authoritative, no error.
// (b) Concrete match (structurally_assignable) → keep inferred type.
// (c) Concrete mismatch → emit OOF-TY0, use annotation to avoid cascade.
if let Some(ann) = &decl.type_annotation {
    let ann_type = self.type_ir(ann);
    if self.unknown_or_unknown_bearing(&typed_expr.resolved_type) {
        // (a) inferred is Unknown or Unknown-bearing — annotation authoritative
        typed_expr.resolved_type = ann_type;
    } else if !self.structurally_assignable(&typed_expr.resolved_type, &ann_type) {
        // (c) concrete mismatch — emit OOF-TY0, use annotation to avoid cascade
        type_errors.push(ClassifierDiagnostic {
            rule: "OOF-TY0".to_string(),
            message: format!(
                "Binding type mismatch: declared {}, got {}",
                self.type_display(&ann_type),
                self.type_display(&typed_expr.resolved_type)
            ),
            node: decl.name.clone(),
            line: None,
        });
        typed_expr.resolved_type = ann_type;
    }
    // (b) concrete match — structurally_assignable → keep inferred type (no change)
}
```

**Build:** `cargo build --release` — succeeded (warnings only, no errors).

---

## Why This Fixes the Gap

Before P2, `compute c0 : Collection[Transition] = [t0, t1]`:

1. `infer_expr(ArrayLiteral{[t0, t1]})` → `Unknown` (by design)
2. `collection_output_hints["c0"]` absent (pre-scan only keys on output node names)
3. `symbol_types["c0"] = Unknown`
4. `append(c0, t2)` where `c0 = Unknown` → `Collection[Unknown]`
5. Output check: `structurally_assignable(Collection[Unknown], Collection[Transition])` → false (D2 rule) → `OOF-TY1`

After P2, at step 3:
- `unknown_or_unknown_bearing(Unknown)` → `true` (scalar Unknown)
- Annotation `Collection[Transition]` is authoritative → `typed_expr.resolved_type = Collection[Transition]`
- `symbol_types["c0"] = Collection[Transition]`
- `append(Collection[Transition], Unknown)` → `Collection[Transition]` (OOF-COL6 guard skips item=Unknown)
- Output check passes → `ok/0`

---

## Three-Way Branch Behavior

| Scenario | Inferred | Annotation | Branch | Result |
|---|---|---|---|---|
| Annotated `[]` intermediate | `Unknown` | `Collection[T]` | (a) | Annotation used, no error |
| Annotated `[a, b]` with Unknown items | `Unknown` | `Collection[T]` | (a) | Annotation used, no error |
| `append(Unknown, elem)` result | `Collection[Unknown]` | `Collection[T]` | (a) | Annotation used, no error |
| `compute s : String = "hello"` | `String` | `String` | (b) | Inferred kept, no error |
| `compute n : String = 42` | `Integer` | `String` | (c) | OOF-TY0 + annotation used |
| No annotation | (any) | none | — | No change (else branch skipped) |

---

## Before / After Compile Matrix

| Fixture | Rust before | Rust after | Ruby |
|---|---|---|---|
| GAP_CHAIN (`compute c0 : Collection[T] = []` + downstream append) | oof/1 OOF-TY1 | **ok/0** | ok/0 |
| GAP_CHAIN_NONEMPTY (non-empty annotated seed) | oof/1 OOF-TY1 | **ok/0** | ok/0 |
| MULTI_HOP (two-hop chain) | oof/1 OOF-TY1 | **ok/0** | ok/0 |
| STRING_CHAIN | oof/1 OOF-TY1 | **ok/0** | ok/0 |
| COL_UNKNOWN (inferred `Collection[Unknown]`, annotated) | oof/1 OOF-TY1 | **ok/0** | ok/0 |
| DIRECT_OUTPUT (LAB-TC-ARRAY-P1) | ok/0 | ok/0 (unchanged) | ok/0 |
| CONCRETE_MATCH | ok/0 | ok/0 (unchanged) | ok/0 |
| CONCRETE_MISMATCH | oof/1 OOF-TY1 | **oof/1 OOF-TY0** | oof/1 OOF-TY0 |
| UNANNOTATED | oof/1 OOF-TY1 | oof/1 OOF-TY1 (unchanged) | oof/1 OOF-TY1 |
| bloom_filter | ok/0 | ok/0 (unchanged) | ok/0 |
| arch_patterns | oof/6 | oof/6 (stringly sites — migration pending) | oof/6 |

---

## arch_patterns Status

The 5 deferred c0-c4 sites in `example.ig` remain as stringly `call_contract("append", ...)` — not migrated in P2. Their compute nodes have **no type annotation**, so the override block is skipped (else branch). They still produce `OOF-TY0` (unknown callee 'append') + `OOF-TY1` (c4 → Unknown → output). arch_patterns remains `oof/6` in both TCs.

The P2 Rust fix **unblocks the migration path**. After migrating c0-c4 to canonical form:
- `compute c0 : Collection[Transition] = [t0, t1]` — P2 binds `Collection[Transition]`
- `compute c1 = append(c0, t2)` — `append(Collection[Transition], Unknown)` → `Collection[Transition]`
- c1–c4 all `Collection[Transition]` → output check passes → arch_patterns `DUAL-CLEAN`

Route: `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3`.

---

## Non-Goals

- Did not change `collection_output_hints` mechanism (LAB-TC-ARRAY-P1/P2 unchanged)
- Did not change the output boundary check
- Did not change unannotated compute behavior
- Did not change parser (annotation already parsed)
- Did not change emitter
- Did not change stdlib
- Did not change any app source files
- Did not change Ruby TC

---

## Proof Summary

| Section | Checks | Result |
|---|---|---|
| A: Source patch present | 4 | 4/4 PASS |
| B: Helper detects scalar Unknown | 4 | 4/4 PASS |
| C: Helper detects param-depth Unknown | 4 | 4/4 PASS |
| D: Annotated [] binds Collection[T] | 4 | 4/4 PASS |
| E: Downstream append sees Collection[T] | 4 | 4/4 PASS |
| F: Concrete match behavior preserved | 4 | 4/4 PASS |
| G: Concrete mismatch OOF-TY0 diagnostic | 4 | 4/4 PASS |
| H: Unannotated compute unchanged | 3 | 3/3 PASS |
| I: Output boundary unchanged (LAB-TC-ARRAY-P1) | 4 | 4/4 PASS |
| J: arch_patterns c0-c4 shape unblocked | 4 | 4/4 PASS |
| K: Ruby parity / no Ruby TC changes | 3 | 3/3 PASS |
| L: No parser / emitter / stdlib changes | 3 | 3/3 PASS |
| **Total** | **45** | **45/45 PASS** |
