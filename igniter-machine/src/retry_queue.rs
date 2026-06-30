//! Durable retry queue (LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9).
//!
//! P8 retried within a single call. Production traffic needs **retry over time**: a failed
//! attempt enqueues a durable retry *intent* (a TBackend fact with a `due_at`), and a later
//! explicit `drain_due_retries(now)` runs the next attempt under the SAME reconcile-gated
//! rules. No background worker, no HTTP — just durable, auditable intents drained on demand.
//!
//! Every scheduler operation (enqueue / reschedule / done / exhausted / abandoned / blocked) is
//! a fact in `__retry_queue__`, so the whole retry history is auditable. The live state of an
//! intent is the latest fact at its key.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use crate::reconcile::{reconcile_unknown_write, ReconcileResult};
use crate::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

pub const RETRY_QUEUE_STORE: &str = "__retry_queue__";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IntentState {
    Pending,
    Done,
    Exhausted,
    Abandoned,
    Blocked,
}

impl IntentState {
    pub fn as_str(&self) -> &'static str {
        match self {
            IntentState::Pending => "pending",
            IntentState::Done => "done",
            IntentState::Exhausted => "exhausted",
            IntentState::Abandoned => "abandoned",
            IntentState::Blocked => "blocked",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "done" => IntentState::Done,
            "exhausted" => IntentState::Exhausted,
            "abandoned" => IntentState::Abandoned,
            "blocked" => IntentState::Blocked,
            _ => IntentState::Pending,
        }
    }
}

/// A durable retry intent. `attempt` = attempts already made; the next drain runs attempt+1.
#[derive(Clone, Debug)]
pub struct RetryIntent {
    pub base_key: String,
    pub capability_id: String,
    pub operation: String,
    pub payload: Value,
    pub required_scope: String,
    pub authority_digest: String,
    pub attempt: u32,
    pub max_attempts: u32,
    pub due_at: f64,
    pub state: IntentState,
}

impl RetryIntent {
    fn to_value(&self) -> Value {
        json!({
            "base_key": self.base_key,
            "capability_id": self.capability_id,
            "operation": self.operation,
            "payload": self.payload,
            "required_scope": self.required_scope,
            "authority_digest": self.authority_digest,
            "attempt": self.attempt,
            "max_attempts": self.max_attempts,
            "due_at": self.due_at,
            "state": self.state.as_str(),
        })
    }
    fn from_value(v: &Value) -> Option<Self> {
        Some(Self {
            base_key: v.get("base_key")?.as_str()?.to_string(),
            capability_id: v.get("capability_id")?.as_str()?.to_string(),
            operation: v.get("operation")?.as_str()?.to_string(),
            payload: v.get("payload").cloned().unwrap_or(Value::Null),
            required_scope: v.get("required_scope")?.as_str()?.to_string(),
            authority_digest: v.get("authority_digest")?.as_str()?.to_string(),
            attempt: v.get("attempt")?.as_u64()? as u32,
            max_attempts: v.get("max_attempts")?.as_u64()? as u32,
            due_at: v.get("due_at")?.as_f64()?,
            state: IntentState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or("")),
        })
    }
}

/// Exponential backoff: `now + base_delay * 2^attempt`. `base_delay = 0` → always immediately due.
pub fn backoff_due(now: f64, attempt: u32, base_delay: f64) -> f64 {
    now + base_delay * 2f64.powi(attempt as i32)
}

async fn write_intent(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    intent: &RetryIntent,
) -> Result<(), EngineError> {
    let fact = Fact {
        id: format!(
            "retry:{}:a{}:{}",
            intent.base_key,
            intent.attempt,
            intent.state.as_str()
        ),
        store: RETRY_QUEUE_STORE.to_string(),
        key: intent.base_key.clone(),
        value: intent.to_value(),
        value_hash: String::new(),
        causation: None,
        transaction_time: now,
        valid_time: None,
        schema_version: 1,
        producer: Some(json!("retry-queue")),
        derivation: None,
    };
    receipts.write_fact(fact).await
}

/// Enqueue a durable retry intent (e.g. after a `retryable` outcome). Writes a pending intent
/// fact with `due_at = now + backoff(0)`. `attempt` starts at 0 (the next drain runs attempt 1).
pub async fn enqueue_retry(
    receipts: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    base: &WriteRequest,
    required_scope: &str,
    authority_digest: &str,
    max_attempts: u32,
    base_delay: f64,
) -> Result<RetryIntent, EngineError> {
    let now = clock.now();
    let intent = RetryIntent {
        base_key: base.idempotency_key.clone(),
        capability_id: base.capability_id.clone(),
        operation: base.operation.clone(),
        payload: base.payload.clone(),
        required_scope: required_scope.to_string(),
        authority_digest: authority_digest.to_string(),
        attempt: 0,
        max_attempts,
        due_at: backoff_due(now, 0, base_delay),
        state: IntentState::Pending,
    };
    write_intent(receipts, now, &intent).await?;
    Ok(intent)
}

/// Live intents: the latest fact per key in the retry-queue store.
fn current_intents(facts: Vec<Fact>) -> Vec<RetryIntent> {
    let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
    for f in facts {
        if f.store != RETRY_QUEUE_STORE {
            continue;
        }
        let e = latest
            .entry(f.key.clone())
            .or_insert((f64::NEG_INFINITY, Value::Null));
        if f.transaction_time >= e.0 {
            *e = (f.transaction_time, f.value);
        }
    }
    latest
        .into_values()
        .filter_map(|(_, v)| RetryIntent::from_value(&v))
        .collect()
}

#[derive(Clone, Debug, PartialEq)]
pub enum DrainAction {
    Committed,
    Rescheduled(f64),
    Exhausted,
    Abandoned,
    Blocked,
}

#[derive(Clone, Debug, PartialEq)]
pub struct DrainReport {
    pub base_key: String,
    pub action: DrainAction,
}

/// Drain due retry intents at `clock.now()`. For each PENDING intent whose `due_at <= now` and
/// whose `authority_digest` matches the drainer's passport, run the next attempt via
/// `run_write_effect` under the SAME reconcile-gated rules as P8. Each operation is an
/// auditable fact. Not-due intents are left untouched.
pub async fn drain_due_retries(
    registry: &CapabilityExecutorRegistry,
    receipts: &Arc<dyn TBackend>,
    substrate: &Arc<dyn TBackend>,
    clock: &Arc<dyn ClockProvider>,
    passport: &CapabilityPassport,
    base_delay: f64,
) -> Result<Vec<DrainReport>, EngineError> {
    let now = clock.now();
    let auth = passport.authority_digest();
    let intents = current_intents(receipts.all_facts().await?);
    let mut reports = Vec::new();

    for intent in intents {
        if intent.state != IntentState::Pending
            || intent.due_at > now
            || intent.authority_digest != auth
        {
            continue; // not pending / not due / not ours to drain
        }

        // bound reached → exhausted terminal.
        if intent.attempt >= intent.max_attempts {
            let mut t = intent.clone();
            t.state = IntentState::Exhausted;
            write_intent(receipts, now, &t).await?;
            reports.push(DrainReport {
                base_key: intent.base_key.clone(),
                action: DrainAction::Exhausted,
            });
            continue;
        }

        let next = intent.attempt + 1;
        let req = WriteRequest {
            capability_id: intent.capability_id.clone(),
            operation: intent.operation.clone(),
            idempotency_key: format!("{}:a{}", intent.base_key, next),
            payload: intent.payload.clone(),
        };
        let out = run_write_effect(
            registry,
            receipts,
            clock,
            passport,
            &intent.required_scope,
            &req,
            RunMode::Live,
        )
        .await?;

        let action = match out.state {
            WriteState::Committed => {
                transition(
                    receipts,
                    now,
                    &intent,
                    next,
                    IntentState::Done,
                    intent.due_at,
                    DrainAction::Committed,
                )
                .await?
            }
            WriteState::Retryable => {
                let due = backoff_due(now, next, base_delay);
                transition(
                    receipts,
                    now,
                    &intent,
                    next,
                    IntentState::Pending,
                    due,
                    DrainAction::Rescheduled(due),
                )
                .await?
            }
            WriteState::UnknownExternalState => {
                match reconcile_unknown_write(
                    receipts,
                    substrate,
                    clock,
                    &req.capability_id,
                    &req.idempotency_key,
                )
                .await?
                {
                    ReconcileResult::ResolvedCommitted => {
                        transition(
                            receipts,
                            now,
                            &intent,
                            next,
                            IntentState::Done,
                            intent.due_at,
                            DrainAction::Committed,
                        )
                        .await?
                    }
                    ReconcileResult::ResolvedPermanentFailure => {
                        // proven not landed → safe to reschedule the next attempt
                        let due = backoff_due(now, next, base_delay);
                        transition(
                            receipts,
                            now,
                            &intent,
                            next,
                            IntentState::Pending,
                            due,
                            DrainAction::Rescheduled(due),
                        )
                        .await?
                    }
                    ReconcileResult::StillUnknown | ReconcileResult::NotApplicable(_) => {
                        transition(
                            receipts,
                            now,
                            &intent,
                            next,
                            IntentState::Blocked,
                            intent.due_at,
                            DrainAction::Blocked,
                        )
                        .await?
                    }
                }
            }
            WriteState::Denied | WriteState::PermanentFailure => {
                transition(
                    receipts,
                    now,
                    &intent,
                    next,
                    IntentState::Abandoned,
                    intent.due_at,
                    DrainAction::Abandoned,
                )
                .await?
            }
            WriteState::Prepared | WriteState::Aborted => {
                transition(
                    receipts,
                    now,
                    &intent,
                    next,
                    IntentState::Blocked,
                    intent.due_at,
                    DrainAction::Blocked,
                )
                .await?
            }
        };
        reports.push(DrainReport {
            base_key: intent.base_key.clone(),
            action,
        });
    }

    Ok(reports)
}

#[allow(clippy::too_many_arguments)]
async fn transition(
    receipts: &Arc<dyn TBackend>,
    now: f64,
    intent: &RetryIntent,
    attempt: u32,
    state: IntentState,
    due_at: f64,
    action: DrainAction,
) -> Result<DrainAction, EngineError> {
    let mut t = intent.clone();
    t.attempt = attempt;
    t.state = state;
    t.due_at = due_at;
    write_intent(receipts, now, &t).await?;
    Ok(action)
}
