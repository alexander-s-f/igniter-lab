# Card: LAB-COMPILER-LIVENESS-P4

**Track:** lab-compiler-liveness-emitter-parser-calibration-and-cycle-preflight-v0
**Route:** EXPERIMENTAL / LAB-ONLY / CALIBRATION-PREFLIGHT
**Status:** ✅ CLOSED — 2026-06-08
**Authority:** igniter-lab only; no canon impact; no production impact
**Depends:** LAB-COMPILER-LIVENESS-P1 (design), LAB-COMPILER-LIVENESS-P2 (instrumentation), LAB-COMPILER-LIVENESS-P3 (tc_infer/fr_walk budgets)

---

## Card Statement

Calibrate the three observe-only emitter/parser counters left by P3: construct fixtures that exercise each counter, measure actual counter values, and decide whether fatal limits are justified. Preflight E-COMPILER-CYCLE risk. Classify compiler_error sidecar behavior.

---

## Explicit Answers

### Q1: Can emitter.lower_expr_for_targets.max_depth be exercised by a fixture?

**Yes.** Requires: a form declaration with an infix operator (`form (left) "+" (right)`) plus a compute expression with many terms using that operator. Depth = number of terms.

Calibration data:
- Fixture `liveness_emitter_form_lower.ig` (30 terms) → depth = 30
- Formula: N terms → depth = N (same as tc_infer, mirrors AST depth)

### Q2: Does em_lower require its own fatal budget?

**No.** `em_lower` traverses the same AST as `tc_infer`. Any input deep enough to overflow em_lower would trigger the P3 tc_infer budget (limit=1000) first. A separate em_lower budget is redundant and cannot be independently triggered with the current instrumentation ordering.

### Q3: Can emitter.build_pipeline.max_depth be exercised?

**Yes, with a caveat.** `build_pipeline` is only called when a pipeline terminal (`sum`/`count`/`fold`/etc.) is processed via `semantic_expr`. This only happens when the terminal is inside an `if_expr` branch — top-level compute expressions use `semantic_expr_for_compute` which does NOT call `try_optimize_map_reduce`.

Calibration data:
- Fixture `liveness_emitter_pipeline_depth.ig` (9 nested filters inside sum inside if_expr) → depth = 10
- Formula: N nested filter/map inside terminal → depth = N + 1

### Q4: Does em_pipeline require its own fatal budget?

**No.** Pipeline nesting depth = source program nesting depth, which is finite and bounded by the source file. Typical programs: 2–5 levels. Maximum observed: 10 (adversarial calibration fixture). No stack overflow risk at realistic depths.

### Q5: Can parser.parse_import.max_steps exceed 1?

**No — structural bound.** The Igniter lexer merges dotted module paths into single tokens when characters after dots are uppercase (e.g., `A.B.C` → `Ident("A.B.C")`). The `parse_import` loop always runs exactly once per import statement regardless of path depth, recording 1 step. The counter is structurally bounded at {0, 1}.

Calibration data:
- Fixture `liveness_parser_import_steps.ig` (3 multi-segment imports) → parse_import_max_steps = 1
- This confirms the structural bound; the counter cannot be > 1 without lexer changes.

### Q6: Is E-COMPILER-CYCLE a real risk in the current compiler?

**No.** Risk classified LOW for all passes:
- `tc_infer` / `fr_walk`: traverse finite typed AST; each call descends to a strict child node
- `em_lower`: descends through finite SemanticIR JSON
- `em_pipeline`: unwraps strictly smaller nesting levels (cannot cycle)
- Forms cannot call other forms (lowering produces function call nodes, not form expressions)

No E-COMPILER-CYCLE instrumentation is needed in P4. P5 trigger: grammar change that allows form-calls-form patterns.

### Q7: Should compiler_error emit a sidecar .compilation_report.json?

**No — stdout-only is correct.** After a budget breach, typechecking is unreliable. Writing an unreliable compilation record would be worse than writing none. Downstream tools should check for `status: "compiler_error"` and treat it as a compiler fault. P5 can revisit if specific tooling requirements emerge.

### Q8: Were any new fatal limits added for emitter/parser counters?

**No.** All three observe-only counters remain observe-only. Now they have calibration evidence; the decision to keep them observe-only is justified by data, not by absence of data.

---

## Proof Matrix

| Section | Description | Checks |
|---------|-------------|--------|
| P4-A | Build | 1 |
| P4-B | em_lower calibration (30-term form fixture) | 5 |
| P4-C | em_pipeline calibration (9-deep filter chain) | 5 |
| P4-D | parse_import structural bound proof | 4 |
| P4-E | P3 regression — budget breach still fails closed | 3 |
| P4-F | P3 regression — 200-term probe under budget | 2 |
| P4-G | Canonical fixture regression | 4 |
| P4-H | Observe-only schema validation | 11 |
| P4-I | Closed-surface scan | 5 |
| **Total** | | **40** |

```
ruby verify_liveness_p4.rb    40/40 PASS
ruby verify_liveness_p3.rb    38/38 PASS  (backward compat confirmed)
ruby verify_liveness_p2.rb    25/25 PASS  (backward compat confirmed)
```

---

## Calibration Summary

| Counter | P4 Calibrated Max | Formula | Mode | Implicit bound |
|---------|-------------------|---------|------|----------------|
| `emitter.lower_expr_for_targets.max_depth` | 30 (30-term form) | depth = N terms | observe-only | tc_infer budget (1000) |
| `emitter.build_pipeline.max_depth` | 10 (9-deep filter chain) | depth = N+1 ops | observe-only | source nesting depth |
| `parser.parse_import.max_steps` | 1 (structural bound) | always ≤ 1 (lexer) | observe-only | lexer merges dotted paths |

---

## Key Technical Discoveries

1. **em_lower mirrors tc_infer depth** (same AST traversal pattern). P3 tc_infer budget provides implicit coverage.

2. **build_pipeline only triggered inside if_expr** (not at top-level compute). The `semantic_expr_for_compute` function used for top-level computes bypasses `try_optimize_map_reduce`.

3. **parse_import_max_steps is structurally bounded at 1** due to the lexer merging uppercase-dotted paths into single Ident tokens. This is a design consequence of the lexer, not a bug in the counter instrumentation. Correcting the measurement would require a lexer PROP.

---

## Files Written

| File | Change |
|------|--------|
| `fixtures/liveness_emitter_form_lower.ig` | NEW — em_lower calibration (30-term form expression) |
| `fixtures/liveness_emitter_pipeline_depth.ig` | NEW — em_pipeline calibration (9 filters in if_expr) |
| `fixtures/liveness_parser_import_steps.ig` | NEW — import steps structural bound proof |
| `verify_liveness_p4.rb` | NEW — 40-check proof script |
| `lab-docs/lang/lab-compiler-liveness-emitter-parser-calibration-and-cycle-preflight-v0.md` | NEW |

---

## Authority and Boundary

```
authority:                     lab_only_p4_calibration
E-COMPILER-CYCLE:              not implemented (risk classified LOW)
new_fatal_limits:              NONE
canon_impact:                  NONE
production_impact:             NONE
VM_change:                     NONE
igniter-lang files:            NONE
new_OOF_codes:                 NONE
grammar_change:                NONE
```

---

## Precondition Documents

- P1: `lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md`
- P2: `lab-docs/lang/lab-compiler-liveness-instrumentation-counters-v0.md`
- P3: `lab-docs/lang/lab-compiler-liveness-calibrated-budget-diagnostics-v0.md`

## Next Route

**LAB-COMPILER-LIVENESS-P5** — if any of:
- Grammar changes enable form-calls-form (→ E-COMPILER-CYCLE)
- Production corpus shows unexpected counter depths
- Downstream tooling needs compiler_error sidecar
- Formal PROP to promote E-COMPILER-BUDGET from lab-local to canon OOF code
