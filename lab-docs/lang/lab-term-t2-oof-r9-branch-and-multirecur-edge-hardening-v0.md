# Lab: PROP-041 T2 OOF-R9 — Branch and Multi-Recur Edge Hardening

Status: closed  
Date: 2026-06-08  
Card: LAB-TERM-T2-P2  
Route: EXPERIMENTAL / LAB-ONLY / PROOF-HARDENING  
Authority: lab proof — structural evidence only; no canon authority, no runtime authorization

---

## 1. Situation

LAB-TERM-T2-P1 closed with `verify_t2_structural_size_relation.rb` 52/52 PASS, proving full
Rust-Ruby symmetry for the PROP-041 T2 structural-size relation. The OOF-R9 checks in P1 covered
simple single-recur cases: wrong accessor, plain subject, wrong variable.

This document covers LAB-TERM-T2-P2: edge hardening of OOF-R9 across:
- Multi-recur expressions (multiple `recur()` calls in one expression)
- If-expression branches (recur() calls inside then/else blocks)
- Nested arithmetic (recur() buried inside a BinaryOp)

---

## 2. Root Cause Found and Fixed

### 2.1 The Bug

`check_t2_callsite_in_expr` in `src/typechecker.rs` had an incomplete `IfExpr` arm:

```rust
// BEFORE (incomplete):
Expr::IfExpr { cond, .. } => {
    self.check_t2_callsite_in_expr(cond, ...);
    // then/else_block NOT walked — recur() in branches missed
}
```

Consequence: a contract with `decreases items.next` and a registered size relation, where
the `recur()` call in the **else branch** used the wrong accessor (e.g. `recur(items)` instead
of `recur(items.next, n-1)`), would NOT fire OOF-R9. The wrong call site would silently pass.

### 2.2 The Fix

Extended the `IfExpr` arm to mirror exactly what `check_recur_in_expr` does for IfExpr:

```rust
// AFTER (complete):
Expr::IfExpr { cond, then, else_block } => {
    self.check_t2_callsite_in_expr(cond, ...);
    // then block
    for stmt in &then.stmts {
        if let Stmt::Let { expr, .. } = stmt {
            self.check_t2_callsite_in_expr(expr, ...);
        }
    }
    if let Some(re) = &then.return_expr {
        self.check_t2_callsite_in_expr(re, ...);
    }
    // else block
    if let Some(eb) = else_block {
        for stmt in &eb.stmts {
            if let Stmt::Let { expr, .. } = stmt {
                self.check_t2_callsite_in_expr(expr, ...);
            }
        }
        if let Some(re) = &eb.return_expr {
            self.check_t2_callsite_in_expr(re, ...);
        }
    }
}
```

The `BinaryOp` arm was already correct (recurses into both `left` and `right`), so multi-recur
and nested arithmetic were handled before this fix. The IfExpr arm was the only gap.

---

## 3. Edge Cases Proven

### 3.1 Multi-Recur Expressions

| Fixture | Contract expression | Expected | Result |
|---------|-------------------|----------|--------|
| `t2r9_multi_recur_both_correct.ig` | `recur(items.next) + recur(items.next)` | PASS (no OOF-R9) | ✅ PASS |
| `t2r9_multi_recur_one_wrong.ig` | `recur(items.next) + recur(items)` | OOF-R9 fires | ✅ OOF-R9 |

Key property: the correct `recur(items.next)` call does NOT suppress OOF-R9 for the wrong
`recur(items)` call. Mixed correct/wrong fails closed.

### 3.2 If-Expression Branches

| Fixture | Contract expression | Expected | Result |
|---------|-------------------|----------|--------|
| `t2r9_if_both_branches_correct.ig` | `if n>0 { recur(items.next, n-1) } else { recur(items.next, n-1) }` | PASS (no OOF-R9) | ✅ PASS |
| `t2r9_if_wrong_else_branch.ig` | `if n>0 { recur(items.next, n-1) } else { recur(items, n-1) }` | OOF-R9 fires | ✅ OOF-R9 |

The IfExpr fix directly proves R9D: wrong accessor in else-branch is caught.

### 3.3 Nested Arithmetic

| Fixture | Contract expression | Expected | Result |
|---------|-------------------|----------|--------|
| `t2r9_nested_arith_wrong.ig` | `0 + recur(items)` | OOF-R9 fires | ✅ OOF-R9 |

`recur()` buried inside a BinaryOp at any depth is correctly caught.

### 3.4 OOF-R3/R8 Precedence Unchanged

Numeric dotted-path → OOF-R3 (not OOF-R9). Missing relation → OOF-R8 (not OOF-R9).
These invariants are confirmed unchanged by this fix.

### 3.5 T1 Regression: syntactic_v0 Unaffected

Simple-identifier `decreases n` contracts compile without OOF-R9. T1 is not affected.

---

## 4. Verification

### 4.1 Verify Script

`igniter-lab/igniter-compiler/verify_t2_oof_r9_edge_cases.rb`

21 checks across sections R9A–R9H.

### 4.2 Results

```
verify_t2_oof_r9_edge_cases.rb:           21/21 PASS
verify_t2_structural_size_relation.rb:    52/52 PASS  (full T2 symmetry — no regression)
verify_oof_r3.rb:                         34/34 PASS  (OOF-R3 scope unchanged)
verify_g5_recur.rb:                       18/18 PASS  (recur() semantics unchanged)
```

### 4.3 Coverage

| Section | Description | Checks |
|---------|-------------|--------|
| R9A | Multi-recur both correct: no OOF-R9, no OOF-R8, compiles | 3 |
| R9B | Multi-recur one wrong: OOF-R9 fires; correct site does NOT suppress wrong-site R9 | 3 |
| R9C | If-expr both branches correct: no OOF-R9, no OOF-R3/R8, compiles | 3 |
| R9D | If-expr wrong else branch: OOF-R9 fires, no OOF-R3/R8 | 3 |
| R9E | Nested arithmetic wrong recur: OOF-R9 fires, no OOF-R3 | 2 |
| R9F | Baseline OOF-R9 forms: wrong_accessor, plain_ref, wrong_variable | 3 |
| R9G | OOF-R3/R8 precedence: numeric → R3 not R9; missing → R8 not R9 | 2 |
| R9H | T1 regression: T1 contracts compile; OOF-R9 does NOT fire | 2 |
| **Total** | | **21** |

---

## 5. Files Changed

| File | Change |
|------|--------|
| `src/typechecker.rs` | Extended `check_t2_callsite_in_expr` IfExpr arm to walk then/else_block bodies |
| `fixtures/prop041_t2_structural_size_relation/t2r9_multi_recur_both_correct.ig` | New |
| `fixtures/prop041_t2_structural_size_relation/t2r9_multi_recur_one_wrong.ig` | New |
| `fixtures/prop041_t2_structural_size_relation/t2r9_if_both_branches_correct.ig` | New |
| `fixtures/prop041_t2_structural_size_relation/t2r9_if_wrong_else_branch.ig` | New |
| `fixtures/prop041_t2_structural_size_relation/t2r9_nested_arith_wrong.ig` | New |
| `verify_t2_oof_r9_edge_cases.rb` | New |

---

## 6. Canon Boundary

No new OOF codes introduced. `check_t2_callsite_in_expr` is a Rust lab-only function — this
fix does not affect the Ruby canon pipeline (`igniter-lang`). No canon files were changed.

All surfaces from LAB-TERM-T2-P1 remain closed:

| Surface | Status |
|---------|--------|
| Runtime execution / `igc run` / VM | Closed |
| Full termination proof authority | T2 is structural evidence only |
| igniter-lang canon files | Unchanged |
| Public/stable/production claims | Closed |

**T2 is structural evidence with trust metadata — NOT a verified termination proof.**

---

## 7. Next Route

`LAB-TERM-T2-P2` hardening is complete. The Rust lab T2 OOF-R9 surface is now fully
proven across all relevant expression forms.

Recommended next steps:
- **PROP-041 T3 (future):** Numeric measure expressions — `decreases size(items)` where
  `size` is a declared pure function (see `lab-managed-recursion-full-termination-proof-beyond-syntactic-v0.md` §2.3)
- **No further T2 hardening required** — IfExpr, BinaryOp, and simple recur call forms are
  all covered

**LAB-TERM-T2-P2 is closed.**
