# LAB-STDLIB-NUMERIC-FIXED-POINT-P1
**Lane:** governance / stdlib / numeric  
**Status:** CLOSED — SPLIT  
**Date:** 2026-06-12  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_numeric_fixed_point_p1.rb` — 40/40 PASS  
**Doc:** `igniter-lab/lab-docs/governance/lab-stdlib-numeric-fixed-point-readiness-v0.md`

---

## Goal

Determine the boundary between:
- What the fixed-point integer convention is (app-level working pattern)
- What belongs in stdlib (none yet, maybe later)
- What belongs in Decimal[N] work (separate track)
- What LAB-STDLIB-NUMERIC-P1 should cover (type-system question, orthogonal)

---

## Verdict: SPLIT

**A — ACCEPT (app convention, no stdlib):** Fixed-point Integer arithmetic is a working pattern for ML/graphics domains where Float is unavailable and Decimal[N] arithmetic is blocked. Scale factor `1000 = 1.0` is documented in neural_net and vector_math. Convention: add/subtract unchanged, multiply always `(a * b) / scale`, negate via `0 - x` pending LANG-PARSER-UNARY-MINUS-P1. No new stdlib entries required.

**B — HOLD (stdlib.math.fixed.* helpers):** No cross-scale demand. Both apps use scale=1000. Revisit when a second scale value appears or a cross-scale bug is documented at a call boundary.

**C — ROUTE (Decimal[N]):** `Decimal[N]` is NOT fixed-point Integer. Route: BK-P02/BK-P03 → LAB-STDLIB-DECIMAL-P1 → LANG-STDLIB-DECIMAL-OPERATOR-P1 (blocked on STAB-P4).

---

## Key Findings

- **`operator_type` returns Integer for all four arithmetic ops** — `+/-/*//` all produce `type_ir("Integer")`; no Decimal promotion.
- **`<` operator gap:** Ruby TC has `>` but NOT `<` in `operator_type`. `x < y` → OOF-TY0 "Unsupported operator: <". SigmoidApprox in `neural_net/activations.ig` uses `x < (0 - 2500)` — this is a confirmed Ruby TC gap. Route: LANG-STDLIB-NUMERIC-COMPARISON-P1.
- **`unary_op` gap confirmed (C-02):** `infer_expr` has no `when "unary_op"` arm. Workaround `0 - x` documented and in use (vector_math Vec2Negate, Vec3Negate).
- **No stdlib.math.fixed entries in inventory** — H-02 confirms.
- **No `Fixed[S]` type in TC source** — H-03 confirms.
- **scale=1000 aligned across neural_net and vector_math** — G-04 confirms.
- **Silent scale error (R1):** Missing `/ scale` after multiply compiles clean with no diagnostic. No type-level enforcement possible without `Fixed[S]` type.

---

## Proof Matrix (40/40)

| Section | Checks | Description |
|---|---|---|
| A: Integer Arithmetic Compiles | 6 | All four ops clean; operator_type SIR names; return Integer |
| B: Multiply-Normalize Pattern | 6 | Two-step / inline / dot product; * and / arms return Integer |
| C: Unary Minus Workaround | 4 | `0 - v` compiles; infer_expr no unary_op; call-graph helpers only |
| D: Neural Net Patterns | 6 | DenseLayer2x2; SigmoidApprox (> branch); scale/convention docs |
| E: Vector Math Patterns | 6 | Vec2Scale / Vec2Lerp / Vec3Cross; milli-units convention |
| F: Decimal Gap | 4 | Decimal[2] ops emit OOF; no Decimal in operator_type |
| G: Scale Boundary | 4 | Wrong-scale / missing-normalize compile clean; no enforcement |
| H: Closed Surfaces | 4 | No Float arithmetic; no stdlib.math.fixed; no Fixed[S]; no Decimal arms |
| **Total** | **40** | **40 PASS / 0 FAIL** |

---

## New Gap Discovered

**`<` operator absent from Ruby TC `operator_type`:** Only `>` is present. `x < y` → OOF-TY0 "Unsupported operator: <". Documented as D-02 finding. SigmoidApprox in neural_net uses `x < (0 - 2500)` — currently compiles only with the Rust TC (LAB-NEURAL-NET-BASELINE-P1 used Rust, so 85/85 passed; Ruby TC would fail this expression).

---

## Next Routes

1. **LAB-STDLIB-NUMERIC-P1** — `T: Numeric` type constraint (gates one-arg sum; orthogonal to fixed-point)
2. **LANG-STDLIB-DECIMAL-OPERATOR-P1** — Decimal[N] arithmetic +/-/*/== (blocked on STAB-P4)
3. **LANG-PARSER-UNARY-MINUS-P1** — `parse_unary` for `-` token (fixes `0 - x` workaround)
4. **LANG-STDLIB-NUMERIC-COMPARISON-P1** — (new gap) add `<`, `<=`, `>=` to `operator_type` in Ruby TC
5. **LAB-FIXED-POINT-CONVENTION-P2** — (demand-gated) stdlib.math.fixed helpers if second scale emerges

---

## Predecessors

- LAB-NEURAL-NET-BASELINE-P1 (NN-P03: fixed-point scale=1000 documented)
- LAB-DSA-BASELINE-P1 (vector_math milli-units pattern)
