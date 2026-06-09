# LAB-T3-P1: T3 Numeric Measure Expressions — Rust Compiler Symmetry

**Card:** LAB-T3-P1
**Category:** lang
**Track:** lab-term-t3-numeric-measure-rust-symmetry-v0
**Date closed:** 2026-06-09
**Status:** ✅ CLOSED — 45/45 PASS; all regressions clean

**Role:** Implementation agent
**Route:** EXPERIMENTAL / LAB-ONLY / RUST-SYMMETRY

**Depends on:**
- PROP-042-P5 (production implementation, 45/45 PASS) ✅
- PROP-041-P7 (T2 production) ✅
- LAB-TERM-T2-P1 (Rust T2 symmetry) ✅
- LAB-TERM-T2-P2 (OOF-R9 edge hardening) ✅

---

## Decision

**LAB-T3-P1 is complete. Rust lab T3 numeric measure symmetry is proven.**

Observable behavior matches Ruby production P5 exactly. Lab behavior is not canon authority.

| Suite | Result |
|-------|--------|
| `verify_t3_numeric_measure.rb` | **45/45 PASS** |
| `verify_t2_structural_size_relation.rb` | **52/52 PASS** (T2 regression clean) |
| `verify_t2_oof_r9_edge_cases.rb` | **21/21 PASS** (OOF-R9 regression clean) |
| `verify_oof_r3.rb` | **34/34 PASS** (OOF-R3 regression clean) |
| `verify_g5_recur.rb` | **18/18 PASS** (G5 recur regression clean) |

---

## Files Modified

| File | Change |
|------|--------|
| `igniter-lab/igniter-compiler/src/parser.rs` | LParen check in `parse_decreases_body_decl` |
| `igniter-lab/igniter-compiler/src/typechecker.rs` | T3 structs + constants + dispatch + OOF-P1 suppression + 3 new methods; `t3_context: RefCell<Option<T3Context>>` on TypeChecker |
| `igniter-lab/igniter-compiler/src/emitter.rs` | T3 termination block before T2/T1 |
| `igniter-lab/igniter-compiler/fixtures/prop042_t3_numeric_measure/` | 16 fixture files |
| `igniter-lab/igniter-compiler/verify_t3_numeric_measure.rb` | 45-check proof runner |
| `igniter-lab/lab-docs/lang/lab-term-t3-numeric-measure-rust-symmetry-v0.md` | Lab doc |

**Unchanged:** `classifier.rs` — pass-through is already correct.

---

## Key Implementation Notes

### OOF-P1 Suppression

The critical difference vs. T2: user-declared accessors (`size_relation Collection sub`)
are not real fields in `type_shapes`, so normal field resolution fires OOF-P1. The
`t3_context: RefCell<Option<T3Context>>` field on `TypeChecker` allows `infer_expr` to
suppress OOF-P1 for ALL field accesses on the T3-measured input. OOF-R11 is the
authoritative diagnostic for structural coverage failures.

This mirrors Ruby production: `@t3_context` instance variable accessed from `infer_expr`.

### T3 Context Lifecycle

- Set at start of `typecheck_contract` via `*self.t3_context.borrow_mut() = None`
- Set when T3 dispatch succeeds: `*self.t3_context.borrow_mut() = ctx.clone()`
- Accessed in `infer_expr` FieldAccess branch: `self.t3_context.borrow()`
- Cleared on next `typecheck_contract` call (reset to None at top)

### Dispatch Priority Chain

```
decreases <variant>
  parse_t3_call_form(v) matches  → T3: handle_t3_variant
  v.contains('.')                → T2: handle_t2_variant  
  else                           → T1: direct syntactic_v0
```

---

## Explicit Answers

| Question | Answer |
|----------|--------|
| Rust T3 symmetry matches Ruby production P5? | ✅ YES — SIR identical, same OOF codes |
| Parser/classifier/typechecker/emitter all match? | ✅ YES |
| OOF-R10/R11 fire correctly? | ✅ YES — mutual exclusivity confirmed |
| T1/T2/R3/OOF-R9 regressions clean? | ✅ YES — all at same counts |
| Lab behavior creates canon authority? | ❌ NO — evidence only |
| Runtime/VM remains closed? | ✅ YES — no VM changes |

---

## Closed Surfaces

- Text length measures — OOF-R10 (deferred pending Unicode receipt canon authority)
- User-defined numeric measures — OOF-R10 (deferred)
- `size(Collection)` / `length(Collection)` — OOF-R10, v1 work
- Runtime/VM behavior — closed, separate authorization
- Public/stable API, `igc run`, `.igbin` — closed

---

## Next Route

PROP-042 T3 is fully proven in both production Ruby and Rust lab. NUMERIC_MEASURE_BUILTINS
v0 (`count` only) is the closed surface.

Future work (all require separate PROP or authorization):
- NUMERIC_MEASURE_BUILTINS v1: `size` / `length` candidates
- Text length measures: Unicode receipt canon authority required
- User-defined numeric measures: separate PROP
- Runtime/VM recursion verification: separate authorization
