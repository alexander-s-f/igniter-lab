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

use crate::read_materialize::{build_dataset_meta, materialize_rows, ProjectionSpec};
use igniter_machine::backend::TBackend;
use igniter_machine::capability::{
    run_effect, CapabilityExecutorRegistry, EffectRequest, OutcomeKind, RunMode,
};
use igniter_machine::postgres_read::PostgresReadPolicy;
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

/// Result of executing a **typed** staged read (LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6), before
/// the continuation is dispatched. The typed crossing is a strict superset of `StagedReadResult`: it carries
/// the rows as a structured `serde_json` array (records, not a `rows_json : String`) plus the `DatasetMeta`
/// sidecar, and adds one outcome the stringly path cannot have — `SchemaMismatch`, the host's own promise
/// violation when its rows fail to materialize as the declared `Collection[<AppRow>]`.
///
/// Kept a SEPARATE enum from `StagedReadResult` on purpose: the existing `rows_json` loop
/// (`dispatch_with_read`) is untouched, so every pre-P6 continuation that takes `input rows_json : String`
/// stays green. Selecting this path per-continuation (from the compiled IR) is the named P7 follow-on.
#[derive(Debug)]
pub enum TypedReadResult {
    /// Materialized, total + typed rows (`Value::Array` of records) + the `DatasetMeta` provenance sidecar.
    /// Cross `rows` and `meta` as sibling continuation inputs; the VM's `from_json` materializes
    /// `Collection[<AppRow>]` + `DatasetMeta`.
    Rows { rows: Value, meta: Value },
    /// Host denied the read before the adapter (allowlist / field / raw-SQL refusal) → 403.
    Denied(String),
    /// Transient or unknown host error → 503.
    HostError(String),
    /// The host fetched rows but could NOT honor them as the declared `Collection[<AppRow>]` (a row was
    /// missing a projected field or carried the wrong scalar kind). The host broke its own promise — a
    /// gateway-level fault (P3 §5 maps it to 502), surfaced BEFORE continuation dispatch so no partial app
    /// response is ever produced.
    SchemaMismatch(String),
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
    /// The host read policy (schema authority) for the registered `PostgresReadExecutor`, when known
    /// (LAB-IGNITER-DATA-PROJECTION-BOOT-RECONCILIATION-P7). Needed to derive a `ProjectionSpec` for a typed
    /// continuation directly from a `ReadThen` plan in the runner contour. `None` keeps the pre-P7 surface —
    /// the typed routing then fails closed rather than guessing a schema.
    read_policy: Option<PostgresReadPolicy>,
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
            read_policy: None,
        }
    }

    /// Override the authority reference (for tests that need a specific passport string).
    pub fn with_authority(mut self, authority_ref: impl Into<String>) -> Self {
        self.authority_ref = authority_ref.into();
        self
    }

    /// Attach the host read policy (the schema authority) so the typed `ReadThen` routing can build a
    /// `ProjectionSpec` for a continuation directly from its plan (P7). The policy is host-owned config,
    /// never contract input — the same authority the registered `PostgresReadExecutor` already enforces.
    pub fn with_read_policy(mut self, policy: PostgresReadPolicy) -> Self {
        self.read_policy = Some(policy);
        self
    }

    /// Build the `ProjectionSpec` for a `ReadThen` plan from the stored read policy: the plan's `source`
    /// + `projection` resolved against the host field-kinds. `None` if no policy is attached or the plan
    /// names no `source` — the caller fails the typed crossing closed rather than projecting blind.
    pub fn projection_spec_for(&self, plan: &Value) -> Option<ProjectionSpec> {
        let policy = self.read_policy.as_ref()?;
        let source = plan.get("source").and_then(|v| v.as_str())?;
        let projection: Vec<String> = plan
            .get("projection")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();
        Some(ProjectionSpec::from_policy(policy, source, &projection))
    }

    /// Is the plan's `source` allowlisted by the attached read policy? The typed routing reconciles schema
    /// drift only for a source the host actually types — an unknown/denied source is the executor's 403 to
    /// make (in `execute_typed`), not a drift false-positive from the default-`Text` field kinds.
    pub fn source_allowlisted(&self, plan: &Value) -> bool {
        match (
            self.read_policy.as_ref(),
            plan.get("source").and_then(|v| v.as_str()),
        ) {
            (Some(policy), Some(source)) => policy.allowed_sources.iter().any(|s| s == source),
            _ => false,
        }
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
    /// The read idempotency key for `plan` under `req` — the freshness/replay policy shared by the stringly
    /// and typed read paths (extracted so both stay byte-identical). With an explicit client correlation id
    /// the key is `"{corr}:{plan_digest}"` (a genuine retry replays the snapshot); without one each call gets
    /// a unique `"auto-{n}:{plan_digest}"` so reads always run fresh.
    fn idem_key_for(&self, plan: &Value, req: &ServerRequest) -> String {
        let digest = plan_digest(plan);
        match req
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
        }
    }

    pub async fn execute(&self, plan: &Value, req: &ServerRequest) -> StagedReadResult {
        let idem_key = self.idem_key_for(plan, req);

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

    /// Execute the staged read, then **materialize the rows to the typed projection** instead of stringifying
    /// them (LAB-IGNITER-DATA-PROJECTION-TYPED-ROW-CROSSING-P6). The host reshapes the already-typed executor
    /// rows against `spec` (the host schema authority's field-kinds for the projected columns) so that what
    /// crosses to the continuation is a total + typed `Collection[<AppRow>]` (`from_json` materializes it) plus
    /// a `DatasetMeta` sidecar. The materialization gate runs BEFORE any continuation dispatch:
    ///
    /// - `Succeeded` + rows align to `spec` → `Rows { rows, meta }`;
    /// - `Succeeded` but a row is missing a field / has the wrong scalar kind → `SchemaMismatch` (the host
    ///   broke its own promise — never a partial `.ig` response);
    /// - `Denied` / transient stay exactly as the stringly path (403 / 503).
    ///
    /// The replay/freshness key is identical to [`Self::execute`]. The existing `rows_json` path is untouched.
    pub async fn execute_typed(
        &self,
        plan: &Value,
        req: &ServerRequest,
        spec: &ProjectionSpec,
    ) -> TypedReadResult {
        let effect_req = EffectRequest {
            capability_id: self.capability_id.clone(),
            idempotency_key: self.idem_key_for(plan, req),
            authority_ref: Some(self.authority_ref.clone()),
            args: plan.clone(),
        };

        match run_effect(&self.registry, &self.receipts, &effect_req, RunMode::Live).await {
            Err(e) => TypedReadResult::HostError(format!("{e:?}")),
            Ok(outcome) => match outcome.kind {
                OutcomeKind::Succeeded => {
                    // The executor hands typed serde rows under `rows`, with `count`/`row_limit_clamped`/`source`
                    // provenance (postgres_read.rs `succeeded` json). Reshape them to the typed projection.
                    let rows = outcome.result["rows"]
                        .as_array()
                        .cloned()
                        .unwrap_or_default();
                    let count = outcome.result["count"]
                        .as_i64()
                        .unwrap_or(rows.len() as i64);
                    let truncated = outcome.result["row_limit_clamped"]
                        .as_bool()
                        .unwrap_or(false);
                    let source = outcome.result["source"].as_str().unwrap_or("").to_string();
                    match materialize_rows(&rows, spec) {
                        Ok(rows) => TypedReadResult::Rows {
                            rows,
                            meta: build_dataset_meta(&source, count, truncated),
                        },
                        Err(e) => TypedReadResult::SchemaMismatch(e),
                    }
                }
                OutcomeKind::Denied => {
                    let reason = outcome
                        .result
                        .get("error")
                        .and_then(|v| v.as_str())
                        .unwrap_or("read denied by host policy")
                        .to_string();
                    TypedReadResult::Denied(reason)
                }
                _ => TypedReadResult::HostError(format!("staged read returned {:?}", outcome.kind)),
            },
        }
    }
}
