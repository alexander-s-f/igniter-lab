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

use crate::postgres_read::{PostgresReadAdapter, PostgresReadResult, QueryPlan};
use async_trait::async_trait;
use serde_json::{Map, Value};
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
        Ok(Self { client: Arc::new(client), queries: AtomicU64::new(0) })
    }

    /// How many real queries were actually executed (a replayed effect must NOT increment this).
    pub fn query_count(&self) -> u64 {
        self.queries.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl PostgresReadAdapter for TokioPostgresReadAdapter {
    async fn query(&self, plan: &QueryPlan, effective_limit: i64) -> PostgresReadResult {
        self.queries.fetch_add(1, Ordering::SeqCst);

        // v0 requires an explicit projection (keeps the value→JSON mapping bounded to TEXT).
        if plan.projection.is_empty() {
            return PostgresReadResult::QueryError(
                "real adapter v0 requires an explicit projection".to_string(),
            );
        }
        let cols: Vec<String> = plan.projection.iter().map(|c| format!("{}::text", quote_ident(c))).collect();

        // eq-only filters; values bound as $1..$n; column cast ::text for a uniform text compare.
        let mut where_parts: Vec<String> = Vec::new();
        let mut params: Vec<String> = Vec::new();
        for f in &plan.filters {
            if f.op != "eq" {
                return PostgresReadResult::QueryError(format!("unsupported filter op in v0: {}", f.op));
            }
            params.push(value_to_text(&f.value));
            where_parts.push(format!("{}::text = ${}", quote_ident(&f.field), params.len()));
        }

        let mut sql = format!("SELECT {} FROM {}", cols.join(", "), quote_ident(&plan.source));
        if !where_parts.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&where_parts.join(" AND "));
        }
        let lim = effective_limit.max(0);
        sql.push_str(&format!(" LIMIT {lim}"));

        let param_refs: Vec<&(dyn ToSql + Sync)> =
            params.iter().map(|s| s as &(dyn ToSql + Sync)).collect();

        match self.client.query(sql.as_str(), &param_refs).await {
            Ok(rows) => {
                let out: Vec<Value> = rows
                    .iter()
                    .map(|row| {
                        let mut obj = Map::new();
                        for (i, field) in plan.projection.iter().enumerate() {
                            let v: Option<String> = row.get(i);
                            obj.insert(field.clone(), v.map(Value::String).unwrap_or(Value::Null));
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
