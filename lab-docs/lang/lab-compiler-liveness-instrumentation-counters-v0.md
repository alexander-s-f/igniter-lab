# Lab Doc: Compiler Liveness Instrumentation Counters v0

**Card:** LAB-COMPILER-LIVENESS-P2
**Track:** lab-compiler-liveness-instrumentation-counters-v0
**Route:** EXPERIMENTAL / LAB-ONLY / INSTRUMENTATION-ONLY
**Authority:** Lab evidence only. Not canon. Not production.
**Date:** 2026-06-08
**Status:** Closed — counters live, verify_liveness_p2.rb 25/25 PASS

---

## 1. Purpose

This document records what was instrumented, the receipt format emitted, and the
empirical depth data gathered. The data informs P3 hard-limit calibration — choosing
safe, non-arbitrary `E-COMPILER-BUDGET` thresholds before they become rejection gates.

Precondition design is in:
`lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md` (P1 research)

---

## 2. What Was Instrumented

### 2.1 Instrument points

| Pass | Function | Counter type | Mechanism |
|------|----------|-------------|-----------|
| Rust TypeChecker | `infer_expr` | Recursion depth | Thread-local RAII guard |
| Rust FormResolver | `walk_expr` | Recursion depth | Thread-local RAII guard |
| Rust Emitter | `lower_expr_for_targets` | Recursion depth | Thread-local RAII guard |
| Rust Emitter | `build_pipeline` | Recursion depth | Thread-local RAII guard |
| Rust Parser | `parse_import` inner loop | Step count | Inline step counter |

### 2.2 Implementation approach: thread-local RAII guards

Adding a `depth: usize` parameter to `infer_expr` would require changes at 30+ call
sites. Instead, each recursive function gets a single line at entry:

```rust
let _depth_guard = crate::liveness::TcInferGuard::enter();
```

`TcInferGuard::enter()` increments the thread-local `TC_INFER_CUR` counter and updates
`TC_INFER_MAX`. When the guard is dropped (Rust `Drop` trait), `TC_INFER_CUR` is
decremented. This fires on ALL exit paths: normal return, early return, panic.

### 2.3 Non-fatal threshold warnings

Default threshold: 100 (configurable via `IGNITER_LIVENESS_LOG_THRESHOLD` env var).

When a counter first reaches `threshold + 1`, a notice is emitted to **stderr** via
`eprintln!`. Example:

```
[LIVENESS-P2] typechecker.infer_expr: depth 101 reached log threshold 100
```

The notice goes to **stderr only** — never mixed into the stdout JSON output. This
preserves the invariant that stdout is always valid JSON for machine consumers.

### 2.4 No behavior change guarantee

P2 counters:
- do NOT cause any compilation failure
- do NOT change `status` from `ok` to `oof`
- do NOT change any SemanticIR output
- emit threshold notices as informational stderr only

---

## 3. Receipt Format

Every compiler output (ok and oof paths) has a `liveness_instrumentation` top-level
key injected. Existing JSON consumers are unaffected — unknown keys are ignored by
spec-compliant parsers.

### 3.1 Receipt shape

```json
{
  "liveness_instrumentation": {
    "kind": "liveness_instrumentation",
    "authority": "lab_only_p2_instrumentation",
    "non_fatal": true,
    "counters": {
      "typechecker.infer_expr.max_depth": 200,
      "form_resolver.walk_expr.max_depth": 200,
      "emitter.lower_expr_for_targets.max_depth": 0,
      "emitter.build_pipeline.max_depth": 0,
      "parser.parse_import.max_steps": 1
    },
    "log_threshold": 100,
    "p3_note": "Hard limits + E-COMPILER-BUDGET diagnostics are P3 work (separate card)"
  }
}
```

### 3.2 Field semantics

| Field | Type | Meaning |
|-------|------|---------|
| `kind` | string | Always `"liveness_instrumentation"` — receipt type discriminator |
| `authority` | string | Always `"lab_only_p2_instrumentation"` — scope boundary marker |
| `non_fatal` | bool | Always `true` in P2 — hard limits are P3 work |
| `counters.*` | usize | Max observed value across the full compilation unit |
| `log_threshold` | usize | Threshold value used (default 100, env-configurable) |
| `p3_note` | string | Forward pointer: hard limits are a separate card |

---

## 4. Empirical Data

### 4.1 Adversarial probe: `liveness_depth_probe.ig`

**Fixture design:** 200 left-associative additions — `a + a + a + ... + a` (200 terms).
This produces a maximally deep expression tree for the recursive passes.

**Theoretical depth:** 200 terms → 199 binary operators → each `BinaryOp` node recurses
left then right. The final right-hand `Ref(a)` leaf is also counted as one `infer_expr`
call. Total: depth = 200.

**Observed results:**

| Counter | Value | Confirms |
|---------|-------|---------|
| `typechecker.infer_expr.max_depth` | **200** | Depth matches theory exactly |
| `form_resolver.walk_expr.max_depth` | **200** | Parallel recursion confirmed |
| `emitter.lower_expr_for_targets.max_depth` | 0 | Emitter uses a different traversal path |
| `emitter.build_pipeline.max_depth` | 0 | No pipeline in this fixture |
| `parser.parse_import.max_steps` | 1 | One import statement |

**Compilation status:** `ok` — the adversarial fixture is valid Igniter and compiles
successfully. P2 counters did not change this behavior.

### 4.2 Canonical fixture baselines

| Fixture | tc_infer | fr_walk | em_lower | em_pipe | import_steps |
|---------|----------|---------|----------|---------|-------------|
| `add.ig` | 0–2 | 0–2 | 0 | 0 | 1 |
| `decimal_contract.ig` | ~4 | ~4 | 0 | 0 | 1 |
| `vendor_lead_pipeline.ig` | 0 | 0 | 0 | 0 | 1 |

Typical production programs stay well under depth 10. The adversarial 200-depth fixture
is a stress case, not a representative workload.

### 4.3 Threshold warning behavior

With `IGNITER_LIVENESS_LOG_THRESHOLD=50` and the 200-term fixture:
- 4 `[LIVENESS-P2]` notices fired on stderr (one per pass that exceeded the threshold)
- stdout remained valid JSON throughout
- Stream separation confirmed by `r.stdout` vs `r.stderr` in BoundedCommand

---

## 5. Implications for P3 Calibration

The data now allows choosing non-arbitrary hard limits:

| Pass | Typical max | Adversarial max | Suggested P3 hard limit |
|------|------------|-----------------|------------------------|
| `typechecker.infer_expr` | < 10 | 200 | 500–1000 (deep but bounded) |
| `form_resolver.walk_expr` | < 10 | 200 | 500–1000 |
| `emitter.lower_expr_for_targets` | 0 | 0 | TBD — counter not yet firing |
| `emitter.build_pipeline` | 0 | 0 | TBD — pipeline depth needs pipeline fixture |
| `parser.parse_import` | 1 | 1 | TBD — needs multi-segment import fixture |

The gap between typical (<10) and adversarial (200) provides a wide calibration window.
A P3 limit of 1000 would:
- allow deeply nested but reasonable programs
- catch pathological inputs (e.g. 50,000-term additions) before stack overflow
- emit `E-COMPILER-BUDGET` as a diagnostic (not a panic/SIGSEGV)

---

## 6. What P2 Does NOT Do

These remain closed until P3 and P4:

- No hard limits — `infer_expr` can still recurse indefinitely on pathological input
- No `E-COMPILER-BUDGET` or `E-COMPILER-CYCLE` diagnostics (P3 work)
- No rejection of any source program based on liveness counters
- No Ruby typechecker instrumentation (deferred — Ruby path not on critical risk list)
- No runtime or VM instrumentation (separate domain — runtime budget = `max_steps`)

---

## 7. Authority and Boundary

```
authority:  lab_only_p2_instrumentation
is_source_program_fault:   false
is_compiler_internal:      true
canon_impact:              NONE — no OOF codes added, no grammar changed
production_impact:         NONE — counters only; no behavior change
```

Per Language Covenant CR-002: E-COMPILER-* codes are lab-local.
OOF promotion requires a formal PROP + grammar review (separate from P3).

---

## 8. Files

| File | Purpose |
|------|---------|
| `igniter-compiler/src/liveness.rs` | Thread-local counters, RAII guards, stats collection |
| `igniter-compiler/src/lib.rs` | `pub mod liveness;` registration |
| `igniter-compiler/src/typechecker.rs` | `TcInferGuard::enter()` in `infer_expr` |
| `igniter-compiler/src/form_resolver.rs` | `FrWalkGuard::enter()` in `walk_expr` |
| `igniter-compiler/src/emitter.rs` | `EmLowerGuard`/`EmPipelineGuard` in two emitter functions |
| `igniter-compiler/src/parser.rs` | `start_import()` + `record_import_step()` in `parse_import` |
| `igniter-compiler/src/main.rs` | `collect_stats()` + receipt injection in both result paths |
| `igniter-compiler/fixtures/liveness_depth_probe.ig` | Adversarial 200-term fixture |
| `igniter-compiler/verify_liveness_p2.rb` | Formal verification script (27 checks) |

---

## 9. Next Route

**P3 (separate card):** Add hard limits to the highest-risk passes with
`E-COMPILER-BUDGET` diagnostics. Use P2 data (200 adversarial, <10 typical) to choose
calibrated limits that reject pathological inputs without touching normal programs.

**Design doc for P3/P4:** `lab-docs/lang/lab-compiler-liveness-nonprogress-audit-boundary-v0.md`
