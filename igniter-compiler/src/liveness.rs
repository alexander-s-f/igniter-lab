// src/liveness.rs
// LAB-COMPILER-LIVENESS-P2 — Non-fatal recursion depth and step instrumentation.
//
// Design contract:
//   - ZERO effect on compilation output when depths are within log threshold.
//   - ZERO new rejection behavior; all compile results are unchanged.
//   - Thread-local counters: safe for single-threaded compiler use.
//   - RAII guards (DepthGuard impls Drop) cover all exit paths including panics.
//   - Threshold warnings go to stderr; they are NOT compiler diagnostics.
//   - collect_stats() reads final maxima after all passes complete.
//
// Usage in recursive functions:
//   let _g = crate::liveness::TcInferGuard::enter();  // depth auto-decrements on drop
//
// Usage in loop bodies:
//   crate::liveness::record_import_step();             // step-count only, no RAII needed
//
// Authority: lab-only — not canon, not stable API.
// P3 will convert these into E-COMPILER-BUDGET hard limits (separate card).

use std::cell::Cell;

// ── Thread-local depth/step state ─────────────────────────────────────────

thread_local! {
    // typechecker.infer_expr — recursive AST type inference
    static TC_INFER_CUR:    Cell<usize> = Cell::new(0);
    static TC_INFER_MAX:    Cell<usize> = Cell::new(0);

    // form_resolver.walk_expr — recursive AST form walk
    static FR_WALK_CUR:     Cell<usize> = Cell::new(0);
    static FR_WALK_MAX:     Cell<usize> = Cell::new(0);

    // emitter.lower_expr_for_targets — recursive JSON IR descent
    static EM_LOWER_CUR:    Cell<usize> = Cell::new(0);
    static EM_LOWER_MAX:    Cell<usize> = Cell::new(0);

    // emitter.build_pipeline — recursive pipeline chain unwrap
    static EM_PIPE_CUR:     Cell<usize> = Cell::new(0);
    static EM_PIPE_MAX:     Cell<usize> = Cell::new(0);

    // parser.parse_import — flat loop steps per import declaration
    static IMPORT_STEPS_CUR: Cell<usize> = Cell::new(0);
    static IMPORT_STEPS_MAX: Cell<usize> = Cell::new(0);
}

// ── Log threshold (non-fatal; stderr only) ────────────────────────────────

/// Threshold above which a depth crossing emits a stderr notice.
/// Default 100; override with IGNITER_LIVENESS_LOG_THRESHOLD.
pub fn log_threshold() -> usize {
    std::env::var("IGNITER_LIVENESS_LOG_THRESHOLD")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(100)
}

// ── RAII depth guards ──────────────────────────────────────────────────────

// typechecker.infer_expr
pub struct TcInferGuard;
impl TcInferGuard {
    #[inline]
    pub fn enter() -> Self {
        TC_INFER_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            TC_INFER_MAX.with(|m| if new > m.get() { m.set(new) });
            if new == log_threshold() + 1 {
                eprintln!(
                    "[LIVENESS-P2] typechecker.infer_expr: depth {} reached log threshold {}",
                    new, log_threshold()
                );
            }
        });
        TcInferGuard
    }
}
impl Drop for TcInferGuard {
    #[inline]
    fn drop(&mut self) {
        TC_INFER_CUR.with(|d| d.set(d.get().saturating_sub(1)));
    }
}

// form_resolver.walk_expr
pub struct FrWalkGuard;
impl FrWalkGuard {
    #[inline]
    pub fn enter() -> Self {
        FR_WALK_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            FR_WALK_MAX.with(|m| if new > m.get() { m.set(new) });
            if new == log_threshold() + 1 {
                eprintln!(
                    "[LIVENESS-P2] form_resolver.walk_expr: depth {} reached log threshold {}",
                    new, log_threshold()
                );
            }
        });
        FrWalkGuard
    }
}
impl Drop for FrWalkGuard {
    #[inline]
    fn drop(&mut self) {
        FR_WALK_CUR.with(|d| d.set(d.get().saturating_sub(1)));
    }
}

// emitter.lower_expr_for_targets
pub struct EmLowerGuard;
impl EmLowerGuard {
    #[inline]
    pub fn enter() -> Self {
        EM_LOWER_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            EM_LOWER_MAX.with(|m| if new > m.get() { m.set(new) });
            if new == log_threshold() + 1 {
                eprintln!(
                    "[LIVENESS-P2] emitter.lower_expr_for_targets: depth {} reached log threshold {}",
                    new, log_threshold()
                );
            }
        });
        EmLowerGuard
    }
}
impl Drop for EmLowerGuard {
    #[inline]
    fn drop(&mut self) {
        EM_LOWER_CUR.with(|d| d.set(d.get().saturating_sub(1)));
    }
}

// emitter.build_pipeline
pub struct EmPipelineGuard;
impl EmPipelineGuard {
    #[inline]
    pub fn enter() -> Self {
        EM_PIPE_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            EM_PIPE_MAX.with(|m| if new > m.get() { m.set(new) });
            if new == log_threshold() + 1 {
                eprintln!(
                    "[LIVENESS-P2] emitter.build_pipeline: depth {} reached log threshold {}",
                    new, log_threshold()
                );
            }
        });
        EmPipelineGuard
    }
}
impl Drop for EmPipelineGuard {
    #[inline]
    fn drop(&mut self) {
        EM_PIPE_CUR.with(|d| d.set(d.get().saturating_sub(1)));
    }
}

// ── Parser step counter (flat loop; no RAII needed) ───────────────────────

/// Call once per iteration of the parse_import loop to record a step.
/// Tracks per-import step count; resets at record_import_start().
pub fn record_import_step() {
    IMPORT_STEPS_CUR.with(|s| {
        let new = s.get() + 1;
        s.set(new);
        IMPORT_STEPS_MAX.with(|m| if new > m.get() { m.set(new) });
    });
}

/// Call before beginning a new import declaration to reset the per-import counter.
pub fn start_import() {
    IMPORT_STEPS_CUR.with(|s| s.set(0));
}

// ── Stats collection ───────────────────────────────────────────────────────

/// Snapshot of all observed maxima.  Call after all compiler passes complete.
#[derive(Debug, Clone)]
pub struct LivenessStats {
    /// Max recursion depth observed in typechecker.infer_expr
    pub tc_infer_max_depth: usize,
    /// Max recursion depth observed in form_resolver.walk_expr
    pub fr_walk_max_depth: usize,
    /// Max recursion depth observed in emitter.lower_expr_for_targets
    pub em_lower_max_depth: usize,
    /// Max recursion depth observed in emitter.build_pipeline
    pub em_pipeline_max_depth: usize,
    /// Max step count observed in any single parse_import loop execution
    pub parse_import_max_steps: usize,
    /// Log threshold (informational)
    pub log_threshold: usize,
}

impl LivenessStats {
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "kind": "liveness_instrumentation",
            "authority": "lab_only_p2_instrumentation",
            "non_fatal": true,
            "counters": {
                "typechecker.infer_expr.max_depth":          self.tc_infer_max_depth,
                "form_resolver.walk_expr.max_depth":         self.fr_walk_max_depth,
                "emitter.lower_expr_for_targets.max_depth":  self.em_lower_max_depth,
                "emitter.build_pipeline.max_depth":          self.em_pipeline_max_depth,
                "parser.parse_import.max_steps":             self.parse_import_max_steps,
            },
            "log_threshold": self.log_threshold,
            "p3_note": "Hard limits + E-COMPILER-BUDGET diagnostics are P3 work (separate card)"
        })
    }
}

pub fn collect_stats() -> LivenessStats {
    LivenessStats {
        tc_infer_max_depth:    TC_INFER_MAX.with(|m| m.get()),
        fr_walk_max_depth:     FR_WALK_MAX.with(|m| m.get()),
        em_lower_max_depth:    EM_LOWER_MAX.with(|m| m.get()),
        em_pipeline_max_depth: EM_PIPE_MAX.with(|m| m.get()),
        parse_import_max_steps: IMPORT_STEPS_MAX.with(|m| m.get()),
        log_threshold: log_threshold(),
    }
}
