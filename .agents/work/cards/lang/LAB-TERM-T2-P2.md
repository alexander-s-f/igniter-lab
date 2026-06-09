# LAB-TERM-T2-P2: T2 OOF-R9 Branch and Multi-Recur Edge Hardening

**Status:** CLOSED  
**Date closed:** 2026-06-08  
**Category:** lang  
**Track:** lab-term-t2-oof-r9-branch-and-multirecur-edge-hardening-v0  
**Route:** EXPERIMENTAL / LAB-ONLY / PROOF-HARDENING  
**Depends on:** LAB-TERM-T2-P1, PROP-041-P7, PROP-039 G5, OOF-R3 Rust symmetry

---

## Acceptance Matrix

| Check | Result |
|-------|--------|
| New OOF-R9 edge runner: all R9A–R9H PASS | ✅ 21/21 PASS |
| `verify_t2_structural_size_relation.rb` still PASS | ✅ 52/52 PASS |
| `verify_oof_r3.rb` still PASS | ✅ 34/34 PASS |
| `verify_g5_recur.rb` still PASS | ✅ 18/18 PASS |
| Multi-recur both correct: no OOF-R9 | ✅ |
| Multi-recur one wrong: OOF-R9 fires | ✅ |
| Mixed correct/wrong: correct site does NOT suppress wrong-site OOF-R9 | ✅ |
| If-expr both branches correct: no OOF-R9 | ✅ |
| If-expr wrong else branch: OOF-R9 fires | ✅ (required IfExpr fix) |
| Nested arithmetic wrong recur: OOF-R9 fires | ✅ |
| OOF-R3 precedence unchanged (numeric → R3, not R9) | ✅ |
| OOF-R8 precedence unchanged (missing → R8, not R9) | ✅ |
| T1 syntactic_v0 unaffected | ✅ |
| No new canon OOF codes | ✅ confirmed |
| No igniter-lang canon files changed | ✅ confirmed |
| No VM/runtime files changed | ✅ confirmed |
| T2 is NOT a full termination proof | ✅ confirmed |

---

## Root Cause Fixed

**Bug:** `check_t2_callsite_in_expr` in `src/typechecker.rs` — `IfExpr` arm only walked
`cond`, not `then`/`else_block` bodies. A `recur()` call with the wrong accessor inside
an if-branch would silently pass OOF-R9.

**Fix:** Extended the `IfExpr` arm to walk `then.stmts`, `then.return_expr`,
`else_block.stmts`, `else_block.return_expr` — exactly mirroring `check_recur_in_expr`.

This was a Rust lab-only bug. The Ruby canon pipeline is not affected.

---

## Files Delivered

| File | Description |
|------|-------------|
| `igniter-lab/igniter-compiler/src/typechecker.rs` | IfExpr arm fix in `check_t2_callsite_in_expr` |
| `igniter-lab/igniter-compiler/fixtures/prop041_t2_structural_size_relation/t2r9_*.ig` | 5 new edge-case fixtures |
| `igniter-lab/igniter-compiler/verify_t2_oof_r9_edge_cases.rb` | 21-check edge hardening runner |
| `igniter-lab/lab-docs/lang/lab-term-t2-oof-r9-branch-and-multirecur-edge-hardening-v0.md` | Proof doc |
| `igniter-lab/.agents/work/cards/lang/LAB-TERM-T2-P2.md` | This card |
| `igniter-lab/.agents/portfolio-index.md` | Updated with entry 27 |

---

## Explicit Answers (Card Spec)

**Is OOF-R9 proven across multi-recur and branch expressions?**  
Yes — 21/21 PASS covers multi-recur (R9A-R9B), if-expression both-correct (R9C) and wrong-else (R9D), and nested arithmetic (R9E).

**Do correct T2 call sites still pass?**  
Yes — multi_recur_both_correct compiles clean (R9A); if_both_branches_correct compiles clean (R9C).

**Do mixed correct/wrong recur sites fail closed?**  
Yes — in `recur(items.next) + recur(items)`, the correct first site does NOT suppress OOF-R9 for the wrong second site (R9B).

**Is OOF-R8 and OOF-R3 precedence unchanged?**  
Yes — numeric dotted-path fires OOF-R3 (not OOF-R9); missing relation fires OOF-R8 (not OOF-R9) (R9G).

**Does Rust behavior still match PROP-041-P7?**  
Yes — `verify_t2_structural_size_relation.rb` 52/52 PASS; no regression found. Ruby canon uses a stateful `@t2_context` and instance-variable pattern; the Rust fix is structurally symmetric.

**Was any T3/full-termination/runtime authority created?**  
No. T2 is structural evidence with trust metadata. No runtime changes. No new OOF codes.

**Exact next route recommendation:**  
`LAB-TERM-T2` track is complete (P1 + P2). No further T2 hardening required.
Next meaningful work is **PROP-041 T3** (numeric measure expressions) — requires a new PROP
and experiment authorization.

---

## Fixtures Added

| Fixture | Tests |
|---------|-------|
| `t2r9_multi_recur_both_correct.ig` | `recur(items.next) + recur(items.next)` → PASS |
| `t2r9_multi_recur_one_wrong.ig` | `recur(items.next) + recur(items)` → OOF-R9 |
| `t2r9_if_both_branches_correct.ig` | if both branches `recur(items.next, n-1)` → PASS |
| `t2r9_if_wrong_else_branch.ig` | then correct, else `recur(items, n-1)` → OOF-R9 |
| `t2r9_nested_arith_wrong.ig` | `0 + recur(items)` → OOF-R9 |
