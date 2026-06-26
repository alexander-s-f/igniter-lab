//! Real local Postgres adapters (LAB-MACHINE-POSTGRES-LOCAL-READ-P6) — opt-in `postgres` feature.
//!
//! The FIRST real database adapter: `TokioPostgresReadAdapter` implements the P2
//! `PostgresReadAdapter` over a real `tokio_postgres` connection. It is the drop-in real
//! counterpart of `FakePostgresAdapter` — the `PostgresReadExecutor` gates (raw-SQL refusal,
//! source/op/field allowlist, row-limit clamp) run UNCHANGED before this adapter is ever called,
//! and the receipt/idempotency/replay machinery is the unchanged `run_effect` path.
//!
//! This whole module is compiled ONLY under `--features postgres`; the default build stays
//! fake-only and pulls no database driver. **Read-only**: SELECT only, never writes/DDL.
//!
//! v0 mapping (deliberately bounded — this proves the connector boundary, not rich type mapping):
//! - an explicit projection is required (no `SELECT *`);
//! - every projected column is rendered `"<col>"::text` so each value returns as TEXT;
//! - filters are `eq`-only, values bound as `$1..$n`, the column cast `::text` for a uniform
//!   text compare; any other operator → a `query_error` (permanent), never a silently-wrong query;
//! - identifiers come ONLY from the already-allowlisted plan and are quoted (defence in depth);
//! - the clamped `effective_limit` is the `LIMIT`.

use crate::postgres_read::{
    PostgresReadAdapter, PostgresReadResult, PostgresReadValueKind, QueryPlan,
};
use crate::postgres_write::{
    PostgresReceiptLookup, PostgresWriteAdapter, PostgresWriteIntent, PostgresWriteReceiptResolver,
    PostgresWriteResult,
};
use async_trait::async_trait;
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio_postgres::types::ToSql;
use tokio_postgres::{Client, NoTls};

/// Quote a SQL identifier (already allowlisted by the executor; quoted here as defence in depth).
fn quote_ident(s: &str) -> String {
    format!("\"{}\"", s.replace('"', "\"\""))
}

/// Render a JSON filter value as the TEXT parameter bound to a `::text` column compare.
fn value_to_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// A real read adapter over `tokio_postgres`. Holds one connection (a pool is a later slice).
/// Counts queries so idempotency/replay can be proven (a replayed effect never reaches here).
pub struct TokioPostgresReadAdapter {
    client: Arc<Client>,
    queries: AtomicU64,
}

impl TokioPostgresReadAdapter {
    /// Connect to a local Postgres with a key=value or URL DSN, spawning the connection driver on
    /// the current tokio runtime. The DSN comes from a `SecretProvider`/env — never hardcoded, and
    /// it never enters a receipt or a log. NoTls (local loopback); TLS is a later slice.
    pub async fn connect(dsn: &str) -> Result<Self, tokio_postgres::Error> {
        let (client, connection) = tokio_postgres::connect(dsn, NoTls).await?;
        // Drive the connection in the background; it completes when the client is dropped.
        tokio::spawn(async move {
            let _ = connection.await;
        });
        Ok(Self {
            client: Arc::new(client),
            queries: AtomicU64::new(0),
        })
    }

    /// How many real queries were actually executed (a replayed effect must NOT increment this).
    pub fn query_count(&self) -> u64 {
        self.queries.load(Ordering::SeqCst)
    }
}

/// The SQL projection expression for a field, per its host-declared decode kind (P10). Text-like
/// kinds keep the `::text` cast (uniform, lossless for timestamp/decimal); int/bool cast to a
/// native scalar; json/array cast to `jsonb` for a `serde_json::Value` decode. Identifiers are
/// already allowlisted and are quoted (defence in depth).
fn projection_expr(col: &str, kind: PostgresReadValueKind) -> String {
    let q = quote_ident(col);
    match kind {
        PostgresReadValueKind::Text
        | PostgresReadValueKind::Timestamp
        | PostgresReadValueKind::DecimalString
        // P23: a typed `Decimal{scale}` reads the same lossless `::text` digits; the host materializer
        // parses them into `{value, scale}`. Never a lossy `::float`.
        | PostgresReadValueKind::Decimal { .. } => format!("{q}::text"),
        PostgresReadValueKind::Integer => format!("{q}::bigint"),
        PostgresReadValueKind::Boolean => format!("{q}::bool"),
        PostgresReadValueKind::Json | PostgresReadValueKind::Array => format!("{q}::jsonb"),
    }
}

/// Decode the `i`-th column of a returned row into a typed JSON value, per its decode kind. NULL of
/// any kind → `Value::Null`. `numeric`/timestamp stay String (lossless); int/bool become JSON
/// scalars; json/jsonb (and narrow json arrays) become the decoded `serde_json::Value`.
fn decode_value(row: &tokio_postgres::Row, i: usize, kind: PostgresReadValueKind) -> Value {
    match kind {
        PostgresReadValueKind::Text
        | PostgresReadValueKind::Timestamp
        | PostgresReadValueKind::DecimalString
        // P23: typed `Decimal{scale}` decodes the exact digit string here; the host materializer turns it
        // into `{value, scale}`. The decode is identical to `DecimalString` — only the host kind differs.
        | PostgresReadValueKind::Decimal { .. } => row
            .get::<_, Option<String>>(i)
            .map(Value::String)
            .unwrap_or(Value::Null),
        PostgresReadValueKind::Integer => row
            .get::<_, Option<i64>>(i)
            .map(|n| Value::Number(n.into()))
            .unwrap_or(Value::Null),
        PostgresReadValueKind::Boolean => row
            .get::<_, Option<bool>>(i)
            .map(Value::Bool)
            .unwrap_or(Value::Null),
        PostgresReadValueKind::Json | PostgresReadValueKind::Array => {
            row.get::<_, Option<Value>>(i).unwrap_or(Value::Null)
        }
    }
}

/// The SQL cast applied to a filter/order column so a typed compare is sound (P11): integer →
/// `::bigint`, boolean → `::bool`, timestamp → `::timestamptz`, everything else → `::text`.
fn compare_cast(field: &str, kind: PostgresReadValueKind) -> String {
    let q = quote_ident(field);
    match kind {
        PostgresReadValueKind::Integer => format!("{q}::bigint"),
        PostgresReadValueKind::Boolean => format!("{q}::bool"),
        PostgresReadValueKind::Timestamp => format!("{q}::timestamptz"),
        // Text compare/order pins `COLLATE "C"` (byte order) so range ops + ORDER BY are deterministic
        // across DB locales and match the fake adapter's byte-wise `String::cmp` (P47 keyset pagination).
        _ => format!("{q}::text COLLATE \"C\""),
    }
}

/// Bind one scalar JSON value as a typed parameter for its kind (P11). Type mismatch → Err (a
/// permanent query error — never a silent coercion). Timestamp/Text/Decimal bind as text and the
/// placeholder applies the cast.
fn bind_scalar(
    kind: PostgresReadValueKind,
    v: &Value,
) -> Result<Box<dyn ToSql + Sync + Send>, String> {
    match kind {
        PostgresReadValueKind::Integer => v
            .as_i64()
            .map(|n| Box::new(n) as Box<dyn ToSql + Sync + Send>)
            .ok_or_else(|| format!("expected integer value, got {v}")),
        PostgresReadValueKind::Boolean => v
            .as_bool()
            .map(|b| Box::new(b) as Box<dyn ToSql + Sync + Send>)
            .ok_or_else(|| format!("expected boolean value, got {v}")),
        _ => Ok(Box::new(value_to_text(v)) as Box<dyn ToSql + Sync + Send>),
    }
}

/// Bind an `in` list as a typed array parameter (P11). `in` is only allowed for Text/Integer/Boolean.
fn bind_array(
    kind: PostgresReadValueKind,
    vs: &[Value],
) -> Result<Box<dyn ToSql + Sync + Send>, String> {
    match kind {
        PostgresReadValueKind::Integer => {
            let mut out = Vec::with_capacity(vs.len());
            for v in vs {
                out.push(
                    v.as_i64()
                        .ok_or_else(|| format!("expected integer, got {v}"))?,
                );
            }
            Ok(Box::new(out) as Box<dyn ToSql + Sync + Send>)
        }
        PostgresReadValueKind::Boolean => {
            let mut out = Vec::with_capacity(vs.len());
            for v in vs {
                out.push(
                    v.as_bool()
                        .ok_or_else(|| format!("expected boolean, got {v}"))?,
                );
            }
            Ok(Box::new(out) as Box<dyn ToSql + Sync + Send>)
        }
        _ => Ok(
            Box::new(vs.iter().map(value_to_text).collect::<Vec<String>>())
                as Box<dyn ToSql + Sync + Send>,
        ),
    }
}

/// The SQL operator for a scalar range/eq op.
fn sql_op(op: &str) -> &'static str {
    match op {
        "gt" => ">",
        "gte" => ">=",
        "lt" => "<",
        "lte" => "<=",
        _ => "=",
    }
}

#[async_trait]
impl PostgresReadAdapter for TokioPostgresReadAdapter {
    async fn query(
        &self,
        plan: &QueryPlan,
        effective_limit: i64,
        kinds: &HashMap<String, PostgresReadValueKind>,
    ) -> PostgresReadResult {
        self.queries.fetch_add(1, Ordering::SeqCst);
        let kind_of = |f: &str| kinds.get(f).copied().unwrap_or_default();

        // v0 requires an explicit projection (keeps the value→JSON mapping bounded + allowlisted).
        if plan.projection.is_empty() {
            return PostgresReadResult::QueryError(
                "real adapter v0 requires an explicit projection".to_string(),
            );
        }
        let cols: Vec<String> = plan
            .projection
            .iter()
            .map(|c| projection_expr(c, kind_of(c)))
            .collect();

        // Typed predicates (already validated by the executor): values bound as $1..$n. `in` →
        // `= ANY($n)` over a typed array; range/eq → `<cast> <op> $n` (timestamp param cast too).
        let mut where_parts: Vec<String> = Vec::new();
        let mut params: Vec<Box<dyn ToSql + Sync + Send>> = Vec::new();
        for f in &plan.filters {
            let kind = kind_of(&f.field);
            let lhs = compare_cast(&f.field, kind);
            if f.op == "in" {
                match bind_array(kind, &f.values) {
                    Ok(p) => params.push(p),
                    Err(e) => return PostgresReadResult::QueryError(e),
                }
                where_parts.push(format!("{lhs} = ANY(${})", params.len()));
            } else {
                match bind_scalar(kind, &f.value) {
                    Ok(p) => params.push(p),
                    Err(e) => return PostgresReadResult::QueryError(e),
                }
                let ph = if kind == PostgresReadValueKind::Timestamp {
                    format!("${}::timestamptz", params.len())
                } else {
                    format!("${}", params.len())
                };
                where_parts.push(format!("{lhs} {} {ph}", sql_op(&f.op)));
            }
        }

        let mut sql = format!(
            "SELECT {} FROM {}",
            cols.join(", "),
            quote_ident(&plan.source)
        );
        if !where_parts.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&where_parts.join(" AND "));
        }
        if !plan.order_by.is_empty() {
            let parts: Vec<String> = plan
                .order_by
                .iter()
                .map(|o| {
                    let dir = if o.dir == "desc" { "DESC" } else { "ASC" };
                    format!("{} {dir}", compare_cast(&o.field, kind_of(&o.field)))
                })
                .collect();
            sql.push_str(" ORDER BY ");
            sql.push_str(&parts.join(", "));
        }
        let lim = effective_limit.max(0);
        sql.push_str(&format!(" LIMIT {lim}"));

        let param_refs: Vec<&(dyn ToSql + Sync)> = params
            .iter()
            .map(|b| b.as_ref() as &(dyn ToSql + Sync))
            .collect();

        match self.client.query(sql.as_str(), &param_refs).await {
            Ok(rows) => {
                let out: Vec<Value> = rows
                    .iter()
                    .map(|row| {
                        let mut obj = Map::new();
                        for (i, field) in plan.projection.iter().enumerate() {
                            obj.insert(field.clone(), decode_value(row, i, kind_of(field)));
                        }
                        Value::Object(obj)
                    })
                    .collect();
                PostgresReadResult::Rows(out)
            }
            // A DB error (SQLSTATE) is a definite query failure → permanent. Anything else
            // (connection/IO) → unavailable → unknown (epistemic, no false "not found").
            Err(e) => {
                if e.as_db_error().is_some() {
                    PostgresReadResult::QueryError(format!("{e}"))
                } else {
                    PostgresReadResult::Unavailable(format!("{e}"))
                }
            }
        }
    }
}

// ── Real write adapter (LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8) ────────────────────
//
// The real counterpart of `FakePostgresWriteAdapter`. Driven by the UNCHANGED `run_write_effect`
// two-phase receipt; this adapter only performs the transaction. **One effect = one atomic
// statement**: a single writable-CTE statement inserts the PG-side `effect_receipts(idempotency_key)`
// row (ON CONFLICT DO NOTHING) and performs the business upsert ONLY when that receipt was fresh —
// so a duplicate idempotency key blocks the second business mutation (the P3 second idempotency
// layer) without a separate transaction object (`Client::query` takes `&self`, so `Arc<Client>`
// suffices). Read-only reconcile via `PostgresWriteReceiptResolver`. Dedicated test DB only.

/// Render a JSON value as an optional TEXT parameter (absent/null → SQL NULL).
fn json_to_opt_text(v: Option<&Value>) -> Option<String> {
    match v {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(other) => Some(other.to_string()),
    }
}

/// Map a `tokio_postgres` error to the P3 write taxonomy: SQLSTATE class drives permanent vs
/// retryable vs denied; a non-DB (connection/IO) error is `Unknown` (no blind retry).
fn classify_write_error(e: &tokio_postgres::Error) -> PostgresWriteResult {
    match e.as_db_error() {
        Some(db) => {
            let code = db.code().code().to_string();
            match code.as_str() {
                "40001" | "40P01" => {
                    PostgresWriteResult::SerializationFailure(format!("{code}: {e}"))
                }
                "42501" => PostgresWriteResult::Denied(format!("{code}: insufficient privilege")),
                c if c.starts_with("23") => {
                    PostgresWriteResult::ConstraintViolation(format!("{c}: {e}"))
                }
                _ => PostgresWriteResult::ConstraintViolation(format!("{code}: {e}")),
            }
        }
        None => PostgresWriteResult::Unknown(format!("connection/io: {e}")),
    }
}

/// A real write adapter over `tokio_postgres`. HOST-CONFIGURED with the single `target` table, its
/// primary-key column, and the value columns it may write — so a contract can NEVER supply a SQL
/// identifier (the intent's values are read only for those configured columns; missing → NULL).
pub struct TokioPostgresWriteAdapter {
    client: Arc<Client>,
    target: String,
    key_column: String,
    columns: Vec<String>,
    attempts: AtomicU64,
}

impl TokioPostgresWriteAdapter {
    /// Connect and bind to one host-owned `target(key_column, columns…)`. DSN from a
    /// SecretProvider/env — never hardcoded, never in a receipt. NoTls loopback (TLS = later slice).
    pub async fn connect(
        dsn: &str,
        target: &str,
        key_column: &str,
        columns: &[&str],
    ) -> Result<Self, tokio_postgres::Error> {
        let (client, connection) = tokio_postgres::connect(dsn, NoTls).await?;
        tokio::spawn(async move {
            let _ = connection.await;
        });
        Ok(Self {
            client: Arc::new(client),
            target: target.to_string(),
            key_column: key_column.to_string(),
            columns: columns.iter().map(|c| c.to_string()).collect(),
            attempts: AtomicU64::new(0),
        })
    }

    /// How many real transactions were attempted (a machine-receipt replay must NOT increment this).
    pub fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }

    /// Direct read of the business table (test/diagnostic): `SELECT <cols> FROM target WHERE key=$1`.
    pub async fn read_business_text(&self, key: &str, col: &str) -> Option<String> {
        let sql = format!(
            "SELECT {}::text FROM {} WHERE {} = $1",
            quote_ident(col),
            quote_ident(&self.target),
            quote_ident(&self.key_column)
        );
        match self.client.query_opt(sql.as_str(), &[&key]).await {
            Ok(Some(row)) => row.get::<_, Option<String>>(0),
            _ => None,
        }
    }
}

#[async_trait]
impl PostgresWriteAdapter for TokioPostgresWriteAdapter {
    async fn transact(
        &self,
        intent: &PostgresWriteIntent,
        idempotency_key: &str,
    ) -> PostgresWriteResult {
        self.attempts.fetch_add(1, Ordering::SeqCst);

        // The effect-receipt gate (`ins`) is identical for every operation — that is what gives delete
        // the SAME two-layer idempotency as insert/upsert: a duplicate idempotency key makes `ins` empty,
        // so the business CTE's `WHERE EXISTS (SELECT 1 FROM ins)` (or, for DELETE, the same guard) does
        // nothing and the call resolves to `DuplicateKey`. Only the business CTE + its params differ.
        // Params always start: $1..$4 = effect-receipt row, $5 = business key.
        let mut params: Vec<Option<String>> = vec![
            Some(idempotency_key.to_string()),
            intent.correlation_id.clone(),
            Some(intent.target.clone()),
            Some(intent.key.clone()),
            Some(intent.key.clone()), // $5 = business key value
        ];

        let biz_cte = if intent.operation == "delete" {
            // DELETE the business row by key, gated on a fresh effect-receipt. Deleting an absent row is
            // a no-op DELETE (0 rows) but still a fresh receipt → `Committed` (idempotent delete). No
            // value columns are read; $5 is the only business param.
            format!(
                "biz AS (DELETE FROM {target} WHERE {key} = $5 AND EXISTS (SELECT 1 FROM ins) RETURNING 1)",
                target = quote_ident(&self.target),
                key = quote_ident(&self.key_column),
            )
        } else {
            // INSERT … ON CONFLICT (insert/upsert). Columns come from the HOST-configured `columns`
            // (never the intent's keys); $6.. = those column values (NULL when the intent omits them).
            let biz_cols: Vec<String> = std::iter::once(quote_ident(&self.key_column))
                .chain(self.columns.iter().map(|c| quote_ident(c)))
                .collect();
            let biz_placeholders: Vec<String> =
                (0..biz_cols.len()).map(|i| format!("${}", 5 + i)).collect();
            let on_conflict = if self.columns.is_empty() {
                "DO NOTHING".to_string()
            } else {
                let sets: Vec<String> = self
                    .columns
                    .iter()
                    .map(|c| format!("{0}=EXCLUDED.{0}", quote_ident(c)))
                    .collect();
                format!("DO UPDATE SET {}", sets.join(", "))
            };
            for c in &self.columns {
                params.push(json_to_opt_text(intent.values.get(c)));
            }
            format!(
                "biz AS (INSERT INTO {target} ({cols}) SELECT {ph} WHERE EXISTS (SELECT 1 FROM ins) \
                 ON CONFLICT ({key}) {on_conflict} RETURNING 1)",
                target = quote_ident(&self.target),
                cols = biz_cols.join(", "),
                ph = biz_placeholders.join(", "),
                key = quote_ident(&self.key_column),
                on_conflict = on_conflict,
            )
        };

        let sql = format!(
            "WITH ins AS (\
               INSERT INTO effect_receipts (idempotency_key, correlation_id, target, business_key) \
               VALUES ($1, $2, $3, $4) ON CONFLICT (idempotency_key) DO NOTHING RETURNING 1\
             ), {biz_cte} SELECT count(*)::int AS fresh FROM ins",
        );

        let param_refs: Vec<&(dyn ToSql + Sync)> =
            params.iter().map(|p| p as &(dyn ToSql + Sync)).collect();

        match self.client.query_one(sql.as_str(), &param_refs).await {
            Ok(row) => {
                let fresh: i32 = row.get("fresh");
                if fresh == 1 {
                    PostgresWriteResult::Committed
                } else {
                    PostgresWriteResult::DuplicateKey
                }
            }
            Err(e) => classify_write_error(&e),
        }
    }
}

#[async_trait]
impl PostgresWriteReceiptResolver for TokioPostgresWriteAdapter {
    async fn lookup_effect_receipt(&self, idempotency_key: &str) -> PostgresReceiptLookup {
        // READ ONLY — never re-runs the write. Any error → Unavailable (cannot determine the fate).
        let sql = "SELECT correlation_id, target, business_key FROM effect_receipts WHERE idempotency_key = $1";
        match self.client.query_opt(sql, &[&idempotency_key]).await {
            Ok(Some(row)) => PostgresReceiptLookup::Found {
                correlation_id: row.get::<_, Option<String>>(0),
                target: row.get::<_, String>(1),
                key: row.get::<_, String>(2),
            },
            Ok(None) => PostgresReceiptLookup::NotFound,
            Err(e) => PostgresReceiptLookup::Unavailable(format!("{e}")),
        }
    }
}
