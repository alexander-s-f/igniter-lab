# LANG-RUST-TYPED-COMPUTE-BINDING-P1

**Card:** `LANG-RUST-TYPED-COMPUTE-BINDING-P1`  
**Date:** 2026-06-13  
**Status:** CLOSED — research complete  
**Scope:** Research + proof (no compiler changes in P1)  
**Proof:** 46/46 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p1.rb`

---

## Background

`LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` deferred 5 `arch_patterns` sites (c0-c4 in `BuildTransitionTable`) because migrating them would make Rust TC emit OOF-TY1. The root cause is that Rust TC does not propagate a `compute` node's declared type annotation into `symbol_types` when the inferred RHS type is Unknown or Unknown-bearing.

Ruby has had this behavior since `LANG-TYPED-COMPUTE-BINDING-P2` (CLOSED). Rust does not.

---

## Gap Description

### The shape

```ig
type Transition { ... }

contract BuildTransitionTable {
  compute t0 = { from_status: "pending", ... }   -- Transition literal (infers Unknown in Rust)
  compute t1 = { from_status: "active",  ... }   -- Transition literal (infers Unknown in Rust)

  compute c0 : Collection[Transition] = [t0, t1] -- annotated BOOTSTRAP seed
  compute c1 = append(c0, t2)                    -- ACCUMULATING
  compute c2 = append(c1, t3)
  compute c3 = append(c2, t4)
  compute c4 = append(c3, t5)
  output c4 : Collection[Transition]
}
```

### What Rust does today

1. `infer_expr(ArrayLiteral{[t0, t1]})` → `Unknown` (by design; see typechecker.rs comment at line ~3990)
2. `collection_output_hints["c0"]` is absent — the pre-scan only keys on **output** node names, not intermediate compute names
3. `symbol_types["c0"] = Unknown`
4. `append(c0, t2)` where `c0 = Unknown` → `col_arg_name = "Unknown"` → `elem_type = Unknown` → `c1 = Collection[Unknown]`
5. `c2 = Collection[Unknown]`, ..., `c4 = Collection[Unknown]`
6. Output check: `structurally_assignable(Collection[Unknown], Collection[Transition])` → recurses into params → `structurally_assignable(Unknown, Transition)` → **false** (D2 rule) → OOF-TY1

### What Ruby does today (P2 behavior)

After `LANG-TYPED-COMPUTE-BINDING-P2`:

```ruby
bind_type = if decl["type_annotation"]
  expected_type = type_ir(decl["type_annotation"])
  if unknown_or_unknown_bearing?(inferred_type)
    expected_type                           # annotation authoritative
  elsif structurally_assignable?(inferred_type, expected_type)
    inferred_type                           # concrete match — keep inferred
  else
    type_errors << oof("OOF-TY0", ...)      # concrete mismatch — emit error
    expected_type                           # annotation prevents cascade
  end
else
  inferred_type                             # no annotation — no change
end
symbol_types[decl.fetch("name")] = bind_type
```

### Divergence

| Scenario | Ruby | Rust |
|---|---|---|
| `compute c0 : Collection[T] = []` (direct output) | ok/0 | ok/0 |
| `compute c0 : Collection[T] = []` (intermediate, append downstream) | ok/0 | **oof/1 OOF-TY1** |
| `compute c0 : Collection[T] = [a, b]` (intermediate) | ok/0 | **oof/1 OOF-TY1** |
| `compute s : String = "hello"` (concrete match) | ok/0 | ok/0 |
| `compute n : String = 42` (concrete mismatch) | oof/1 OOF-TY0 | oof/1 OOF-TY1 (at output) |
| Unannotated `compute c = []` | oof/1 OOF-TY1 | oof/1 OOF-TY1 |

---

## Research Answers

**Q01 — Where does Rust typecheck compute declarations?**  
`typechecker.rs`: `"compute" | "snapshot"` arm (~line 1106).

**Q02 — Where is a compute's declared type annotation read?**  
In the `"output"` arm (~line 1228) for the output-boundary check, and in the `collection_output_hints` pre-scan (LAB-TC-ARRAY-P1/P2, lines ~698-747) — but **not** in the compute arm to override the bind type.

**Q03 — Where are local symbol types updated after compute inference?**  
Single call: `symbol_types.insert(decl.name.clone(), typed_expr.resolved_type.clone())` after the array-literal and record-literal upgrade blocks (~line 1187).

**Q04 — Does Rust upgrade at output boundary only, or also during compute binding?**  
Output boundary ONLY (via `collection_output_hints` pre-scan for direct-output positions). Intermediate annotated computes are not upgraded.

**Q05 — What exact type does `empty_trail` / `c0` get in symbol_types today?**  
`Unknown`. `infer_expr` for `ArrayLiteral` always returns `Unknown` (by design). The `collection_output_hints` mechanism fires only when the compute node name matches an output name.

**Q06 — Is the gap limited to `Collection[Unknown]`, or any Unknown-bearing type?**  
Any compute where: (a) a type annotation is declared, and (b) the RHS infers as Unknown or Unknown-bearing. Arrays always infer Unknown from `infer_expr`. Unannotated record literals also infer Unknown. The gap applies to all such cases.

**Q07 — Should Rust mirror Ruby P2 exactly?**  
Yes. Same three-way branch:  
- (a) Unknown-bearing inferred → annotation authoritative, no error  
- (b) Concrete match (structurally_assignable) → keep inferred type  
- (c) Concrete mismatch → emit OOF-TY0, use annotation to prevent cascade

**Q08 — What happens for concrete mismatch?**  
Ruby (P2): OOF-TY0 at binding time; annotation authoritative; no cascade OOF-TY1.  
Rust (today): no binding-time error; inferred type used; OOF-TY1 at output boundary.

**Q09 — What happens for concrete match?**  
Both TCs: inferred type used; annotation confirms. No error. After P2 Rust fix: same (`structurally_assignable` branch keeps inferred type).

**Q10 — What happens when there is no annotation?**  
Both TCs: inferred type used as bind type. No change from P2 fix (else branch).

**Q11 — What happens when annotation is non-Collection?**  
Same three-way branch applies to any type. A `String` annotation on a `String` literal → concrete match → no gap. A `Map[K,V]` annotation on an Unknown-bearing RHS → (a) use annotation.

**Q12 — Which arch_patterns sites are unblocked by P2?**  
All 5 deferred sites (c0-c4 in `BuildTransitionTable`). After P2 Rust fix + migration:
- `c0 : Collection[Transition] = [t0, t1]` → binds `Collection[Transition]`
- `append(c0, t2)` where `c0 = Collection[Transition]`, `t2 = Unknown` → `elem_type = Transition`, `item = Unknown` → OOF-COL6 guard skipped (item IS Unknown) → result `Collection[Transition]`
- c1-c4 all `Collection[Transition]` → output check passes → 0 diags → arch_patterns DUAL-CLEAN

**Q13 — Can P2 be one local Rust TC change?**  
Yes. One file: `typechecker.rs`. One insertion point. Two additions.

---

## Implementation Plan (for P2)

### File

`igniter-lab/igniter-compiler/src/typechecker.rs`

### Addition 1: `unknown_or_unknown_bearing` helper

Add adjacent to the existing `structurally_assignable` fn (~line 2057):

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

### Addition 2: annotation override block in the compute arm

Insert immediately before `symbol_types.insert(decl.name.clone(), ...)` (~line 1187):

```rust
// LANG-RUST-TYPED-COMPUTE-BINDING-P2: if the compute has a declared
// type annotation, apply annotation-based bind-type resolution.
// Mirrors Ruby LANG-TYPED-COMPUTE-BINDING-P2 three-way branch:
// (a) Unknown-bearing inferred → annotation authoritative, no error.
// (b) Concrete match → keep inferred type.
// (c) Concrete mismatch → emit OOF-TY0, use annotation to prevent cascade.
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
    // (b) concrete match — keep inferred type (no change)
}
```

### Non-goals

- No parser change (annotation already parsed as `type_annotation` field)
- No emitter change
- No stdlib change
- No app source changes in P2
- Does NOT affect the `collection_output_hints` mechanism (LAB-TC-ARRAY-P1/P2 unchanged)
- Does NOT affect the output boundary check (`"output"` arm unchanged)
- Does NOT change unannotated compute behavior

### Interaction with existing mechanisms

The annotation override block runs AFTER the existing upgrades (LAB-RACK-P13 record literal upgrade, LAB-TC-ARRAY-P1 array literal upgrade). If either upgrade fires, `typed_expr.resolved_type` is already non-Unknown → the annotation block takes branch (b) or (c), not (a). No conflict.

---

## App Impact

| App | Current | After P2 + migration |
|---|---|---|
| arch_patterns | oof/6 (5 OOF-TY0 + 1 OOF-TY1) | **ok/0 (DUAL-CLEAN)** |
| bloom_filter | ok/0 | ok/0 (unchanged) |
| decision_tree | ok/0 | ok/0 (unchanged) |
| vector_editor | ok/0 Rust | ok/0 (unchanged) |

The bloom_filter, decision_tree, and vector_editor migrations from P2 already work because they either use ACCUMULATING (input-typed collection) or BOOTSTRAP → record output (LAB-TC-ARRAY-P2 field-context hint fires). Only the arch_patterns direct-Collection-output chain requires P2.

---

## Proof Summary

| Section | Checks | Result |
|---|---|---|
| A: Source survey | 6 | 6/6 PASS |
| B: Gap reproduction | 5 | 5/5 PASS |
| C: Downstream type evidence | 5 | 5/5 PASS |
| D: Output boundary comparison | 4 | 4/4 PASS |
| E: Ruby parity documented | 5 | 5/5 PASS |
| F: Concrete match case | 4 | 4/4 PASS |
| G: Concrete mismatch case | 4 | 4/4 PASS |
| H: Unannotated unchanged | 4 | 4/4 PASS |
| I: arch_patterns c0-c4 evidence | 5 | 5/5 PASS |
| J: Implementation insertion point | 4 | 4/4 PASS |
| **Total** | **46** | **46/46 PASS** |
