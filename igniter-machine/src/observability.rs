//! Observability projection (LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23).
//!
//! Operator visibility, NOT a monitoring stack. Metrics are AGGREGATED FROM THE FACTS (receipts /
//! retry queue / dead-letters) — a pure read-only projection, never a parallel counter side-log.
//! The audit facts remain the single source of truth; `observe()` just summarizes them and the
//! `DeadLetterInbox` groups stuck items by reason. Export is a plain JSON struct for a host /
//! operator UI. No metrics daemon, no Prometheus dependency, no live network.

use crate::backend::TBackend;
use crate::capability::RECEIPTS_STORE;
use crate::errors::EngineError;
use crate::orchestrator::DEAD_LETTER_STORE;
use crate::retry_queue::RETRY_QUEUE_STORE;
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct EffectMetrics {
    // effects by latest receipt state
    pub committed: usize,
    pub denied: usize,
    pub unknown: usize,
    pub permanent_failure: usize,
    pub retryable: usize,
    pub prepared: usize, // dangling
    pub aborted: usize,  // compensated
    // derived from receipt details (executor-reached only; pre-executor refusals write no receipt)
    pub auth_refusals: usize,
    pub secret_missing: usize,
    pub compensation: usize, // = aborted
    // retry queue intents by state
    pub retry_pending: usize,
    pub retry_exhausted: usize,
    pub retry_done: usize,
    pub retry_blocked: usize,
    pub retry_abandoned: usize,
    // dead-letters
    pub dead_letters: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DeadLetter {
    pub key: String,
    pub kind: String,
    pub reason: String,
    /// Joined from the matching receipt when available.
    pub correlation: Option<String>,
}

#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct DeadLetterInbox {
    pub total: usize,
    pub by_reason: BTreeMap<String, usize>,
    pub entries: Vec<DeadLetter>,
}

#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct ObservabilitySnapshot {
    pub metrics: EffectMetrics,
    pub dead_letters: DeadLetterInbox,
}

impl ObservabilitySnapshot {
    /// Export as a JSON struct for a host / operator UI.
    pub fn to_json(&self) -> Value {
        serde_json::to_value(self).unwrap_or(Value::Null)
    }
}

fn latest_by_key(all: &[crate::fact::Fact], store: &str) -> HashMap<String, Value> {
    let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
    for f in all {
        if f.store != store {
            continue;
        }
        let e = latest
            .entry(f.key.clone())
            .or_insert((f64::NEG_INFINITY, Value::Null));
        // P4: latest by (transaction_time, receipt_seq) — same tie-break helper as the write
        // resolution + recovery sweep (receipt facts carry `receipt_seq`; other stores read it as 0,
        // degrading to the prior wall-clock-only behavior).
        if crate::capability::receipt_is_newer_or_equal(f.transaction_time, &f.value, e.0, &e.1) {
            *e = (f.transaction_time, f.value.clone());
        }
    }
    latest.into_iter().map(|(k, (_, v))| (k, v)).collect()
}

/// Aggregate an observability snapshot by reading the fact stores — a pure projection.
pub async fn observe(facts: &Arc<dyn TBackend>) -> Result<ObservabilitySnapshot, EngineError> {
    let all = facts.all_facts().await?;
    let mut m = EffectMetrics::default();
    let mut corr_by_key: HashMap<String, String> = HashMap::new();

    for (key, v) in latest_by_key(&all, RECEIPTS_STORE) {
        let state = v.get("state").and_then(|s| s.as_str()).unwrap_or("");
        let detail = v.get("detail").and_then(|d| d.as_str()).unwrap_or("");
        let failure = v.get("failure_kind").and_then(|d| d.as_str()).unwrap_or("");
        let text = format!("{detail} {failure}").to_lowercase();
        match state {
            "committed" => m.committed += 1,
            "denied" => {
                m.denied += 1;
                if text.contains("authority") {
                    m.auth_refusals += 1;
                }
            }
            "unknown_external_state" => m.unknown += 1,
            "permanent_failure" => {
                m.permanent_failure += 1;
                if text.contains("credential") || text.contains("secret") {
                    m.secret_missing += 1;
                }
            }
            "retryable" => m.retryable += 1,
            "prepared" => m.prepared += 1,
            "aborted" => m.aborted += 1,
            _ => {}
        }
        if let Some(c) = v.get("correlation_id").and_then(|c| c.as_str()) {
            if !c.is_empty() {
                corr_by_key.insert(key, c.to_string());
            }
        }
    }
    m.compensation = m.aborted;

    for (_k, v) in latest_by_key(&all, RETRY_QUEUE_STORE) {
        match v.get("state").and_then(|s| s.as_str()).unwrap_or("") {
            "pending" => m.retry_pending += 1,
            "exhausted" => m.retry_exhausted += 1,
            "done" => m.retry_done += 1,
            "blocked" => m.retry_blocked += 1,
            "abandoned" => m.retry_abandoned += 1,
            _ => {}
        }
    }

    let mut inbox = DeadLetterInbox::default();
    for (_k, v) in latest_by_key(&all, DEAD_LETTER_STORE) {
        let key = v
            .get("key")
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string();
        let kind = v
            .get("kind")
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string();
        let reason = v
            .get("reason")
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string();
        let correlation = corr_by_key.get(&key).cloned();
        *inbox.by_reason.entry(reason.clone()).or_insert(0) += 1;
        inbox.entries.push(DeadLetter {
            key,
            kind,
            reason,
            correlation,
        });
    }
    inbox.entries.sort_by(|a, b| a.key.cmp(&b.key));
    inbox.total = inbox.entries.len();
    m.dead_letters = inbox.total;

    Ok(ObservabilitySnapshot {
        metrics: m,
        dead_letters: inbox,
    })
}
