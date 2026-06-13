# LANG-RUST-TYPED-COMPUTE-BINDING-P1

**Status:** CLOSED  
**Date closed:** 2026-06-13  
**Lane:** lang / rust-typechecker / parity  
**Scope:** Research + proof (no compiler changes)  
**Proof:** 46/46 PASS — `igniter-lab/igniter-compiler/verify_rust_typed_compute_binding_p1.rb`  
**Lab doc:** `igniter-lab/lab-docs/lang/lab-rust-typed-compute-binding-p1-v0.md`

---

## Gap Confirmed

Rust TC does not propagate a compute node's declared type annotation into `symbol_types` when the inferred RHS type is Unknown or Unknown-bearing.

- `compute c0 : Collection[Transition] = [...]` → `symbol_types["c0"] = Unknown` (not `Collection[Transition]`)
- `append(c0, t)` → first arg Unknown → `Collection[Unknown]`
- `output c4 : Collection[Transition]` → OOF-TY1

Ruby has had the fix since `LANG-TYPED-COMPUTE-BINDING-P2` (via `unknown_or_unknown_bearing?` + three-way branch in the compute arm).

---

## Key Finding: Rust output boundary vs. intermediate divergence

| Shape | Rust | Ruby |
|---|---|---|
| `compute c0 : Collection[T] = []` + `output c0 : Collection[T]` | ok/0 | ok/0 |
| `compute c0 : Collection[T] = []` + `append(c0,…)` + output | **oof/1 OOF-TY1** | ok/0 |

The Rust LAB-TC-ARRAY-P1 mechanism (collection_output_hints) handles direct-output positions only. Intermediate annotated computes are not covered.

---

## Implementation Route (P2)

**One file:** `igniter-lab/igniter-compiler/src/typechecker.rs`  
**One insertion point:** immediately before `symbol_types.insert(decl.name.clone(), …)` (~line 1187)  
**Two additions:**

1. `fn unknown_or_unknown_bearing(&self, t: &Value) -> bool` — recursive helper (~4 lines)
2. Annotation override block — mirror Ruby P2 three-way branch (~15 lines)

Three-way branch:  
- (a) Unknown-bearing inferred → annotation authoritative, no error  
- (b) Concrete match (structurally_assignable) → keep inferred type  
- (c) Concrete mismatch → OOF-TY0 + annotation to prevent cascade

No parser change. No emitter change. No stdlib change. No app source changes in P2.

---

## arch_patterns Unblocked

All 5 deferred sites (c0-c4 in `BuildTransitionTable`) unblocked after P2 + migration:

```ig
compute c0 : Collection[Transition] = [t0, t1]   -- P2 binds Collection[Transition]
compute c1 = append(c0, t2)                       -- Collection[Transition] propagates
compute c2 = append(c1, t3)
compute c3 = append(c2, t4)
compute c4 = append(c3, t5)
output c4 : Collection[Transition]               -- passes → arch_patterns DUAL-CLEAN
```

Note: `append(Collection[Transition], Unknown)` works because OOF-COL6 guard is `elem != "Unknown" && item != "Unknown" && elem != item` — item is Unknown → guard skipped → result `Collection[Transition]`.

---

## Non-goals

- Does not change `collection_output_hints` mechanism
- Does not change output boundary check
- Does not change unannotated compute behavior
- Does not require parser change
- Does not affect other apps (bloom_filter, decision_tree, vector_editor already clean)
