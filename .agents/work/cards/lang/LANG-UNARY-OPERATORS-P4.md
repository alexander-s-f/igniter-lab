# LANG-UNARY-OPERATORS-P4

**Status:** CLOSED — PROVED 47/47 PASS  
**Track:** lang / parser / typechecker / emitter (Rust)  
**Route:** RUST PARITY PROOF  
**Date:** 2026-06-12  
**Predecessors:** LANG-UNARY-OPERATORS-P3 (Ruby implementation)  
**Next:** none (feature complete — dual-toolchain)

---

## Goal

Rust parity for unary `!` (logical negation) and unary `-` (integer negation). Four Rust file changes: parser, typechecker, emitter (two locations). Stdlib inventory updated to `dual-toolchain`.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| parser.rs — unary minus branch | `igniter-lab/igniter-compiler/src/parser.rs` | Done |
| typechecker.rs — Expr::UnaryOp arm | `igniter-lab/igniter-compiler/src/typechecker.rs` | Done |
| emitter.rs — unary_op → call (semantic_expr + semantic_expr_for_compute) | `igniter-lab/igniter-compiler/src/emitter.rs` | Done |
| stdlib-inventory.json — dual-toolchain | `igniter-lang/docs/spec/stdlib-inventory.json` | Done |
| Proof runner | `igniter-lab/igniter-compiler/verify_unary_operators_p4.rb` | 47/47 PASS |
| This card | `.agents/work/cards/lang/LANG-UNARY-OPERATORS-P4.md` | Written |

---

## Verdict: PROVED 47/47 PASS

```
Result: 47/47 PASS
VERDICT: PASS — LANG-UNARY-OPERATORS-P4 PROVED
  Unary ! : Bool → Bool (stdlib.primitive.not)
  Unary - : Integer → Integer (stdlib.integer.neg)
  Both: OOF-TY0 on wrong operand (Bool/Integer returned on all paths)
  Both: Unknown permissive (input : Unknown — no OOF-TY0)
  SIR: no raw unary_op nodes — all converted to call nodes
  SIR: resolved_type attached (Bool / Integer)
  !is_empty(col) composition works
  Regression: binary ops, is_empty, non_empty, if_expr, append — clean
  Inventory: stdlib.primitive.not + stdlib.integer.neg → dual-toolchain
```

---

## Implementation Notes

### Parser (`parser.rs` ~line 2734)
Added `is_unary_minus` branch after the `!` (Bang) case in `parse_unary`. Operand uses `parse_postfix` (not `parse_unary`) to prevent chained unary.

### TypeChecker (`typechecker.rs` before `_ =>` wildcard)
Added `Expr::UnaryOp { op, operand }` arm in `infer_expr`:
- Infers operand type recursively
- `!`: requires Bool, emits OOF-TY0 for non-Bool/non-Unknown, returns Bool
- `-`: requires Integer, emits OOF-TY0 for non-Integer/non-Unknown, returns Integer
- Unknown permissive on both paths
- `_fn_name` ignored (emitter handles conversion, not TC)

### Emitter (`emitter.rs` — two locations)
1. **`semantic_expr`**: Added `unary_op` → call conversion block (before text-stdlib section). Maps `!` → `stdlib.primitive.not` / Bool, `-` → `stdlib.integer.neg` / Integer. Attaches `resolved_type`.
2. **`semantic_expr_for_compute`**: Added delegation to `semantic_expr` for `unary_op` kind (mirrors `if_expr` delegation pattern). Without this, compute nodes called `semantic_expr_for_compute` which fell through to the generic recursive path without triggering the conversion.

---

## Closed Scope

- No Decimal/Float negation
- No chained unary (`--x`, `!!x`)
- No baseline hash updates
- No app source migration
