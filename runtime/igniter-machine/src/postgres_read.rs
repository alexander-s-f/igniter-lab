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

/// One filter predicate. The field is allowlist-checked; values are treated as *bound parameters*
/// (never interpolated into SQL). P11 supports `eq`/`in`/`gt`/`gte`/`lt`/`lte`: `value` carries the
/// scalar for `eq`/range, `values` carries the list for `in`. The op is validated (kind + shape)
/// before any adapter work.
#[derive(Clone, Debug)]
pub struct QueryFilter {
    pub field: String,
    pub op: String,
    pub value: Value,
    pub values: Vec<Value>,
}

/// One `ORDER BY` clause. `field` is allowlist-checked; `dir` is normalized to `asc`/`desc`.
#[derive(Clone, Debug)]
pub struct QueryOrder {
    pub field: String,
    pub dir: String,
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
    pub order_by: Vec<QueryOrder>,
    pub limit: Option<i64>,
}

impl QueryPlan {
    /// Parse a plan from the effect args. Refuses a raw-SQL-shaped request structurally:
    /// the presence of a `sql` / `raw_sql` / `query` string is a hard error, NOT a plan.
    pub fn from_args(args: &Value) -> Result<QueryPlan, String> {
        for raw in ["sql", "raw_sql", "query"] {
            if args.get(raw).and_then(|v| v.as_str()).is_some() {
                return Err(format!(
                    "raw SQL refused (`{raw}`): contracts emit typed plans, not SQL"
                ));
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
        let op = p
            .get("op")
            .and_then(|v| v.as_str())
            .unwrap_or("select")
            .to_string();
        let projection = p
            .get("projection")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();
        let filters = p
            .get("filters")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|f| {
                        let field = f.get("field").and_then(|v| v.as_str())?.to_string();
                        let op = f
                            .get("op")
                            .and_then(|v| v.as_str())
                            .unwrap_or("eq")
                            .to_string();
                        let value = f.get("value").cloned().unwrap_or(Value::Null);
                        let values = f
                            .get("values")
                            .and_then(|v| v.as_array())
                            .cloned()
                            .unwrap_or_default();
                        Some(QueryFilter {
                            field,
                            op,
                            value,
                            values,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let order_by = p
            .get("order_by")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|o| {
                        let field = o.get("field").and_then(|v| v.as_str())?.to_string();
                        let dir = o
                            .get("dir")
                            .and_then(|v| v.as_str())
                            .unwrap_or("asc")
                            .to_ascii_lowercase();
                        Some(QueryOrder { field, dir })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let limit = p.get("limit").and_then(|v| v.as_i64());
        Ok(QueryPlan {
            source,
            op,
            projection,
            filters,
            order_by,
            limit,
        })
    }

    /// All field names the plan touches (projection + filter + order_by fields) — the set the field
    /// allowlist must cover.
    fn referenced_fields(&self) -> Vec<String> {
        let mut out: Vec<String> = self.projection.clone();
        out.extend(self.filters.iter().map(|f| f.field.clone()));
        out.extend(self.order_by.iter().map(|o| o.field.clone()));
        out
    }
}

/// Operations that mutate state. The read executor refuses any of these BEFORE the adapter is
/// called — a read capability can never write, even if the op were somehow allowlisted.
fn is_mutating_op(op: &str) -> bool {
    matches!(
        op.to_ascii_lowercase().as_str(),
        "insert"
            | "update"
            | "delete"
            | "upsert"
            | "merge"
            | "truncate"
            | "drop"
            | "alter"
            | "create"
            | "replace"
            | "write"
    )
}

// ── P11: typed predicate + order policy ────────────────────────────────────────

/// The supported filter ops. `eq` is the default; `in` takes a list; the four range ops take a scalar.
fn is_range_op(op: &str) -> bool {
    matches!(op, "gt" | "gte" | "lt" | "lte")
}

/// Which ops a host-declared field kind permits (the v0 matrix). Json/Array carry no predicates.
fn kind_allows_op(kind: PostgresReadValueKind, op: &str) -> bool {
    use PostgresReadValueKind::*;
    match (kind, op) {
        (Json, _) | (Array, _) => false,
        (_, "eq") => true, // every scalar kind supports equality
        (Text, "in") | (Integer, "in") | (Boolean, "in") => true,
        (Integer, o) | (Timestamp, o) if is_range_op(o) => true, // range: integer + timestamp
        _ => false,
    }
}

/// Which kinds may be ordered (v0): Text (lexicographic), Integer, Timestamp.
fn kind_allows_order(kind: PostgresReadValueKind) -> bool {
    matches!(
        kind,
        PostgresReadValueKind::Text
            | PostgresReadValueKind::Integer
            | PostgresReadValueKind::Timestamp
    )
}

/// Validate every predicate + order clause against the field kinds and policy bounds — BEFORE any
/// adapter work. Returns a stable error string for a `PermanentFailure` (malformed/over-broad plan).
fn validate_predicates(
    plan: &QueryPlan,
    policy: &PostgresReadPolicy,
    kinds: &HashMap<String, PostgresReadValueKind>,
) -> Result<(), String> {
    for f in &plan.filters {
        let kind = kinds.get(&f.field).copied().unwrap_or_default();
        if !kind_allows_op(kind, &f.op) {
            return Err(format!(
                "op `{}` not allowed for field `{}` ({:?})",
                f.op, f.field, kind
            ));
        }
        if f.op == "in" {
            if f.values.is_empty() {
                return Err(format!(
                    "`in` on `{}` requires a non-empty `values`",
                    f.field
                ));
            }
            if f.values.len() > policy.max_in_values {
                return Err(format!(
                    "`in` on `{}` exceeds max {} values",
                    f.field, policy.max_in_values
                ));
            }
        } else if is_range_op(&f.op) && f.value.is_null() {
            return Err(format!(
                "range `{}` on `{}` requires a `value`",
                f.op, f.field
            ));
        }
    }
    if plan.order_by.len() > policy.max_order_by {
        return Err(format!(
            "order_by exceeds max {} clauses",
            policy.max_order_by
        ));
    }
    for o in &plan.order_by {
        if o.dir != "asc" && o.dir != "desc" {
            return Err(format!("order_by dir must be asc|desc, got `{}`", o.dir));
        }
        let kind = kinds.get(&o.field).copied().unwrap_or_default();
        if !kind_allows_order(kind) {
            return Err(format!(
                "order_by not allowed for field `{}` ({:?})",
                o.field, kind
            ));
        }
    }
    Ok(())
}

/// Compare two JSON values for the fake evaluator: numbers numerically, bools as bools, otherwise a
/// string fallback (stable + total). `None` only on a NaN number compare (not reachable for JSON).
fn cmp_values(a: &Value, b: &Value) -> Option<std::cmp::Ordering> {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.as_f64()?.partial_cmp(&y.as_f64()?),
        (Value::Bool(x), Value::Bool(y)) => Some(x.cmp(y)),
        (Value::String(x), Value::String(y)) => Some(x.cmp(y)),
        _ => Some(a.to_string().cmp(&b.to_string())),
    }
}

/// Does row value `a` satisfy filter `f` (fake evaluator)? Unsupported ops were already refused.
fn row_matches_filter(a: &Value, f: &QueryFilter) -> bool {
    use std::cmp::Ordering::*;
    match f.op.as_str() {
        "eq" => cmp_values(a, &f.value) == Some(Equal),
        "in" => f.values.iter().any(|v| cmp_values(a, v) == Some(Equal)),
        "gt" => cmp_values(a, &f.value) == Some(Greater),
        "gte" => matches!(cmp_values(a, &f.value), Some(Greater) | Some(Equal)),
        "lt" => cmp_values(a, &f.value) == Some(Less),
        "lte" => matches!(cmp_values(a, &f.value), Some(Less) | Some(Equal)),
        _ => false,
    }
}

// ── Host-owned read policy (the allowlist gates) ───────────────────────────────

/// How an allowlisted field is decoded into a JSON row value (P10). This is HOST policy — the
/// schema authority — NOT contract input and NOT DB introspection. The contract still emits only a
/// typed `QueryPlan`; it never names SQL casts or DB types. `Text` is the default for any field
/// without a declared kind (so untyped `allow_source` keeps the old all-text behaviour).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum PostgresReadValueKind {
    #[default]
    Text,
    Integer,
    Boolean,
    /// `json` / `jsonb` decoded to a `serde_json::Value` (object or array).
    Json,
    /// date/time rendered as a lossless string (RFC3339-ish), never an epoch number.
    Timestamp,
    /// arbitrary-precision `numeric` kept as a String — NEVER a lossy `f64`.
    DecimalString,
    /// v0 narrow support: a JSON/JSONB array field decoded to a `Value::Array`. Native PG arrays
    /// (`int[]`) are deferred — see the proof doc.
    Array,
}

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
    /// Per-source field DECODE kind (P10). A field absent here decodes as `Text` (back-compat).
    pub field_kinds: HashMap<String, HashMap<String, PostgresReadValueKind>>,
    /// Hard server-side row cap. A plan limit above this is CLAMPED (not denied).
    pub row_limit: i64,
    /// Max length of an `in` value list (P11). A longer list is a permanent failure before adapter.
    pub max_in_values: usize,
    /// Max number of `order_by` clauses (P11).
    pub max_order_by: usize,
}

impl PostgresReadPolicy {
    pub fn new(row_limit: i64) -> Self {
        Self {
            allowed_sources: vec![],
            allowed_ops: vec!["select".to_string()],
            allowed_fields: HashMap::new(),
            field_kinds: HashMap::new(),
            row_limit,
            max_in_values: 100,
            max_order_by: 3,
        }
    }
    /// Override the `in`-list and `order_by`-clause bounds (P11).
    pub fn with_predicate_limits(mut self, max_in_values: usize, max_order_by: usize) -> Self {
        self.max_in_values = max_in_values;
        self.max_order_by = max_order_by;
        self
    }
    /// All declared field decode kinds for a source (empty = every field decodes as `Text`).
    pub fn source_field_kinds(&self, source: &str) -> HashMap<String, PostgresReadValueKind> {
        self.field_kinds.get(source).cloned().unwrap_or_default()
    }
    /// Allowlist a source + its fields, all decoded as `Text` (the pre-P10 behaviour, unchanged).
    pub fn allow_source(mut self, source: &str, fields: &[&str]) -> Self {
        self.allowed_sources.push(source.to_string());
        self.allowed_fields.insert(
            source.to_string(),
            fields.iter().map(|f| f.to_string()).collect(),
        );
        self
    }
    /// Allowlist a source + its fields WITH a per-field decode kind (P10). Populates BOTH the
    /// allowlist gate and the decode map, so the gate and the typing stay in one host declaration.
    pub fn allow_source_typed(
        mut self,
        source: &str,
        fields: &[(&str, PostgresReadValueKind)],
    ) -> Self {
        self.allowed_sources.push(source.to_string());
        self.allowed_fields.insert(
            source.to_string(),
            fields.iter().map(|(f, _)| f.to_string()).collect(),
        );
        self.field_kinds.insert(
            source.to_string(),
            fields.iter().map(|(f, k)| (f.to_string(), *k)).collect(),
        );
        self
    }
    pub fn allow_ops(mut self, ops: &[&str]) -> Self {
        self.allowed_ops = ops.iter().map(|o| o.to_string()).collect();
        self
    }
    /// The decode kind for `source.field`, defaulting to `Text` (back-compat for untyped sources).
    pub fn field_kind(&self, source: &str, field: &str) -> PostgresReadValueKind {
        self.field_kinds
            .get(source)
            .and_then(|m| m.get(field))
            .copied()
            .unwrap_or_default()
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

/// The host-side read port. The real implementation holds a connection and renders an allowlisted
/// parameterised statement. The plan it receives is already gate-checked (incl. typed-predicate
/// validation) and the limit clamped; `kinds` maps every field of the source to its host-declared
/// decode kind (P10/P11) — used by the real adapter to cast/bind/decode projection, filter, and
/// order fields. A field absent from the map decodes as `Text`. The fake adapter already carries
/// typed `serde_json::Value` rows and ignores `kinds`.
#[async_trait]
pub trait PostgresReadAdapter: Send + Sync {
    async fn query(
        &self,
        plan: &QueryPlan,
        effective_limit: i64,
        kinds: &HashMap<String, PostgresReadValueKind>,
    ) -> PostgresReadResult;
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
        Self {
            capability_id: capability_id.to_string(),
            adapter,
            policy,
        }
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
        if !self
            .policy
            .allowed_sources
            .iter()
            .any(|s| s == &plan.source)
        {
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
                    return EffectOutcome::denied(&format!(
                        "no field allowlist for source: {}",
                        plan.source
                    ));
                }
            }
        }

        // Source field decode kinds from host policy (P10/P11; Text where unspecified).
        let kinds = self.policy.source_field_kinds(&plan.source);

        // (G3.5) typed predicate + order validation (P11) — malformed/over-broad plan is permanent,
        // refused BEFORE the adapter is reached.
        if let Err(e) = validate_predicates(&plan, &self.policy, &kinds) {
            return EffectOutcome::permanent(&format!("invalid predicate: {e}"));
        }

        // (G4) row-limit clamp — NOT a denial. effective = min(requested, cap).
        let requested = plan.limit.unwrap_or(self.policy.row_limit);
        let effective_limit = requested.clamp(0, self.policy.row_limit);
        let clamped = requested > self.policy.row_limit;

        // Adapter call (the ONLY place the external port is reached). Everything above gated it.
        match self.adapter.query(&plan, effective_limit, &kinds).await {
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
            PostgresReadResult::Unavailable(m) => {
                EffectOutcome::unknown(&format!("adapter unavailable: {m}"))
            }
            PostgresReadResult::Transient(m) => {
                EffectOutcome::retryable(&format!("adapter transient: {m}"))
            }
            PostgresReadResult::QueryError(m) => {
                EffectOutcome::permanent(&format!("query error: {m}"))
            }
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
        self.sources
            .insert(source.to_string(), SourceBehavior::Table(rows));
        self
    }
    pub fn unavailable(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(
            source.to_string(),
            SourceBehavior::Unavailable(reason.to_string()),
        );
        self
    }
    pub fn transient(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(
            source.to_string(),
            SourceBehavior::Transient(reason.to_string()),
        );
        self
    }
    pub fn query_error(mut self, source: &str, reason: &str) -> Self {
        self.sources.insert(
            source.to_string(),
            SourceBehavior::QueryError(reason.to_string()),
        );
        self
    }
    /// How many times the adapter actually ran a query (replay must keep this unchanged).
    pub fn query_count(&self) -> u64 {
        self.queries.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl PostgresReadAdapter for FakePostgresAdapter {
    // The fake stores already-typed `serde_json::Value` rows; it preserves int/bool/json/null types
    // and ignores the decode `kinds`. P11: it now EVALUATES the (already-validated) predicates +
    // order_by deterministically — filter → sort → project → limit. No SQL, no expression language.
    async fn query(
        &self,
        plan: &QueryPlan,
        effective_limit: i64,
        _kinds: &HashMap<String, PostgresReadValueKind>,
    ) -> PostgresReadResult {
        self.queries.fetch_add(1, Ordering::SeqCst);
        match self.sources.get(&plan.source) {
            Some(SourceBehavior::Unavailable(m)) => PostgresReadResult::Unavailable(m.clone()),
            Some(SourceBehavior::Transient(m)) => PostgresReadResult::Transient(m.clone()),
            Some(SourceBehavior::QueryError(m)) => PostgresReadResult::QueryError(m.clone()),
            Some(SourceBehavior::Table(rows)) => {
                // 1. filter: every predicate must hold (AND-composed); a missing field never matches.
                let mut matched: Vec<&Value> = rows
                    .iter()
                    .filter(|row| {
                        plan.filters.iter().all(|f| {
                            row.get(&f.field)
                                .map(|v| row_matches_filter(v, f))
                                .unwrap_or(false)
                        })
                    })
                    .collect();

                // 2. order_by: stable sort, last clause first → earlier clauses dominate.
                for o in plan.order_by.iter().rev() {
                    matched.sort_by(|a, b| {
                        let av = a.get(&o.field).unwrap_or(&Value::Null);
                        let bv = b.get(&o.field).unwrap_or(&Value::Null);
                        let ord = cmp_values(av, bv).unwrap_or(std::cmp::Ordering::Equal);
                        if o.dir == "desc" {
                            ord.reverse()
                        } else {
                            ord
                        }
                    });
                }

                // 3. project + 4. limit (types preserved by cloning the stored value).
                let take = if effective_limit < 0 {
                    0
                } else {
                    effective_limit as usize
                };
                let shaped: Vec<Value> = matched
                    .into_iter()
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
