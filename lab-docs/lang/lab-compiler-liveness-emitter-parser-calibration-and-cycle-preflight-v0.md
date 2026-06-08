# Lab Doc: Compiler Liveness Emitter/Parser Calibration and Cycle Preflight v0

**Card:** LAB-COMPILER-LIVENESS-P4
**Track:** lab-compiler-liveness-emitter-parser-calibration-and-cycle-preflight-v0
**Route:** EXPERIMENTAL / LAB-ONLY / CALIBRATION-PREFLIGHT
**Authority:** Lab evidence only. Not canon. Not production.
**Date:** 2026-06-08
**Depends:** LAB-COMPILER-LIVENESS-P1, P2 (instrumentation), P3 (tc_infer/fr_walk budgets)
**Status:** Closed — 40/40 PASS, emitter/parser counters remain observe-only

---

## 1. Purpose

P3 left three counters as observe-only with "no calibration basis." P4 addresses this gap:

1. **Construct calibration fixtures** that exercise each counter to meaningful depths
2. **Measure actual counter values** and document empirical data
3. **Decide** whether fatal limits are justified (armed with actual fixture evidence)
4. **Preflight E-COMPILER-CYCLE** risk for form resolution
5. **Classify** sidecar behavior for `compiler_error` status

---

## 2. Calibration Findings

### 2.1 emitter.lower_expr_for_targets.max_depth

**Constructibility:** YES — requires a form declaration (`form (left) "+" (right)`) plus a many-term expression using the form operator. Each term adds one level of recursion.

**Calibration fixture:** `fixtures/liveness_emitter_form_lower.ig`
- 30-term form expression: `a + a + a + ... + a` (30 `a`s, left-associative)
- Form contract `Add` with `form (left) "+" (right) priority 5 associativity :left`
- Result: `em_lower_max_depth = 30`, `tc_infer_max_depth = 30`, `fr_walk_max_depth = 30`

**Formula:** N-term expression → depth = N for all three counters (em_lower mirrors tc_infer — same AST depth)

**Calibration table:**

| Fixture | Terms | em_lower | tc_infer | Status |
|---------|-------|----------|----------|--------|
| positive_forms.ig (P2) | 2 | 2 | 2 | ok |
| liveness_emitter_form_lower.ig | 30 | 30 | 30 | ok |
| liveness_depth_probe.ig (P2) | 200 | 200 | 200 | ok |
| liveness_budget_breach.ig (P3) | 1100 | n/a (breach) | 1101 | compiler_error |

**Key insight:** `lower_expr_for_targets` mirrors the depth of `tc_infer` and `fr_walk` because all three traverse the same AST structure. The P3 budget on `tc_infer` (limit=1000) therefore provides implicit coverage: any input deep enough to overflow `em_lower` would have already triggered the `tc_infer` budget breach first.

**Decision: remain observe-only.** The P3 tc_infer budget (limit=1000) implicitly bounds em_lower. A separate budget would be redundant and could never be triggered independently.

---

### 2.2 emitter.build_pipeline.max_depth

**Constructibility:** YES — requires a pipeline terminal operation (`sum`/`count`/`fold`/etc.) with nested `filter`/`map` operations, AND the terminal must be inside an `if_expr` branch.

**Why the if_expr requirement:** `build_pipeline` is called from `try_optimize_map_reduce`, which is called from `semantic_expr`. However, compute expressions at the top level are processed by `semantic_expr_for_compute`, which does NOT call `try_optimize_map_reduce` directly for pipeline terminals. Only when a pipeline terminal appears inside an `if_expr` (or a text stdlib call) is it processed by `semantic_expr`, which triggers the optimization.

**Calibration fixture:** `fixtures/liveness_emitter_pipeline_depth.ig`
- 9 nested filter operations inside `sum(...)` inside `if count(leads) > 0 { ... } else { ... }`
- Formula: N nested filter/map inside a terminal → `em_pipeline_max_depth = N + 1`
- Result: `em_pipeline_max_depth = 10`

**Calibration table:**

| Fixture | Nesting | em_pipeline | Status |
|---------|---------|-------------|--------|
| stdlib_extension.ig (baseline) | 1 (sum(filter)) | 2 | ok |
| liveness_emitter_pipeline_depth.ig | 9 (sum(filter^9)) | 10 | ok |

**Typical programs:** 2–5 levels of nesting. Deeply chained pipelines (`filter(filter(filter(...)))`) are unusual in real code. Even 20-level nesting would give depth=21, well within safe ranges.

**Decision: remain observe-only.** The pipeline recursion is bounded by the nesting depth of the source program, which is finite. Real programs rarely exceed 3–5 levels. No stack overflow risk at realistic depths. No fatal limit needed — if extreme nesting were seen in the wild, it would be a P5 item with actual measured data.

---

### 2.3 parser.parse_import.max_steps — STRUCTURAL BOUND FINDING

**Key P4 finding:** This counter is structurally bounded at 0–1 by the Igniter lexer design, regardless of import path length.

**Root cause — lexer merging:** `read_ident_or_keyword` in `lexer.rs` (lines 307–313) consumes dots when the next character is uppercase:

```rust
if ch == '.' {
    if let Some(next) = self.peek(1) {
        if next.is_ascii_uppercase() || (buf.starts_with("stdlib.IO") && ...) {
            buf.push(self.advance().unwrap()); // consume '.'
            continue;
        }
    }
    break;
}
```

Therefore `import Lang.Compiler.Liveness.Calibration.Parser` is lexed as a **single** `Ident("Lang.Compiler.Liveness.Calibration.Parser")` token. The `parse_import` loop sees no Dot tokens after consuming the first ident, so it runs exactly once (recording 1 step) and breaks.

**Consequence:** `parse_import_max_steps` can only ever be:
- `0` — no import statements in the file
- `1` — one or more import statements (any path, regardless of dot-segment count)

**Calibration fixture:** `fixtures/liveness_parser_import_steps.ig`
- Three import statements with multi-segment uppercase paths
- Result: `parse_import_max_steps = 1` (confirmed structural bound)

**Decision: remain observe-only.** The counter does not measure what its name implies (path segment depth). To get useful depth measurement for future work, the lexer would need to be modified to not merge dotted paths in imports, or the counter would need to count dots within the merged token. Neither change is in P4 scope. The counter is non-harmful and may be corrected in a future PROP. No fatal limit is appropriate since the structural maximum is 1.

---

## 3. E-COMPILER-CYCLE Risk Preflight

**What E-COMPILER-CYCLE would address:** A cycle would occur if the compiler's own recursion produced a loop — not just deep recursion (covered by P3 budgets) but an actual cycle where state `A` generates state `B` which generates state `A` again.

**Risk classification per subsystem:**

| Subsystem | Cycle risk | Rationale |
|-----------|-----------|-----------|
| `typechecker.infer_expr` | **LOW** | Traverses a finite typed AST; each recursive call descends to a strict child node. No back-edges possible. P3 depth budget already covers deep (non-cyclic) recursion. |
| `form_resolver.walk_expr` | **LOW** | Walks the typed AST looking for form-matching patterns. Form lowering produces function call nodes, not new form expressions. The emitter's `lower_expr_for_targets` descends into the produced JSON IR (also finite). No expansion loop. |
| `emitter.lower_expr_for_targets` | **LOW** | Descends through SemanticIR JSON (finite). Each call processes a strict sub-node. |
| `emitter.build_pipeline` | **LOW** | Unwraps nested `filter`/`map` calls. Each recursion processes the inner collection, which must be strictly smaller (fewer nesting levels). Cannot cycle. |
| `parser.parse_import` | **NONE** | Flat loop over tokens; not recursive. |

**Form recursion risk specifically:** Could Form A's body reference an operator that triggers Form B, which in turn triggers Form A? In the current Igniter grammar, forms match syntactic operator patterns (`(left) "+" (right)`) and lower them to regular function calls. The lowered form is a function call node — it cannot re-match as a form operator. There is no macro-expansion or form-calls-form mechanism. **Structural impossibility of form cycles in the current grammar.**

**Conclusion:** E-COMPILER-CYCLE instrumentation is NOT needed in P4. The existing P3 depth budgets already prevent infinite-depth non-progress for the highest-risk passes. True cycle detection (tracking visited nodes) would require different instrumentation (e.g., a `HashSet` of visited AST node identifiers per recursion chain) and is appropriate only if empirical evidence of cycles is found. No such evidence exists.

**P5 trigger condition:** If a future grammar change allows form bodies to reference form-matched operators, or if an infinite-recursion bug is discovered in any compiler pass, E-COMPILER-CYCLE instrumentation becomes relevant.

---

## 4. compiler_error Sidecar Behavior

**Current behavior (P3):** When `status: "compiler_error"` is emitted (budget breach), the output goes to stdout only. No `.compilation_report.json` sidecar file is written.

**Alternatives considered:**
1. Write sidecar with partial/unreliable compilation record → **REJECTED**: the sidecar represents the source program's compilation record. After a budget breach, the typechecking result is unreliable (the traversal was cut short). Writing an unreliable record is worse than not writing one.
2. Write sidecar with `compiler_error` status and no typed output → could cause downstream tools to mis-diagnose the source program as having a semantic error.
3. Write no sidecar → **CHOSEN**: correct for a compiler-internal diagnostic.

**Decision: keep stdout-only for `compiler_error`.** Document: downstream tools that expect a sidecar for every compilation should check for `status: "compiler_error"` and treat it as a compiler fault, not a source program fault. P5 can revisit if specific downstream tooling requirements emerge.

---

## 5. Calibration Summary Table

| Counter | P2 Max (all fixtures) | P4 Calibrated Max | Formula | Mode | P3 Budget |
|---------|----------------------|-------------------|---------|------|-----------|
| `typechecker.infer_expr.max_depth` | 200 | 30 (form fixture) | depth = N terms | **fatal** | 1000 |
| `form_resolver.walk_expr.max_depth` | 200 | 30 (form fixture) | depth = N terms | **fatal** | 1000 |
| `emitter.lower_expr_for_targets.max_depth` | 0 | **30** (form fixture) | depth = N terms | observe-only | n/a |
| `emitter.build_pipeline.max_depth` | 2 | **10** (pipeline fixture) | depth = N+1 (N ops) | observe-only | n/a |
| `parser.parse_import.max_steps` | 1 | **1** (structural bound) | always 0 or 1 (lexer) | observe-only | n/a |

**Revised observe-only rationale (post-P4):**

| Counter | P3 Rationale | P4 Updated Rationale |
|---------|-------------|---------------------|
| `em_lower_max_depth` | "P2 data shows 0 depth" | P4: calibrated to 30 (mirrors tc_infer); P3 budget implicitly bounds it |
| `em_pipeline_max_depth` | "P2 data shows 0 depth" | P4: calibrated to 10 (9-deep filter chain); bounded by source nesting; no stack risk |
| `parse_import_max_steps` | "P2 data shows max 1 step" | P4: **structurally bounded at 1** by lexer merging; counter cannot exceed 1 regardless of path depth |

---

## 6. Fixtures Written

| Fixture | Purpose | Expected Counters |
|---------|---------|-------------------|
| `fixtures/liveness_emitter_form_lower.ig` | em_lower calibration; 30-term form expression | em_lower=30, status=ok |
| `fixtures/liveness_emitter_pipeline_depth.ig` | em_pipeline calibration; 9 nested filters in sum | em_pipeline=10, status=ok |
| `fixtures/liveness_parser_import_steps.ig` | import steps structural bound proof | parse_import=1, status=ok |

---

## 7. Verify Results

```
ruby verify_liveness_p4.rb    40/40 PASS
ruby verify_liveness_p3.rb    38/38 PASS  (backward compat confirmed)
ruby verify_liveness_p2.rb    25/25 PASS  (backward compat confirmed)
```

---

## 8. Authority and Boundary

```
authority:                     lab_only_p4_calibration
E-COMPILER-CYCLE:              not implemented (risk classified LOW)
new_fatal_limits:              NONE
canon_impact:                  NONE
production_impact:             NONE
VM_change:                     NONE
igniter-lang files:            NONE
new_OOF_codes:                 NONE
```

---

## 9. What P4 Does NOT Do

- No new fatal limits (emitter/parser counters remain observe-only)
- No E-COMPILER-CYCLE instrumentation (risk is LOW; no evidence of actual cycles)
- No sidecar file written on `compiler_error` (stdout-only is correct)
- No canon OOF promotion
- No grammar changes
- No correction to `parse_import_max_steps` counter behavior (would require lexer change + PROP)

---

## 10. Files

| File | Change |
|------|--------|
| `fixtures/liveness_emitter_form_lower.ig` | NEW — em_lower calibration (30-term form expression) |
| `fixtures/liveness_emitter_pipeline_depth.ig` | NEW — em_pipeline calibration (9-deep filter chain) |
| `fixtures/liveness_parser_import_steps.ig` | NEW — import steps structural bound proof |
| `verify_liveness_p4.rb` | NEW — 40-check proof script |
| `lab-docs/lang/lab-compiler-liveness-emitter-parser-calibration-and-cycle-preflight-v0.md` | This doc |

---

## 11. Next Route (P5)

P5 candidates (data-driven, not assumed):
1. Revisit `parse_import_max_steps` if import path depth becomes a concern (would require lexer change)
2. Add E-COMPILER-CYCLE instrumentation if grammar changes allow form-calls-form patterns
3. Consider compiler_error sidecar if downstream tooling requirements emerge
4. Revisit em_lower or em_pipeline budgets if production corpus shows deeper nesting
5. Consider promoting any E-COMPILER-* diagnostic to canon if design is validated and formal PROP is approved
