//! Postgres-shaped receipt-gated write capability (LAB-MACHINE-POSTGRES-WRITE-GATE-P3).
//!
//! The write counterpart of `postgres_read` (P2) — and again **fake-adapter only**: no
//! `tokio-postgres`/`sqlx`/`diesel`, no DB, no network, no SQL executed. It proves the
//! Postgres-shaped write boundary decided in the readiness packet (P1 §4): a contract emits a
//! typed `PostgresWriteIntent` (NO SQL, NO DB handle); the host runs it through the EXISTING
//! `write::run_write_effect` two-phase receipt protocol; the executor wraps a fake adapter that
//! models **one transaction** containing the business mutation AND a PG-side
//! `effect_receipts(idempotency_key)` upsert.
//!
//! ```text
//! WriteRequest.payload = typed PostgresWriteIntent
//!   → run_write_effect / run_write_effect_atomic     (machine receipt: prepared → terminal)
//!       layer 1 idempotency: machine __receipts__ (replay / different-payload refusal)
//!   → PostgresWriteExecutor : CapabilityExecutor
//!       gates (BEFORE the adapter): raw-SQL refusal · target allowlist · op allowlist
//!   → PostgresWriteAdapter.transact(intent, idempotency_key)   (fake: ONE txn)
//!       layer 2 idempotency: PG-side effect_receipts(idempotency_key) → no 2nd mutation
//!   → EffectOutcome → WriteState (committed/denied/retryable/permanent/unknown)
//! ```
//!
//! Two-layer idempotency = defence in depth: even if the machine receipt is LOST, the PG-side
//! `effect_receipts` unique key blocks a second business mutation. Reconcile of `unknown` is P4
//! (NOT here). No ORM/SQL reaches `.ig`, the VM, or capsule activation.

use crate::capability::{CapabilityExecutor, EffectOutcome, EffectRequest};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

// ── Typed write intent (what a contract emits — never SQL) ─────────────────────

/// A typed mutation intent. `target` is a logical table name (allowlist-resolved, never a
/// contract-supplied SQL identifier); `key` is the business/primary key; `values` are bound
/// parameters (never interpolated). `correlation_id` threads the P11/P13 reconcile trail.
#[derive(Clone, Debug)]
pub struct PostgresWriteIntent {
    pub operation: String,
    pub target: String,
    pub key: String,
    pub values: Value,
    pub correlation_id: Option<String>,
}

impl PostgresWriteIntent {
    /// Parse an intent from the effect payload. Refuses a raw-SQL-shaped payload structurally:
    /// a `sql` / `raw_sql` / `query` string is a hard error, NOT an intent.
    pub fn from_args(args: &Value) -> Result<PostgresWriteIntent, String> {
        for raw in ["sql", "raw_sql", "query"] {
            if args.get(raw).and_then(|v| v.as_str()).is_some() {
                return Err(format!("raw SQL refused (`{raw}`): contracts emit typed intents, not SQL"));
            }
        }
        let operation = args
            .get("operation")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing `operation`".to_string())?
            .to_string();
        let target = args
            .get("target")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing `target`".to_string())?
            .to_string();
        let key = args
            .get("key")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing `key`".to_string())?
            .to_string();
        let values = args.get("values").cloned().unwrap_or_else(|| json!({}));
        let correlation_id = args.get("correlation_id").and_then(|v| v.as_str()).map(|s| s.to_string());
        Ok(PostgresWriteIntent { operation, target, key, values, correlation_id })
    }
}

// ── Host-owned write policy (the allowlist gates) ──────────────────────────────

/// Host-owned write policy: the allowlist authority for v0 (hand-written host config, not
/// contract input, not DB introspection). Bounds which tables and which operations a contract
/// may mutate.
#[derive(Clone, Debug, Default)]
pub struct PostgresWritePolicy {
    pub allowed_targets: Vec<String>,
    pub allowed_ops: Vec<String>,
}

impl PostgresWritePolicy {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn allow_target(mut self, target: &str) -> Self {
        self.allowed_targets.push(target.to_string());
        self
    }
    pub fn allow_ops(mut self, ops: &[&str]) -> Self {
        self.allowed_ops = ops.iter().map(|o| o.to_string()).collect();
        self
    }
}

// ── The adapter port (fake here; tokio-postgres later, behind an opt-in feature) ─

/// What the adapter's transaction returned. Maps to the documented write taxonomy:
/// `Committed`/`DuplicateKey` → succeeded → `WriteState::Committed` (duplicate = no 2nd mutation),
/// `Denied` → denied, `ConstraintViolation` → permanent, `SerializationFailure` → retryable
/// (rolled back, KNOWN no mutation), `Unknown` → unknown_external_state (no blind retry; P4
/// reconciles).
pub enum PostgresWriteResult {
    Committed,
    /// The PG-side `effect_receipts(idempotency_key)` already had this key → the business mutation
    /// is NOT performed again; treated as a committed replay.
    DuplicateKey,
    Denied(String),
    ConstraintViolation(String),
    SerializationFailure(String),
    Unknown(String),
}

/// The host-side write port. The real impl (later, opt-in) holds a connection pool and runs ONE
/// `BEGIN … COMMIT` containing the business mutation + the `effect_receipts` upsert. The intent
/// it receives is already gate-checked.
#[async_trait]
pub trait PostgresWriteAdapter: Send + Sync {
    async fn transact(&self, intent: &PostgresWriteIntent, idempotency_key: &str) -> PostgresWriteResult;
}

// ── The executor ───────────────────────────────────────────────────────────────

/// A Postgres-shaped write capability. Implements `CapabilityExecutor`, so it is driven by the
/// EXISTING `write::run_write_effect` / `single_flight::run_write_effect_atomic` protocol (two-
/// phase receipt, payload-digest idempotency, no-blind-retry) — NO new write machinery, exactly
/// as `TBackendWriteExecutor` is.
pub struct PostgresWriteExecutor<A: PostgresWriteAdapter> {
    capability_id: String,
    adapter: Arc<A>,
    policy: PostgresWritePolicy,
}

impl<A: PostgresWriteAdapter> PostgresWriteExecutor<A> {
    pub fn new(capability_id: &str, adapter: Arc<A>, policy: PostgresWritePolicy) -> Self {
        Self { capability_id: capability_id.to_string(), adapter, policy }
    }
}

#[async_trait]
impl<A: PostgresWriteAdapter + 'static> CapabilityExecutor for PostgresWriteExecutor<A> {
    fn capability_id(&self) -> &str {
        &self.capability_id
    }

    async fn execute(&self, req: &EffectRequest) -> EffectOutcome {
        // (0) Structural raw-SQL refusal + intent parse. A contract can never hand us SQL.
        let intent = match PostgresWriteIntent::from_args(&req.args) {
            Ok(i) => i,
            Err(e) if e.starts_with("raw SQL") => return EffectOutcome::permanent(&e),
            Err(e) => return EffectOutcome::permanent(&format!("malformed write intent: {e}")),
        };

        // (gate) target allowlist — refused before the adapter (denial-as-data).
        if !self.policy.allowed_targets.iter().any(|t| t == &intent.target) {
            return EffectOutcome::denied(&format!("target not allowed: {}", intent.target));
        }
        // (gate) operation allowlist.
        if !self.policy.allowed_ops.iter().any(|o| o == &intent.operation) {
            return EffectOutcome::denied(&format!("op not allowed: {}", intent.operation));
        }

        // The ONLY place the external port (a transaction) is reached. `idempotency_key` is the
        // one the machine receipt is keyed by (set by run_write_effect), so both idempotency
        // layers share the same key.
        let corr = intent.correlation_id.clone();
        match self.adapter.transact(&intent, &req.idempotency_key).await {
            PostgresWriteResult::Committed => EffectOutcome::succeeded(json!({
                "committed": true,
                "duplicate": false,
                "target": intent.target,
                "key": intent.key,
                "correlation_id": corr,
            })),
            PostgresWriteResult::DuplicateKey => EffectOutcome::succeeded(json!({
                "committed": true,
                "duplicate": true,            // PG-side dedup: no second business mutation
                "target": intent.target,
                "key": intent.key,
                "correlation_id": corr,
            })),
            PostgresWriteResult::Denied(m) => EffectOutcome::denied(&m),
            PostgresWriteResult::ConstraintViolation(m) => EffectOutcome::permanent(&format!("constraint violation: {m}")),
            PostgresWriteResult::SerializationFailure(m) => EffectOutcome::retryable(&format!("serialization failure (rolled back): {m}")),
            PostgresWriteResult::Unknown(m) => EffectOutcome::unknown(&format!("commit state unknown: {m}")),
        }
    }
}

// ── Fake adapter (proof only — no DB, no SQL, no dependency) ────────────────────

/// Scripted transaction behaviour for the fake adapter.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum FakeWriteBehavior {
    Commit,
    ConstraintViolation,
    SerializationFailure,
    Unknown,
    Denied,
}

/// An in-memory fake of a Postgres write adapter modelling ONE transaction = business mutation +
/// PG-side `effect_receipts(idempotency_key)` upsert. Two maps:
/// - `business_rows["target/key"] = values`
/// - `effect_receipts[idempotency_key] = { correlation_id, target, key }`
///
/// On `Commit` behaviour: if `idempotency_key` already exists in `effect_receipts` → `DuplicateKey`
/// (NO second business mutation) — this is the PG-side second idempotency layer, independent of the
/// machine receipt. Other behaviours roll back (no mutation) and return their failure variant.
/// `attempts` counts every `transact` call; a machine-receipt replay never reaches it.
pub struct FakePostgresWriteAdapter {
    behavior: FakeWriteBehavior,
    business_rows: Mutex<HashMap<String, Value>>,
    effect_receipts: Mutex<HashMap<String, Value>>,
    attempts: AtomicU64,
}

impl FakePostgresWriteAdapter {
    pub fn new(behavior: FakeWriteBehavior) -> Self {
        Self {
            behavior,
            business_rows: Mutex::new(HashMap::new()),
            effect_receipts: Mutex::new(HashMap::new()),
            attempts: AtomicU64::new(0),
        }
    }
    /// How many times a transaction was actually attempted (a machine-receipt replay must NOT
    /// increment this).
    pub fn attempts(&self) -> u64 {
        self.attempts.load(Ordering::SeqCst)
    }
    /// Number of distinct business rows written (the witness for "exactly one mutation").
    pub fn business_row_count(&self) -> usize {
        self.business_rows.lock().unwrap().len()
    }
    /// Number of PG-side effect receipts recorded.
    pub fn effect_receipt_count(&self) -> usize {
        self.effect_receipts.lock().unwrap().len()
    }
    pub fn has_effect_receipt(&self, idempotency_key: &str) -> bool {
        self.effect_receipts.lock().unwrap().contains_key(idempotency_key)
    }
}

#[async_trait]
impl PostgresWriteAdapter for FakePostgresWriteAdapter {
    async fn transact(&self, intent: &PostgresWriteIntent, idempotency_key: &str) -> PostgresWriteResult {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        match self.behavior {
            FakeWriteBehavior::Commit => {
                // PG-side idempotency: the unique key blocks a second mutation even if the machine
                // receipt is absent/lost.
                if self.effect_receipts.lock().unwrap().contains_key(idempotency_key) {
                    return PostgresWriteResult::DuplicateKey;
                }
                // ONE transaction: business mutation + effect-receipt upsert, both or neither.
                let row_key = format!("{}/{}", intent.target, intent.key);
                self.business_rows.lock().unwrap().insert(row_key, intent.values.clone());
                self.effect_receipts.lock().unwrap().insert(
                    idempotency_key.to_string(),
                    json!({
                        "correlation_id": intent.correlation_id,
                        "target": intent.target,
                        "key": intent.key,
                    }),
                );
                PostgresWriteResult::Committed
            }
            // The remaining behaviours roll back — no mutation, nothing recorded.
            FakeWriteBehavior::ConstraintViolation => {
                PostgresWriteResult::ConstraintViolation("duplicate value violates unique constraint".to_string())
            }
            FakeWriteBehavior::SerializationFailure => {
                PostgresWriteResult::SerializationFailure("could not serialize access due to concurrent update".to_string())
            }
            FakeWriteBehavior::Unknown => {
                // Lost-after-send: the response never came back. v0 records nothing and refuses to
                // guess; the landed-but-unknown case is resolved by reconcile (P4), not here.
                PostgresWriteResult::Unknown("connection lost after sending".to_string())
            }
            FakeWriteBehavior::Denied => {
                PostgresWriteResult::Denied("insufficient privilege".to_string())
            }
        }
    }
}
