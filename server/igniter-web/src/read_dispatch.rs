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
        }
    }

    /// Override the authority reference (for tests that need a specific passport string).
    pub fn with_authority(mut self, authority_ref: impl Into<String>) -> Self {
        self.authority_ref = authority_ref.into();
        self
    }

    /// Execute the staged read for `plan`. Reads are idempotent *per query*, so the idempotency key
    /// folds a digest of the `plan` into the (optional) `req.correlation_id`. Without the plan
    /// digest, two DIFFERENT queries served on one host instance with the same/empty correlation id
    /// would collide on one key — the second read would replay the first's cached rows instead of
    /// executing its own query (e.g. an empty-account read returning a populated account's rows).
    /// Same correlation + same plan still replays safely; distinct plans never collide.
    pub async fn execute(&self, plan: &Value, req: &ServerRequest) -> StagedReadResult {
        let corr = req
            .correlation_id
            .clone()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "staged-read".to_string());
        let idem_key = format!("{corr}:{:016x}", plan_digest(plan));

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
