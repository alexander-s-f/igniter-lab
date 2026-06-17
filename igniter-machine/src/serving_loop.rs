//! ServingLoop — host-owned serving shell over the proven wire-to-effect entrypoint
//! (LAB-MACHINE-SERVING-LOOP-P12).
//!
//! The wire-to-effect contour is already proven one connection at a time
//! (`ingress::serve_once_effect`, P11). What was missing was the *host shape* that shows how
//! the machine "lives as a process" without inventing a background daemon:
//!
//! ```text
//! open local listener (caller — 127.0.0.1 only)
//!   → boot recovery once          (EffectOrchestrator::boot — P19 sweep)
//!   → accept/process N requests    (repeated ingress::serve_once_effect — P11)
//!   → host-owned tick cadence      (EffectOrchestrator::tick — drains due retries, P9)
//!   → report/observe stays queryable (facts remain the truth)
//!   → graceful stop after a bounded, deterministic condition (max_requests)
//! ```
//!
//! **The host owns the loop and the cadence; the machine only exposes functions.** This helper
//! adds NO new effect/coordination semantics: it calls `serve_once_effect` (unchanged) and
//! `EffectOrchestrator::{boot,tick}` (unchanged). It uses no `tokio::spawn`, owns no background
//! worker, and registers no hidden scheduler — when `run` resolves, nothing of the loop remains.
//!
//! Scope is loopback/local only: the caller passes a `TcpListener` it bound to `127.0.0.1`. This
//! helper never opens an address itself, so it cannot open a public one. This is the in-lab host
//! shell, NOT a deployment topology (no daemon, supervisor, systemd unit, or live vendor).

use crate::coordination::CoordinationHub;
use crate::errors::EngineError;
use crate::ingress::{serve_once_effect, EffectBridgeConfig, IngressRouter};
use crate::orchestrator::EffectOrchestrator;
use tokio::net::TcpListener;

/// How the host paces the loop. Cadence is explicit and the stop is bounded: there is no hidden
/// timer and no way to run unbounded.
#[derive(Debug, Clone)]
pub struct ServingPolicy {
    /// Deterministic stop: process exactly this many inbound connections, then return. This is
    /// the only exit — the loop can never run unbounded (the card's "no unkillable loop").
    pub max_requests: usize,
    /// Host-owned tick cadence: run one `EffectOrchestrator::tick` after every N served requests
    /// (drains due retry intents). `None` = the loop never ticks on its own; the host may still
    /// call `orch.tick()` itself between runs. There is NO background timer either way.
    pub tick_every: Option<usize>,
    /// Run one final `tick` after the last request, before returning — lets a single bounded run
    /// both serve and drain without a follow-up call.
    pub tick_on_stop: bool,
}

impl ServingPolicy {
    /// Serve exactly `n` requests, no auto-tick.
    pub fn serve(n: usize) -> Self {
        Self { max_requests: n, tick_every: None, tick_on_stop: false }
    }
    /// Tick after every `n` served requests (host-owned cadence).
    pub fn tick_every(mut self, n: usize) -> Self {
        self.tick_every = Some(n);
        self
    }
    /// Tick once more after the last request, before returning.
    pub fn tick_on_stop(mut self) -> Self {
        self.tick_on_stop = true;
        self
    }
}

/// A derived summary of what one `run` did. NOT a source of truth: the receipt / audit facts
/// remain authoritative (query them via `EffectOrchestrator::report` or `observability::observe`).
/// These are loop-iteration counters for tests and operators, not a side-log.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct ServingReport {
    pub booted: bool,
    pub requests_served: usize,
    pub ticks_run: usize,
    pub retries_drained: usize,
}

/// Host serving shell. Borrows the listener, router, hub, and effect-bridge config the caller
/// already wired for `serve_once_effect`, plus an `EffectOrchestrator` for boot/tick. Owns the
/// accept loop and the tick cadence; the machine still only exposes functions.
pub struct ServingLoop<'a> {
    pub listener: &'a TcpListener,
    pub router: &'a IngressRouter,
    pub hub: &'a CoordinationHub,
    pub cfg: &'a EffectBridgeConfig<'a>,
}

impl ServingLoop<'_> {
    /// boot recovery once → accept/process `policy.max_requests` connections (each through the
    /// proven `serve_once_effect` contour) → optional host-owned tick cadence → return a derived
    /// report.
    ///
    /// Processing is **sequential** (one connection at a time): this introduces no new concurrency
    /// and therefore cannot weaken the P18 atomic effect gate. Duplicate same-key requests still
    /// resolve through the unchanged duplicate-policy / single-flight path inside
    /// `serve_once_effect` — the loop performs at most one effect per idempotency key exactly as a
    /// hand-driven sequence of `serve_once_effect` calls would.
    pub async fn run(
        &self,
        orch: &EffectOrchestrator<'_>,
        policy: &ServingPolicy,
    ) -> Result<ServingReport, EngineError> {
        // boot recovery ONCE, before serving (P19 sweep of dangling prepared/unknown receipts).
        orch.boot().await?;
        let mut report = ServingReport { booted: true, ..Default::default() };

        while report.requests_served < policy.max_requests {
            // One inbound connection through the unchanged wire-to-effect contour.
            serve_once_effect(self.listener, self.router, self.hub, self.cfg)
                .await
                .map_err(|e| EngineError::IOError(e.to_string()))?;
            report.requests_served += 1;

            if let Some(n) = policy.tick_every {
                if n > 0 && report.requests_served % n == 0 {
                    let drained = orch.tick().await?;
                    report.ticks_run += 1;
                    report.retries_drained += drained.len();
                }
            }
        }

        if policy.tick_on_stop {
            let drained = orch.tick().await?;
            report.ticks_run += 1;
            report.retries_drained += drained.len();
        }

        Ok(report)
    }
}
