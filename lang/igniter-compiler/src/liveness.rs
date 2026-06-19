// src/liveness.rs
// LAB-COMPILER-LIVENESS-P2/P3 — Recursion depth / step instrumentation + calibrated budgets.
//
// P2 contract (unchanged):
//   - Thread-local counters; RAII guards; no call-site signature changes.
//   - Log threshold warnings → stderr only; never mixed into stdout JSON.
//   - collect_stats() reads final maxima after all passes complete.
//
// P3 additions:
//   - Budget limits for typechecker.infer_expr and form_resolver.walk_expr (default 1000).
//   - Limits are configurable via env vars (see budget functions below).
//   - When a limit is exceeded: breach is recorded in BUDGET_BREACHES thread-local.
//   - Breach detection is non-destructive; compilation continues to completion.
//   - main.rs checks budget_breaches after all passes and emits E-COMPILER-BUDGET if breached.
//   - Emitter / parser counters remain observe-only (no fixture evidence for calibration).
//
// Authority: lab-only — not canon, not stable API.
// E-COMPILER-* codes are lab-local per Language Covenant CR-002.

use std::cell::{Cell, RefCell};

// ── Thread-local depth/step state ─────────────────────────────────────────

thread_local! {
    // typechecker.infer_expr — recursive AST type inference
    static TC_INFER_CUR:    Cell<usize> = Cell::new(0);
    static TC_INFER_MAX:    Cell<usize> = Cell::new(0);

    // form_resolver.walk_expr — recursive AST form walk
    static FR_WALK_CUR:     Cell<usize> = Cell::new(0);
    static FR_WALK_MAX:     Cell<usize> = Cell::new(0);

    // emitter.lower_expr_for_targets — recursive JSON IR descent (observe-only in P3)
    static EM_LOWER_CUR:    Cell<usize> = Cell::new(0);
    static EM_LOWER_MAX:    Cell<usize> = Cell::new(0);

    // emitter.build_pipeline — recursive pipeline chain unwrap (observe-only in P3)
    static EM_PIPE_CUR:     Cell<usize> = Cell::new(0);
    static EM_PIPE_MAX:     Cell<usize> = Cell::new(0);

    // parser.parse_import — flat loop steps per import declaration (observe-only in P3)
    static IMPORT_STEPS_CUR: Cell<usize> = Cell::new(0);
    static IMPORT_STEPS_MAX: Cell<usize> = Cell::new(0);

    // P3: budget breach records — one entry per breached counter (first breach only)
    static BUDGET_BREACHES: RefCell<Vec<BudgetBreach>> = RefCell::new(Vec::new());
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

// ── P3 Budget limits ───────────────────────────────────────────────────────

/// Hard budget limit for typechecker.infer_expr recursion depth.
/// Default 1000. Override with IGNITER_LIVENESS_BUDGET_TC_INFER.
/// P2 empirical data: typical <10, adversarial 200. 1000 = 5× headroom above adversarial.
pub fn tc_infer_budget() -> usize {
    std::env::var("IGNITER_LIVENESS_BUDGET_TC_INFER")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1000)
}

/// Hard budget limit for form_resolver.walk_expr recursion depth.
/// Default 1000. Override with IGNITER_LIVENESS_BUDGET_FR_WALK.
/// Same calibration as tc_infer (mirrors the same AST traversal pattern).
pub fn fr_walk_budget() -> usize {
    std::env::var("IGNITER_LIVENESS_BUDGET_FR_WALK")
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(1000)
}

// ── P3 Budget breach ───────────────────────────────────────────────────────

/// A single budget breach event: which counter exceeded, at what depth, what was the limit.
#[derive(Debug, Clone)]
pub struct BudgetBreach {
    /// Counter identifier (matches liveness_instrumentation.counters key)
    pub counter: String,
    /// Depth/step value at which the breach was first detected
    pub depth: usize,
    /// The configured budget limit that was exceeded
    pub limit: usize,
}

/// Record a budget breach in the thread-local breaches list.
/// Only records the first breach per counter (avoids duplicate entries on deeply nested calls).
fn record_breach(counter: &str, depth: usize, limit: usize) {
    BUDGET_BREACHES.with(|b| {
        let mut v = b.borrow_mut();
        if !v.iter().any(|x| x.counter == counter) {
            v.push(BudgetBreach {
                counter: counter.to_string(),
                depth,
                limit,
            });
        }
    });
}

// ── RAII depth guards ──────────────────────────────────────────────────────

// typechecker.infer_expr  [P3: fatal budget]
pub struct TcInferGuard;
impl TcInferGuard {
    #[inline]
    pub fn enter() -> Self {
        TC_INFER_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            TC_INFER_MAX.with(|m| if new > m.get() { m.set(new) });
            let thr = log_threshold();
            if new == thr + 1 {
                eprintln!(
                    "[LIVENESS-P2] typechecker.infer_expr: depth {} reached log threshold {}",
                    new, thr
                );
            }
            // P3 budget check
            let budget = tc_infer_budget();
            if new == budget + 1 {
                eprintln!(
                    "[LIVENESS-P3] E-COMPILER-BUDGET: typechecker.infer_expr depth {} exceeded limit {}",
                    new, budget
                );
                record_breach("typechecker.infer_expr.max_depth", new, budget);
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

// form_resolver.walk_expr  [P3: fatal budget]
pub struct FrWalkGuard;
impl FrWalkGuard {
    #[inline]
    pub fn enter() -> Self {
        FR_WALK_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            FR_WALK_MAX.with(|m| if new > m.get() { m.set(new) });
            let thr = log_threshold();
            if new == thr + 1 {
                eprintln!(
                    "[LIVENESS-P2] form_resolver.walk_expr: depth {} reached log threshold {}",
                    new, thr
                );
            }
            // P3 budget check
            let budget = fr_walk_budget();
            if new == budget + 1 {
                eprintln!(
                    "[LIVENESS-P3] E-COMPILER-BUDGET: form_resolver.walk_expr depth {} exceeded limit {}",
                    new, budget
                );
                record_breach("form_resolver.walk_expr.max_depth", new, budget);
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

// emitter.lower_expr_for_targets  [P3: observe-only — insufficient calibration data]
pub struct EmLowerGuard;
impl EmLowerGuard {
    #[inline]
    pub fn enter() -> Self {
        EM_LOWER_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            EM_LOWER_MAX.with(|m| if new > m.get() { m.set(new) });
            let thr = log_threshold();
            if new == thr + 1 {
                eprintln!(
                    "[LIVENESS-P2] emitter.lower_expr_for_targets: depth {} reached log threshold {}",
                    new, thr
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

// emitter.build_pipeline  [P3: observe-only — insufficient calibration data]
pub struct EmPipelineGuard;
impl EmPipelineGuard {
    #[inline]
    pub fn enter() -> Self {
        EM_PIPE_CUR.with(|d| {
            let new = d.get() + 1;
            d.set(new);
            EM_PIPE_MAX.with(|m| {
                if new > m.get() {
                    m.set(new)
                }
            });
            let thr = log_threshold();
            if new == thr + 1 {
                eprintln!(
                    "[LIVENESS-P2] emitter.build_pipeline: depth {} reached log threshold {}",
                    new, thr
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
pub fn record_import_step() {
    IMPORT_STEPS_CUR.with(|s| {
        let new = s.get() + 1;
        s.set(new);
        IMPORT_STEPS_MAX.with(|m| {
            if new > m.get() {
                m.set(new)
            }
        });
    });
}

/// Call before beginning a new import declaration to reset the per-import counter.
pub fn start_import() {
    IMPORT_STEPS_CUR.with(|s| s.set(0));
}

// ── Stats collection ───────────────────────────────────────────────────────

/// Snapshot of all observed maxima + P3 budget breach records.
/// Call after all compiler passes complete.
#[derive(Debug, Clone)]
pub struct LivenessStats {
    pub tc_infer_max_depth: usize,
    pub fr_walk_max_depth: usize,
    pub em_lower_max_depth: usize,
    pub em_pipeline_max_depth: usize,
    pub parse_import_max_steps: usize,
    pub log_threshold: usize,
    /// P3: budget limits in effect for this compilation
    pub tc_infer_budget: usize,
    pub fr_walk_budget: usize,
    /// P3: breach records — empty if no budget was exceeded
    pub budget_breaches: Vec<BudgetBreach>,
}

impl LivenessStats {
    /// Returns true if any hard-budget pass was breached.
    pub fn has_budget_breach(&self) -> bool {
        !self.budget_breaches.is_empty()
    }

    pub fn to_json(&self) -> serde_json::Value {
        let breaches_json: Vec<serde_json::Value> = self
            .budget_breaches
            .iter()
            .map(|b| {
                serde_json::json!({
                    "counter": b.counter,
                    "depth":   b.depth,
                    "limit":   b.limit,
                })
            })
            .collect();

        serde_json::json!({
            "kind":      "liveness_instrumentation",
            "authority": "lab_only_p2_instrumentation",
            "non_fatal": !self.has_budget_breach(),
            "counters": {
                "typechecker.infer_expr.max_depth":          self.tc_infer_max_depth,
                "form_resolver.walk_expr.max_depth":         self.fr_walk_max_depth,
                "emitter.lower_expr_for_targets.max_depth":  self.em_lower_max_depth,
                "emitter.build_pipeline.max_depth":          self.em_pipeline_max_depth,
                "parser.parse_import.max_steps":             self.parse_import_max_steps,
            },
            "log_threshold": self.log_threshold,
            // P3 budget policy
            "budget_policy": {
                "typechecker.infer_expr.max_depth": {
                    "limit": self.tc_infer_budget,
                    "mode":  "fatal",
                    "env_override": "IGNITER_LIVENESS_BUDGET_TC_INFER",
                    "calibration": "P2 empirical: typical<10, adversarial=200; limit=1000 is 5× headroom"
                },
                "form_resolver.walk_expr.max_depth": {
                    "limit": self.fr_walk_budget,
                    "mode":  "fatal",
                    "env_override": "IGNITER_LIVENESS_BUDGET_FR_WALK",
                    "calibration": "mirrors tc_infer (same AST traversal pattern)"
                },
                "emitter.lower_expr_for_targets.max_depth": {
                    "mode": "observe_only",
                    "reason": "P2 data shows 0 depth across all fixtures; no calibration basis"
                },
                "emitter.build_pipeline.max_depth": {
                    "mode": "observe_only",
                    "reason": "P2 data shows 0 depth across all fixtures; no calibration basis"
                },
                "parser.parse_import.max_steps": {
                    "mode": "observe_only",
                    "reason": "P2 data shows max 1 step; no meaningful threshold evidence"
                }
            },
            "breaches": breaches_json,
            // p3_note kept for backward compatibility with verify_liveness_p2.rb schema check
            "p3_note": "E-COMPILER-BUDGET is now active for tc_infer and fr_walk (P3). Emitter/parser limits are P4 work pending fixture calibration."
        })
    }
}

pub fn collect_stats() -> LivenessStats {
    let breaches = BUDGET_BREACHES.with(|b| b.borrow().clone());
    LivenessStats {
        tc_infer_max_depth: TC_INFER_MAX.with(|m| m.get()),
        fr_walk_max_depth: FR_WALK_MAX.with(|m| m.get()),
        em_lower_max_depth: EM_LOWER_MAX.with(|m| m.get()),
        em_pipeline_max_depth: EM_PIPE_MAX.with(|m| m.get()),
        parse_import_max_steps: IMPORT_STEPS_MAX.with(|m| m.get()),
        log_threshold: log_threshold(),
        tc_infer_budget: tc_infer_budget(),
        fr_walk_budget: fr_walk_budget(),
        budget_breaches: breaches,
    }
}
