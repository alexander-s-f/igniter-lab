# Card: LAB-COMPILER-LIVENESS-P2

**Track:** lab-compiler-liveness-instrumentation-counters-v0
**Route:** EXPERIMENTAL / LAB-ONLY / INSTRUMENTATION-ONLY
**Status:** ✅ CLOSED — 2026-06-08
**Authority:** igniter-lab only; no canon impact; no production impact

---

## Card Statement

Add non-fatal liveness instrumentation counters to the highest-risk compiler passes,
collect empirical recursion/step depth data, and emit a compact instrumentation
receipt without changing compilation behavior or introducing hard limits.

---

## Explicit Answers to Card Questions

### Q1: Which functions were instrumented?

| Pass | Function | Counter | Mechanism |
|------|----------|---------|-----------|
| Rust TypeChecker | `infer_expr` | `tc_infer_max_depth` | Thread-local RAII guard (`TcInferGuard`) |
| Rust FormResolver | `walk_expr` (static) | `fr_walk_max_depth` | Thread-local RAII guard (`FrWalkGuard`) |
| Rust Emitter | `lower_expr_for_targets` | `em_lower_max_depth` | Thread-local RAII guard (`EmLowerGuard`) |
| Rust Emitter | `build_pipeline` | `em_pipeline_max_depth` | Thread-local RAII guard (`EmPipelineGuard`) |
| Rust Parser | `parse_import` inner loop | `parse_import_max_steps` | Inline step counter |

Ruby typechecker deferred — not on critical risk list (Ruby path raises SystemStackError
on stack overflow, which is fail-fast, not silent hang).

### Q2: Why thread-local RAII guards instead of threading `depth: usize`?

`infer_expr` is called at 30+ sites. Threading a parameter would require changing
every call site signature and every caller — a large, noisy diff with no behavior gain.
Thread-local RAII guard: one line per instrumented function (`let _g = XxxGuard::enter();`).
Rust's `Drop` trait handles decrement on ALL exit paths automatically (normal return,
early return, panic).

### Q3: What is the receipt format?

```json
{
  "liveness_instrumentation": {
    "kind": "liveness_instrumentation",
    "authority": "lab_only_p2_instrumentation",
    "non_fatal": true,
    "counters": {
      "typechecker.infer_expr.max_depth": <usize>,
      "form_resolver.walk_expr.max_depth": <usize>,
      "emitter.lower_expr_for_targets.max_depth": <usize>,
      "emitter.build_pipeline.max_depth": <usize>,
      "parser.parse_import.max_steps": <usize>
    },
    "log_threshold": <usize>,
    "p3_note": "Hard limits + E-COMPILER-BUDGET diagnostics are P3 work (separate card)"
  }
}
```

Injected as a top-level key in BOTH ok and oof compiler outputs. Backward-compatible —
existing JSON consumers ignore unknown keys.

### Q4: How are threshold warnings handled?

Default threshold: 100 (env: `IGNITER_LIVENESS_LOG_THRESHOLD`).

When a counter first reaches `threshold + 1`:
```
[LIVENESS-P2] typechecker.infer_expr: depth 101 reached log threshold 100
```

Goes to **stderr via `eprintln!`**. Never mixed into stdout JSON. This preserves the
invariant that stdout is always valid JSON for machine consumers.

### Q5: What is the adversarial fixture?

`fixtures/liveness_depth_probe.ig` — 200 left-associative additions.

200 terms → 199 binary operators → `infer_expr` depth = 200 (confirmed empirically).
Compilation status: `ok` — the fixture is valid Igniter. P2 counters did not change
behavior.

### Q6: What empirical data was gathered?

| Counter | Typical (canonical) | Adversarial (200-term) |
|---------|--------------------|-----------------------|
| `tc_infer_max_depth` | 0–4 | **200** |
| `fr_walk_max_depth` | 0–4 | **200** |
| `em_lower_max_depth` | 0 | 0 (different traversal path) |
| `em_pipeline_max_depth` | 0 | 0 (no pipeline in fixture) |
| `parse_import_max_steps` | 1 | 1 (one import) |

### Q7: Does P2 change any compilation result?

**No.** P2 is strictly non-fatal:
- No source program is rejected because of P2 counters
- OOF fixtures remain OOF (tested: `loops_and_recursion.ig` pre-existing OOF-R3)
- OK fixtures remain OK (tested: add, decimal_contract, vendor_lead_pipeline)
- Counter data collected silently; threshold notices on stderr only

---

## Acceptance Criteria (all met)

| Criterion | Status | Evidence |
|-----------|--------|---------|
| [A1] Existing proof suites still pass | ✅ | 3 canonical fixtures: status=ok, no regression |
| [A2] Adversarial deep fixture records high depth but does NOT change behavior | ✅ | liveness_depth_probe: tc=200, fr=200, status=ok |
| [A3] Receipt gives enough data to choose P3 hard limits | ✅ | Typical <10, adversarial 200 — calibration window documented |
| [A4] Non-fatal — OOF fixtures still return oof | ✅ | loops_and_recursion: status=oof, receipt present |
| [A5] Stderr separation — threshold warnings on stderr, JSON on stdout only | ✅ | r.stdout valid JSON; r.stderr has [LIVENESS-P2] notices |
| [A6] Receipt injected on BOTH ok and oof paths | ✅ | Verified both paths in main.rs |

---

## Verification

```
ruby verify_liveness_p2.rb
25/25 PASS
```

Sections:
- P2-A: Build (1 check)
- P2-B: Adversarial probe (5 checks)
- P2-C: Canonical regression (9 checks — 3 fixtures × 3 checks each)
- P2-D: OOF receipt injection (3 checks)
- P2-E: Stderr separation (3 checks)
- P2-F: Receipt schema validation (4 checks — kind/authority/counters/fields)

---

## Files Written / Modified

| File | Change |
|------|--------|
| `igniter-compiler/src/liveness.rs` | NEW — thread-local counters, RAII guards, stats |
| `igniter-compiler/src/lib.rs` | Added `pub mod liveness;` |
| `igniter-compiler/src/typechecker.rs` | `TcInferGuard::enter()` at top of `infer_expr` |
| `igniter-compiler/src/form_resolver.rs` | `FrWalkGuard::enter()` at top of `walk_expr` |
| `igniter-compiler/src/emitter.rs` | `EmLowerGuard`/`EmPipelineGuard` in two functions |
| `igniter-compiler/src/parser.rs` | `start_import()` + `record_import_step()` in `parse_import` |
| `igniter-compiler/src/main.rs` | `collect_stats()` + receipt injection in both result paths |
| `igniter-compiler/fixtures/liveness_depth_probe.ig` | NEW — adversarial 200-term fixture |
| `igniter-compiler/verify_liveness_p2.rb` | NEW — formal verify script (27 checks) |
| `lab-docs/lang/lab-compiler-liveness-instrumentation-counters-v0.md` | NEW — this lab doc |

---

## Authority and Boundary

```
authority:                 lab_only_p2_instrumentation
is_source_program_fault:   false
is_compiler_internal:      true
canon_impact:              NONE
production_impact:         NONE
new_OOF_codes:             NONE
grammar_change:            NONE
```

Covenant CR-002: E-COMPILER-* codes are lab-local. OOF promotion requires PROP + review.

---

## Precondition Design (P1)

`lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md`

---

## Next Route

**P3 (hard limits + E-COMPILER-BUDGET diagnostics):**
- Choose P3 limits using P2 data: typical <10, adversarial 200
- Suggested limits: 500–1000 for infer_expr/walk_expr (large gap from 200)
- Emit `E-COMPILER-BUDGET` as non-fatal diagnostic (then make fatal in P4)
- P3 card should be dispatched separately; reference P1 design doc for gate spec

**Closed in P2:**
- Runtime instrumentation (separate domain — runtime budget = `max_steps`)
- Ruby typechecker instrumentation (fail-fast SystemStackError, not silent hang)
- Hard limits (P3)
- E-COMPILER-* promotion to canon (PROP required)
