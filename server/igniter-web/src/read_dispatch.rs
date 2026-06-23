//! Staged-read host for `ReadThen` dispatch (LAB-IGNITER-WEB-READTHEN-DISPATCH-P11).
//!
//! `StagedReadHost` wraps a `CapabilityExecutorRegistry` that contains a `PostgresReadExecutor`
//! (fake or real). `IgWebLoadedApp::dispatch_with_read` calls `StagedReadHost::execute` when it
//! encounters a `ReadThen { plan, then }` decision arm.
//!
//! Authority split (unchanged from P5/P6):
//! - Host owns: allowlist, row-limit clamp, adapter choice, DSN (never in `.ig`)
//! - App owns: logical query (QueryPlan value), continuation name, not-found Decision
//! - No app surface: capability id, scope, DSN, raw SQL, pool

use igniter_machine::backend::TBackend;
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode,
};
use igniter_server::protocol::ServerRequest;
use serde_json::Value;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

/// Digest of a query plan, used to scope the in-memory read idempotency key per query.
/// This key is only used for in-memory host receipts, so process-local stability is enough.
fn plan_digest(plan: &Value) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    serde_json::to_string(plan).unwrap_or_default().hash(&mut h);
    h.finish()
}

/// Result of executing a staged read, before the continuation is dispatched.
pub enum StagedReadResult {
    /// Rows serialized to JSON array string (may be "[]" for empty result set).
    Rows(String),
    /// Host denied the read before the adapter (allowlist / field / raw-SQL refusal).
    Denied(String),
    /// Transient or unknown host error — caller should return 503.
    HostError(String),
}

/// Operator-owned read host: holds the capability executor registry + receipts backend.
/// Build with `StagedReadHostBuilder` (or construct manually in tests).
pub struct StagedReadHost {
    registry: CapabilityExecutorRegistry,
    receipts: Arc<dyn TBackend>,
    /// The capability_id that the `PostgresReadExecutor` is registered under.
    capability_id: String,
    /// Operator-supplied authority reference (a passport or host-level scope token). Required by
    /// `run_effect_with_clock` — a missing authority is a preflight denial before the executor.
    authority_ref: String,
    /// Monotonic per-host counter that makes an uncorrelated read's receipt key unique per execution,
    /// so reads without an explicit client correlation never replay across HTTP requests (freshness).
    read_seq: AtomicU64,
}

impl StagedReadHost {
    pub fn new(
        registry: CapabilityExecutorRegistry,
        receipts: Arc<dyn TBackend>,
        capability_id: impl Into<String>,
    ) -> Self {
        Self {
            registry,
            receipts,
            capability_id: capability_id.into(),
            authority_ref: "host:read".to_string(),
            read_seq: AtomicU64::new(0),
        }
    }

    /// Override the authority reference (for tests that need a specific passport string).
    pub fn with_authority(mut self, authority_ref: impl Into<String>) -> Self {
        self.authority_ref = authority_ref.into();
        self
    }

    /// Execute the staged read for `plan`. Read replay is **opt-in via an explicit client
    /// `x-correlation-id`** (LAB-TODOAPP-API-READ-FRESHNESS-P23):
    ///
    /// - **With** a correlation id: the receipt key is `"{corr}:{plan_digest}"`, so a genuine client
    ///   retry of the same logical read (same correlation + same plan) replays the prior snapshot.
    ///   The plan digest keeps two *different* queries under one correlation from colliding (the P12 fix).
    /// - **Without** a correlation id: each execution gets a unique key (`"auto-{n}:{plan_digest}"` via
    ///   a monotonic per-host counter), so the read always runs fresh and never replays a stale result
    ///   across HTTP requests — e.g. `list → [] ; create ; list` returns the new row, not a replayed `[]`.
    pub async fn execute(&self, plan: &Value, req: &ServerRequest) -> StagedReadResult {
        let digest = plan_digest(plan);
        let idem_key = match req
            .correlation_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            Some(corr) => format!("{corr}:{digest:016x}"),
            None => {
                let n = self.read_seq.fetch_add(1, Ordering::Relaxed);
                format!("auto-{n}:{digest:016x}")
            }
        };

        let effect_req = EffectRequest {
            capability_id: self.capability_id.clone(),
            idempotency_key: idem_key,
            authority_ref: Some(self.authority_ref.clone()),
            args: plan.clone(),
        };

        match run_effect(&self.registry, &self.receipts, &effect_req, RunMode::Live).await {
            Err(e) => StagedReadResult::HostError(format!("{e:?}")),
            Ok(outcome) => match outcome.kind {
                OutcomeKind::Succeeded => {
                    let rows_json =
                        serde_json::to_string(&outcome.result["rows"]).unwrap_or_else(|_| {
                            // Fallback: the outcome.result itself is the rows array.
                            serde_json::to_string(&outcome.result)
                                .unwrap_or_else(|_| "[]".to_string())
                        });
                    StagedReadResult::Rows(rows_json)
                }
                OutcomeKind::Denied => {
                    let reason = outcome
                        .result
                        .get("error")
                        .and_then(|v| v.as_str())
                        .unwrap_or("read denied by host policy")
                        .to_string();
                    StagedReadResult::Denied(reason)
                }
                _ => {
                    StagedReadResult::HostError(format!("staged read returned {:?}", outcome.kind))
                }
            },
        }
    }
}
