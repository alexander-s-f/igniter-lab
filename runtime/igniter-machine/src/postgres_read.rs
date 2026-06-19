//! Postgres-shaped read capability (LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2).
//!
//! The FIRST Postgres-shaped read executor — and deliberately **fake-adapter only**: no
//! `tokio-postgres`/`sqlx`/`diesel`, no DB, no network, no SQL executed. It proves the
//! *connector boundary and the safety gates* decided in the readiness packet
//! (`lab-docs/lang/lab-machine-postgres-capability-readiness-p1-v0.md`), not a live connection.
//!
//! ```text
//! EffectRequest.args = typed QueryPlan (NO SQL string, NO DB handle)
//!   → PostgresReadExecutor (host CapabilityExecutor)
//!       gates: raw-SQL refusal · source allowlist · read-only · op allowlist
//!              · field allowlist · row-limit clamp        (ALL before the adapter)
//!   → PostgresReadAdapter (allowlisted, parameterised query model — fake here)
//!   → EffectOutcome + receipt via the existing capability machinery (replay bypasses adapter)
//! ```
//!
//! This is the live promotion of the *shape* proven (mocked) by the `ExecuteQuery` /
//! `IO.StorageCapability` work — a contract emits a typed plan; the host owns the gates and the
//! (eventual) SQL template. The contract NEVER sees SQL, a connection, a pool, or a cursor.
//! Read-only: a mutating op is refused before the adapter is ever called.

use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

// ── Typed query plan (the intent a contract emits — never SQL) ─────────────────

/// One filter predicate. The field is allowlist-checked; the value is treated as a *bound
/// parameter* (never interpolated into SQL). v0 does not evaluate predicates in the fake adapter
/// — predicate evaluation is a separate, named slice. The op string is carried, not interpreted.
#[derive(Clone, Debug)]
pub struct QueryFilter {
    pub field: String,
    pub op: String,
    pub value: Value,
}

/// A typed read plan. The `source` is a logical table/view name resolved against the policy
/// allowlist (never a contract-supplied SQL identifier). `projection` empty = the full allowed
/// row. `op` defaults to `select`.
#[derive(Clone, Debug)]
pub struct QueryPlan {
    pub source: String,
    pub op: String,
    pub projection: Vec<String>,
    pub filters: Vec<QueryFilter>,
    pub limit: Option<i64>,
}

impl QueryPlan {
    /// Parse a plan from the effect args. Refuses a raw-SQL-shaped request structurally:
    /// the presence of a `sql` / `raw_sql` / `query` string is a hard error, NOT a plan.
    pub fn from_args(args: &Value) -> Result<QueryPlan, String> {
        for raw in ["sql", "raw_sql", "query"] {
            if args.get(raw).and_then(|v| v.as_str()).is_some() {
                return Err(format!("raw SQL refused (`{raw}`): contracts emit typed plans, not SQL"));
            }
        }
        // Plan may sit at the top level of args or under a `plan` key.
        let p = args.get("plan").unwrap_or(args);
        let source = p
            .get("source")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing `source`".to_string())?
            .to_string();
        let op = p.get("op").and_then(|v| v.as_str()).unwrap_or("select").to_string();
        let projection = p
            .get("projection")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
            .unwrap_or_default();
        let filters = p
            .get("filters")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|f| {
                        let field = f.get("field").and_then(|v| v.as_str())?.to_string();
                        let op = f.get("op").and_then(|v| v.as_str()).unwrap_or("eq").to_string();
                        let value = f.get("value").cloned().unwrap_or(Value::Null);
                        Some(QueryFilter { field, op, value })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let limit = p.get("limit").and_then(|v| v.as_i64());
        Ok(QueryPlan { source, op, projection, filters, limit })
    }

    /// All field names the plan touches (projection + filter fields) — the set the field
    /// allowlist must cover.
    fn referenced_fields(&self) -> Vec<String> {
        let mut out: Vec<String> = self.projection.clone();
        out.extend(self.filters.iter().map(|f| f.field.clone()));
        out
    }
}

/// Operations that mutate state. The read executor refuses any of these BEFORE the adapter is
/// called — a read capability can never write, even if the op were somehow allowlisted.
fn is_mutating_op(op: &str) -> bool {
    matches!(
        op.to_ascii_lowercase().as_str(),
        "insert" | "update" | "delete" | "upsert" | "merge" | "truncate" | "drop" | "alter"
            | "create" | "replace" | "write"
    )
}

// ── Host-owned read policy (the allowlist gates) ───────────────────────────────

/// The host-owned read policy. This is the schema/allowlist authority for v0 — hand-written
/// host config, NOT contract input and NOT live DB introspection. Everything a contract can read
/// is bounded here.
#[derive(Clone, Debug, Default)]
pub struct PostgresReadPolicy {
    pub allowed_sources: Vec<String>,
    /// Read ops the executor will serve (e.g. `select`). Mutating ops are refused regardless.
    pub allowed_ops: Vec<String>,
    /// Per-source field allowlist. A source with no entry can only be selected whole (empty
    /// projection, no filters); any named field then refuses.
    pub allowed_fields: HashMap<String, Vec<String>>,
    /// Hard server-side row cap. A plan limit above this is CLAMPED (not denied).
    pub row_limit: i64,
}

impl PostgresReadPolicy {
    pub fn new(row_limit: i64) -> Self {
        Self { allowed_sources: vec![], allowed_ops: vec!["select".to_string()], allowed_fields: HashMap::new(), row_limit }
    }
    pub fn allow_source(mut self, source: &str, fields: &[&str]) -> Self {
        self.allowed_sources.push(source.to_string());
        self.allowed_fields
            .insert(source.to_string(), fields.iter().map(|f| f.to_string()).collect());
        self
    }
    pub fn allow_ops(mut self, ops: &[&str]) -> Self {
        self.allowed_ops = ops.iter().map(|o| o.to_string()).collect();
        self
    }
}

// ── The adapter port (fake here; tokio-postgres later, behind an opt-in feature) ─

/// What the adapter returns. Maps to the documented outcome taxonomy:
/// `Rows` → succeeded (rows/empty), `Unavailable` → unknown (epistemic, no blind retry),
/// `Transient` → retryable (adapter KNOWS nothing partial happened), `QueryError` → permanent.
pub enum PostgresReadResult {
    Rows(Vec<Value>),
    Unavailable(String),
    Transient(String),
    QueryError(String),
}

/// The host-side read port. The real implementation (later, opt-in) will hold a connection pool
/// and render an allowlisted parameterised statement. The plan it receives is already
/// gate-checked and the limit already clamped.
#[async_trait]
pub trait PostgresReadAdapter: Send + Sync {
    async fn query(&self, plan: &QueryPlan, effective_limit: i64) -> PostgresReadResult;
}

// ── The executor ───────────────────────────────────────────────────────────────

/// A Postgres-shaped read capability. Implements `CapabilityExecutor`, so it composes with the
/// existing `run_effect` machinery (authority, idempotency, receipt-as-fact, replay) with NO new
/// primitive — exactly as `SparkCrmExecutor` composes the HTTP executor.
pub struct PostgresReadExecutor<A: PostgresReadAdapter> {
    capability_id: String,
    adapter: Arc<A>,
    policy: PostgresReadPolicy,
}

impl<A: PostgresReadAdapter> PostgresReadExecutor<A> {
    pub fn new(capability_id: &str, adapter: Arc<A>, policy: PostgresReadPolicy) -> Self {
        Self { capability_id: capability_id.to_string(), adapter, policy }
    }
}

#[async_trait]
impl<A: PostgresReadAdapter + 'static> CapabilityExecutor for PostgresReadExecutor<A> {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        // (0) Structural raw-SQL refusal + plan parse. A contract can never hand us SQL.
        let plan = match QueryPlan::from_args(&req.args) {
            Ok(p) => p,
            Err(e) if e.starts_with("raw SQL") => return EffectOutcome::permanent(&e),
            Err(e) => return EffectOutcome::permanent(&format!("malformed query plan: {e}")),
        };

        // (G1) source allowlist.
        if !self.policy.allowed_sources.iter().any(|s| s == &plan.source) {
            return EffectOutcome::denied(&format!("source not allowed: {}", plan.source));
        }

        // (read-only) a mutating op is refused before the adapter is ever touched.
        if is_mutating_op(&plan.op) {
            return EffectOutcome::denied(&format!("read-only: mutation refused ({})", plan.op));
        }

        // (G2) op allowlist.
        if !self.policy.allowed_ops.iter().any(|o| o == &plan.op) {
            return EffectOutcome::denied(&format!("op not allowed: {}", plan.op));
        }

        // (G3) field allowlist — projection + filter fields must be declared for the source.
        let referenced = plan.referenced_fields();
        if !referenced.is_empty() {
            match self.policy.allowed_fields.get(&plan.source) {
                Some(allowed) => {
                    if let Some(bad) = referenced.iter().find(|f| !allowed.contains(f)) {
                        return EffectOutcome::denied(&format!("forbidden field: {bad}"));
                    }
                }
                None => {
                    return EffectOutcome::denied(&format!("no field allowlist for source: {}", plan.source));
                }
            }
        }

        // (G4) row-limit clamp — NOT a denial. effective = min(requested, cap).
        let requested = plan.limit.unwrap_or(self.policy.row_limit);
        let effective_limit = requested.clamp(0, self.policy.row_limit);
        let clamped = requested > self.policy.row_limit;

        // Adapter call (the ONLY place the external port is reached). Everything above gated it.
        match self.adapter.query(&plan, effective_limit).await {
            PostgresReadResult::Rows(rows) => {
                let count = rows.len();
                let kind = if count == 0 { "empty" } else { "rows" };
                EffectOutcome::succeeded(json!({
                    "kind": kind,
                    "source": plan.source,
                    "rows": Value::Array(rows),
                    "count": count,
                    "effective_limit": effective_limit,
                    "row_limit_clamped": clamped,
                }))
            }
            PostgresReadResult::Unavailable(m) => EffectOutcome::unknown(&format!("adapter unavailable: {m}")),
            PostgresReadResult::Transient(m) => EffectOutcome::retryable(&format!("adapter transient: {m}")),
            PostgresReadResult::QueryError(m) => EffectOutcome::permanent(&format!("query error: {m}")),
        }
    }
}

// ── Fake adapter (proof only — no DB, no SQL, no dependency) ────────────────────

use std::sync::atomic::{AtomicU64, Ordering};

/// Scripted per-source behaviour for the fake adapter.
enum SourceBehavior {
    Table(Vec<Value>),
    Unavailable(String),
    Transient(String),
    QueryError(String),
}

/// An in-memory fake of a Postgres read adapter, keyed by allowlisted source name. It performs
/// NO SQL — it returns stored rows (applying projection-shaping + the effective limit) or a
/// scripted failure. Counts queries so idempotency/replay can be proven (a replayed effect must
/// NOT increment the count, because the executor is never re-entered on replay).
#[derive(Default)]
pub struct FakePostgresAdapter {
    sources: HashMap<String, SourceBehavior>,
    queries: AtomicU64,
}

impl FakePostgresAdapter {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn with_table(mut self, source: &str, rows: Vec<Value>) -> Self {
        self.sources.insert(source.to_string(), SourceBehavior::Table(rows));
        self
    }
    pub fn unavailable(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(source.to_string(), SourceBehavior::Unavailable(reason.to_string()));
        self
    }
    pub fn transient(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(source.to_string(), SourceBehavior::Transient(reason.to_string()));
        self
    }
    pub fn query_error(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(source.to_string(), SourceBehavior::QueryError(reason.to_string()));
        self
    }
    /// How many times the adapter actually ran a query (replay must keep this unchanged).
    pub fn query_count(&self) -> u64 {
        self.queries.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl PostgresReadAdapter for FakePostgresAdapter {
    async fn query(&self, plan: &QueryPlan, effective_limit: i64) -> PostgresReadResult {
        self.queries.fetch_add(1, Ordering::SeqCst);
        match self.sources.get(&plan.source) {
            Some(SourceBehavior::Unavailable(m)) => PostgresReadResult::Unavailable(m.clone()),
            Some(SourceBehavior::Transient(m)) => PostgresReadResult::Transient(m.clone()),
            Some(SourceBehavior::QueryError(m)) => PostgresReadResult::QueryError(m.clone()),
            Some(SourceBehavior::Table(rows)) => {
                // Apply projection-shaping (pure shaping, not predicate evaluation — v0 does NOT
                // evaluate filters here) and the clamped limit.
                let take = if effective_limit < 0 { 0 } else { effective_limit as usize };
                let shaped: Vec<Value> = rows
                    .iter()
                    .take(take)
                    .map(|row| {
                        if plan.projection.is_empty() {
                            row.clone()
                        } else {
                            let mut obj = serde_json::Map::new();
                            for f in &plan.projection {
                                if let Some(v) = row.get(f) {
                                    obj.insert(f.clone(), v.clone());
                                }
                            }
                            Value::Object(obj)
                        }
                    })
                    .collect();
                PostgresReadResult::Rows(shaped)
            }
            // An allowlisted source the fake simply has no data for → definite empty (not error).
            None => PostgresReadResult::Rows(vec![]),
        }
    }
}
