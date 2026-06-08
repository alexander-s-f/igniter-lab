# Card: LAB-COMPILER-LIVENESS-P3

**Track:** lab-compiler-liveness-calibrated-budget-diagnostics-v0
**Route:** EXPERIMENTAL / LAB-ONLY / IMPLEMENTATION-PROOF
**Status:** ✅ CLOSED — 2026-06-08
**Authority:** igniter-lab only; no canon impact; no production impact
**Depends:** LAB-COMPILER-LIVENESS-P1 (design), LAB-COMPILER-LIVENESS-P2 (instrumentation)

---

## Card Statement

Add calibrated hard budget limits on top of P2 instrumentation counters. When limits
are exceeded, emit `E-COMPILER-BUDGET` (lab-local) with `status: "compiler_error"` —
a clean JSON output that neither panics nor silently hangs.

---

## Explicit Answers

### Q1: Which compiler passes received fatal budget limits?

**Two passes: `typechecker.infer_expr` and `form_resolver.walk_expr` — both fatal at
depth 1000.**

Rationale: these are the MEDIUM-risk passes from P1. P2 measured depth 200 for the
adversarial 200-term fixture and <10 for canonical programs. Limit 1000 = 5× headroom
above the adversarial maximum. No canon program has been measured above depth 10.

### Q2: Which counters remain observe-only and why?

| Counter | Mode | Reason |
|---------|------|--------|
| `emitter.lower_expr_for_targets.max_depth` | observe-only | P2 measured 0 across all fixtures; no calibration basis for a limit |
| `emitter.build_pipeline.max_depth` | observe-only | P2 measured 0; same reason |
| `parser.parse_import.max_steps` | observe-only | P2 measured max 1 step; no meaningful threshold |

Setting an arbitrary tight limit without fixture evidence would be unsound and could
reject valid programs.

### Q3: Does P2 empirical data support the chosen limits?

Yes. P2 data:
- Typical depth: < 10 for canonical fixtures
- Adversarial depth: 200 for 200-term `a + a + ... + a`
- Limit 1000: never triggered by any known valid program; caught by 1100-term fixture

The 5× safety margin above the adversarial case makes the limit conservative enough
that normal programs are never affected, while still catching truly pathological inputs.

### Q4: Is pathological compiler non-progress now fail-closed?

**Yes, for the two instrumented recursive passes.** A program requiring depth >1000
in `infer_expr` or `walk_expr` will receive `status: "compiler_error"` with
`E-COMPILER-BUDGET` diagnostics. The compiler will not hang or overflow the stack.

Residual gaps: emitter/parser paths remain unbounded (observe-only). P4 addresses those
once calibration fixtures exist.

### Q5: Do normal programs remain accepted?

**Yes.** Verified:
- `add.ig`, `decimal_contract.ig`, `vendor_lead_pipeline.ig` → `status: ok`, `breaches: []`
- `liveness_depth_probe.ig` (200 terms, depth 200) → `status: ok` (200 < 1000)

### Q6: Does stdout JSON remain clean?

**Yes.** All output paths (ok, oof, compiler_error) emit valid JSON on stdout.
E-COMPILER-BUDGET stderr notices (from `eprintln!`) remain on stderr only. Verified by
P3-F check: stdout parses as JSON even on budget breach.

### Q7: Is `E-COMPILER-BUDGET` lab-local only?

**Yes.** Per Language Covenant CR-002, E-COMPILER-* codes are lab-local. The diagnostic
carries:
- `authority: "lab_only_e_compiler_budget"`
- `is_compiler_internal: true`
- `is_source_program_fault: false`

No canon OOF code was created. No grammar was changed.

### Q8: Was any canon OOF/public/stable/runtime authority created?

**No.** Changes confined to `igniter-lab/igniter-compiler/src/liveness.rs`,
`src/main.rs`, and fixtures. No `igniter-lang` files touched. No VM files touched.

### Q9: What is the next route?

**LAB-COMPILER-LIVENESS-P4**: calibrate emitter/parser counters once fixture evidence
exists. Candidates: deeply-nested JSON pipeline fixture (emitter), multi-segment import
chain fixture (parser). Also consider `E-COMPILER-CYCLE` and whether `compiler_error`
should be written to the compilation report sidecar file.

---

## Proof Matrix

| Section | Description | Checks |
|---------|-------------|--------|
| P3-A | Build | 1 |
| P3-B | P2 200-term probe remains ok | 4 |
| P3-C | 1100-term fixture → E-COMPILER-BUDGET | 8 |
| P3-D | Canonical regression | 6 |
| P3-E | Existing OOF unchanged | 3 |
| P3-F | Stdout JSON / stderr separation | 3 |
| P3-G | Receipt budget_policy + breaches schema | 5 |
| P3-H | Observe-only counters non-fatal | 4 |
| P3-I | Closed-surface scan | 4 |
| **Total** | | **38** |

```
ruby verify_liveness_p3.rb    38/38 PASS
ruby verify_liveness_p2.rb    25/25 PASS  (backward compat confirmed)
```

---

## Output Path Summary

| Condition | `status` |
|-----------|---------|
| Budget breach in tc_infer or fr_walk | `compiler_error` |
| Source language OOF | `oof` |
| Parse error | `error` |
| Clean compilation | `ok` |

Budget breach takes priority over OOF/OK.

---

## Files Written / Modified

| File | Change |
|------|--------|
| `src/liveness.rs` | P3 budget limits (BudgetBreach, tc/fr budgets, BUDGET_BREACHES, to_json extension) |
| `src/main.rs` | E-COMPILER-BUDGET output path inserted before OOF/OK check |
| `fixtures/liveness_budget_breach.ig` | NEW — 1100-term fixture (over limit=1000) |
| `verify_liveness_p3.rb` | NEW — 38-check proof script |
| `lab-docs/lang/lab-compiler-liveness-calibrated-budget-diagnostics-v0.md` | NEW |

---

## Authority and Boundary

```
authority:                     lab_only_p3_budget_diagnostics
E-COMPILER-BUDGET:             lab-local only (CR-002)
is_compiler_internal:          true
is_source_program_fault:       false
canon_impact:                  NONE
production_impact:             NONE
new_OOF_codes:                 NONE
grammar_change:                NONE
VM_change:                     NONE
```

---

## Precondition Documents

- P1: `lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md`
- P2: `lab-docs/lang/lab-compiler-liveness-instrumentation-counters-v0.md`

## Next Route

**LAB-COMPILER-LIVENESS-P4** — calibrate emitter/parser observe-only counters, consider
`E-COMPILER-CYCLE`, and decide whether `compiler_error` status should write a sidecar
compilation report. Reference this doc and P2 empirical data for calibration baseline.
