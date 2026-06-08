# Lab Doc: Compiler Liveness Calibrated Budget Diagnostics v0

**Card:** LAB-COMPILER-LIVENESS-P3
**Track:** lab-compiler-liveness-calibrated-budget-diagnostics-v0
**Route:** EXPERIMENTAL / LAB-ONLY / IMPLEMENTATION-PROOF
**Authority:** Lab evidence only. Not canon. Not production.
**Date:** 2026-06-08
**Depends:** LAB-COMPILER-LIVENESS-P1 (design), LAB-COMPILER-LIVENESS-P2 (instrumentation)
**Status:** Closed — E-COMPILER-BUDGET active, verify_liveness_p3.rb 38/38 PASS

---

## 1. Purpose

P3 converts the P2 observe-only instrumentation counters into calibrated hard budget
limits for the two highest-risk compiler passes. When a limit is exceeded, the compiler
emits `E-COMPILER-BUDGET` and exits with `status: "compiler_error"` — a clean JSON
output, not a panic or hang.

This is the first step toward the Covenant Postulate 14 requirement that every
repetition in the compiler itself belongs to a class with a verified contract.

---

## 2. Design Decisions

### 2.1 Which passes received hard limits?

| Pass | Mode | Limit | Env override |
|------|------|-------|-------------|
| `typechecker.infer_expr` | **fatal** | 1000 | `IGNITER_LIVENESS_BUDGET_TC_INFER` |
| `form_resolver.walk_expr` | **fatal** | 1000 | `IGNITER_LIVENESS_BUDGET_FR_WALK` |
| `emitter.lower_expr_for_targets` | observe-only | — | — |
| `emitter.build_pipeline` | observe-only | — | — |
| `parser.parse_import` | observe-only | — | — |

**Rationale:**
- `tc_infer` and `fr_walk` are the highest-risk passes (MEDIUM in P1 risk map). P2
  measured depth 200 for adversarial input, typical <10 for canon programs. Limit 1000
  is 5× the adversarial maximum — generous headroom, far above any canon input.
- Emitter and parser counters remain observe-only: P2 measured 0 depth across all
  fixtures. There is no calibration basis for an emitter budget. Setting an arbitrary
  tight limit would be unsound.

### 2.2 Fatal immediately or post-pass?

P3 uses **post-pass fatal**: when a limit is exceeded, the breach is recorded in a
thread-local `BUDGET_BREACHES` list and a stderr notice is emitted. Compilation
continues to termination. After all passes, `main.rs` checks for breaches and emits
`E-COMPILER-BUDGET` before the OOF/OK path.

**Why not abort mid-recursion?** Aborting requires changing call-site signatures (30+
sites for `infer_expr`) or using `longjmp`-style unwinding. The post-pass approach
preserves the non-signature-changing property established in P2 while still catching
the breach. The compiler terminates (ASTs are finite) — it just records the breach.

### 2.3 Why `status: "compiler_error"` not `status: "oof"`?

- `status: "oof"` means the source program violates a language rule (OOF-* code). The
  source program in the breach fixture is semantically valid Integer arithmetic.
- `status: "compiler_error"` means the compiler's own internal budget was exceeded.
- Using `oof` for a compiler-internal condition would conflate the four-way distinction
  established in P1 (source / compiler / harness / runtime).
- The diagnostic `E-COMPILER-BUDGET` is explicitly labeled `is_compiler_internal: true`
  and `is_source_program_fault: false`.

### 2.4 Is `E-COMPILER-BUDGET` lab-local?

Yes. Per Language Covenant CR-002, E-COMPILER-* codes are lab-local. They do not enter
the canon OOF vocabulary without a formal PROP + grammar review. The diagnostic carries
`authority: "lab_only_e_compiler_budget"` in its receipt.

---

## 3. Implementation

### 3.1 `liveness.rs` changes (P3 additions)

- Added `use std::cell::RefCell;`
- Added `BudgetBreach { counter, depth, limit }` struct
- Added `BUDGET_BREACHES: RefCell<Vec<BudgetBreach>>` thread-local
- Added `tc_infer_budget()` and `fr_walk_budget()` (default 1000, env-configurable)
- Updated `TcInferGuard::enter()` and `FrWalkGuard::enter()` to call `record_breach()`
  at `budget + 1` depth
- Extended `LivenessStats` with `budget_breaches`, `tc_infer_budget`, `fr_walk_budget`
- Extended `to_json()` with `budget_policy` and `breaches` keys
- Added `has_budget_breach()` helper

### 3.2 `main.rs` change (P3 new path)

After `collect_stats()`, before the OOF/OK check:

```
if liveness_stats.has_budget_breach() {
    emit { status: "compiler_error", diagnostics: [E-COMPILER-BUDGET, ...] }
    return Ok(false)
}
```

The budget breach path is independent of the OOF/OK path. Budget breach takes priority
(the typechecking result is unreliable after a depth limit was hit).

### 3.3 Fixtures added

| Fixture | Terms | Expected | Purpose |
|---------|-------|----------|---------|
| `liveness_depth_probe.ig` (P2) | 200 | `status: ok` | Under-limit baseline |
| `liveness_budget_breach.ig` | 1100 | `status: compiler_error` | Over-limit proof |

---

## 4. Empirical Data and Calibration

| Counter | Typical | Adversarial (P2) | Limit | Safety margin |
|---------|---------|-----------------|-------|---------------|
| `tc_infer_max_depth` | < 10 | 200 | **1000** | 5× over adversarial |
| `fr_walk_max_depth` | < 10 | 200 | **1000** | 5× over adversarial |
| `em_lower_max_depth` | 0 | 0 | observe-only | No basis |
| `em_pipeline_max_depth` | 0 | 0 | observe-only | No basis |
| `parse_import_max_steps` | 1 | 1 | observe-only | No basis |

The 5× margin means a program would need to be roughly 5× more deeply nested than
the most adversarial test case before hitting the budget. For `a + a + ... + a`:
- 200 terms → depth 200 (P2 adversarial, passes) ✓
- 1000 terms → depth 1000 (right at limit, would breach)
- 1100 terms → depth 1100 (breaches at depth 1001) ✓ tested

---

## 5. Receipt Format (P3 extended)

```json
{
  "liveness_instrumentation": {
    "kind":      "liveness_instrumentation",
    "authority": "lab_only_p2_instrumentation",
    "non_fatal": false,
    "counters": {
      "typechecker.infer_expr.max_depth": 1100,
      "form_resolver.walk_expr.max_depth": 1100,
      "emitter.lower_expr_for_targets.max_depth": 0,
      "emitter.build_pipeline.max_depth": 0,
      "parser.parse_import.max_steps": 1
    },
    "log_threshold": 100,
    "budget_policy": {
      "typechecker.infer_expr.max_depth": {
        "limit": 1000, "mode": "fatal",
        "env_override": "IGNITER_LIVENESS_BUDGET_TC_INFER"
      },
      "form_resolver.walk_expr.max_depth": {
        "limit": 1000, "mode": "fatal",
        "env_override": "IGNITER_LIVENESS_BUDGET_FR_WALK"
      },
      "emitter.lower_expr_for_targets.max_depth": { "mode": "observe_only" },
      "emitter.build_pipeline.max_depth":         { "mode": "observe_only" },
      "parser.parse_import.max_steps":            { "mode": "observe_only" }
    },
    "breaches": [
      {"counter": "typechecker.infer_expr.max_depth", "depth": 1001, "limit": 1000},
      {"counter": "form_resolver.walk_expr.max_depth", "depth": 1001, "limit": 1000}
    ],
    "p3_note": "E-COMPILER-BUDGET is now active for tc_infer and fr_walk (P3). ..."
  }
}
```

When `non_fatal: false`, the outer `status` is `"compiler_error"`.

---

## 6. Output Paths

| Condition | `status` | `diagnostics` |
|-----------|---------|---------------|
| Budget breach | `compiler_error` | `[E-COMPILER-BUDGET, ...]` |
| Source OOF | `oof` | OOF-* diagnostics |
| Parse error | `error` | parse errors |
| Clean | `ok` | `[]` |

Budget breach takes priority over OOF/OK: if both a budget breach and OOF conditions
are present, the budget breach output is emitted (OOF check is unreliable after budget
was exceeded).

---

## 7. Verify Results

```
ruby verify_liveness_p3.rb    38/38 PASS
ruby verify_liveness_p2.rb    25/25 PASS  (backward compat confirmed)
```

---

## 8. Authority and Boundary

```
authority:                     lab_only_p3_budget_diagnostics
E-COMPILER-BUDGET:             lab-local only (CR-002)
is_compiler_internal:          true
is_source_program_fault:       false
canon_impact:                  NONE
production_impact:             NONE
VM/runtime:                    NONE
igniter-lang files:            NONE
```

---

## 9. What P3 Does NOT Do

- No hard limits on emitter/parser counters (insufficient calibration data)
- No `E-COMPILER-CYCLE` detection (would require different instrumentation)
- No canon OOF promotion (PROP required per CR-002)
- No production/stable authority claimed
- No runtime execution or VM changes

---

## 10. Files

| File | Change |
|------|--------|
| `src/liveness.rs` | P3 budget extension: BudgetBreach, limits, BUDGET_BREACHES, to_json update |
| `src/main.rs` | E-COMPILER-BUDGET output path (before OOF/OK check) |
| `fixtures/liveness_budget_breach.ig` | NEW — 1100-term over-limit fixture |
| `verify_liveness_p3.rb` | NEW — 38-check proof script |
| `lab-docs/lang/lab-compiler-liveness-calibrated-budget-diagnostics-v0.md` | This doc |

---

## 11. Next Route (P4)

P4 should address:
1. Calibrate emitter/parser counters — create fixtures that exercise deep emitter
   recursion (deeply nested JSON pipeline) and multi-segment imports
2. Consider `E-COMPILER-CYCLE` for potential cycle-detection in form resolution
3. Consider whether `compiler_error` status should propagate to the compilation
   report file (currently only emitted to stdout)
4. Consider adjusting limits based on production program corpus (if/when available)

**P4 card should reference this doc and the P2 empirical baseline.**
