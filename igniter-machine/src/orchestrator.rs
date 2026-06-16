//! Host-driven effect orchestrator (LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20).
//!
//! The pieces exist (P7/P13 reconcile, P9 retry queue, P12 compensation, P19 recovery) but were
//! driven by hand. P20 ties them into an EXPLICIT, host-called control loop — NOT a background
//! daemon and NOT an infinite loop. The host owns the cadence:
//!
//! ```text
//! boot()   -> P19 recovery sweep (reconcile dangling prepared/unknown); dead-letter what stays
//!             unresolved. Idempotent across restarts.
//! tick()   -> drain DUE retry intents (P9); dead-letter exhausted/blocked intents.
//! report() -> a status snapshot (receipt states + dead-letters).
//! ```
//!
//! Every action writes an audit/status fact — nothing is silently skipped. Compensation (P12)
//! stays EXPLICIT and is intentionally NOT driven from the loop (reversing a committed effect is a
//! host decision, never automatic). No live network.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RECEIPTS_STORE};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use crate::recovery::{recover_dangling_writes, RecoveryReport};
use crate::retry_queue::{drain_due_retries, DrainAction, DrainReport};
use crate::write::WriteState;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

pub const ORCHESTRATOR_AUDIT_STORE: &str = "__orchestrator_audit__";
pub const DEAD_LETTER_STORE: &str = "__dead_letter__";

/// A host-called control loop over the existing effect primitives.
pub struct EffectOrchestrator<'a> {
    pub receipts: &'a Arc<dyn TBackend>,
    pub substrate: &'a Arc<dyn TBackend>,
    pub registry: &'a CapabilityExecutorRegistry,
    pub clock: &'a Arc<dyn ClockProvider>,
    pub passport: &'a CapabilityPassport,
    pub base_delay: f64,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct OrchestratorStatus {
    pub receipts_committed: usize,
    pub receipts_unknown: usize,
    pub receipts_prepared: usize, // dangling — should be 0 after a successful boot
    pub dead_letters: usize,      // distinct dead-lettered keys
}

impl EffectOrchestrator<'_> {
    async fn put(&self, store: &str, key: &str, value: Value) -> Result<(), EngineError> {
        let fact = Fact {
            id: format!("{store}:{key}"),
            store: store.to_string(),
            key: key.to_string(),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("orchestrator")),
            derivation: None,
        };
        self.receipts.write_fact(fact).await
    }
    async fn audit(&self, op: &str, detail: Value) -> Result<(), EngineError> {
        self.put(ORCHESTRATOR_AUDIT_STORE, op, json!({ "op": op, "detail": detail })).await
    }
    async fn dead_letter(&self, kind: &str, key: &str, reason: &str) -> Result<(), EngineError> {
        self.put(DEAD_LETTER_STORE, &format!("{kind}:{key}"), json!({ "kind": kind, "key": key, "reason": reason })).await
    }

    /// Latest receipt fact per key (last-wins by tx-time), within the receipts store.
    async fn latest_receipts(&self) -> Result<Vec<(String, Value)>, EngineError> {
        let all = self.receipts.all_facts().await?;
        let mut latest: HashMap<String, (f64, Value)> = HashMap::new();
        for f in all {
            if f.store != RECEIPTS_STORE {
                continue;
            }
            let e = latest.entry(f.key.clone()).or_insert((f64::NEG_INFINITY, Value::Null));
            if f.transaction_time >= e.0 {
                *e = (f.transaction_time, f.value);
            }
        }
        Ok(latest.into_iter().map(|(k, (_, v))| (k, v)).collect())
    }

    /// Boot recovery: reconcile dangling `prepared`/`unknown` receipts (P19). Any receipt still
    /// unresolved (prepared/unknown) after the attempt is dead-lettered — no silent skip.
    /// Idempotent: once everything is terminal a second boot recovers nothing.
    pub async fn boot(&self) -> Result<RecoveryReport, EngineError> {
        let report = recover_dangling_writes(self.receipts, self.substrate, self.clock).await?;
        for (key, v) in self.latest_receipts().await? {
            let state = WriteState::from_str(v.get("state").and_then(|s| s.as_str()).unwrap_or(""));
            if matches!(state, WriteState::Prepared | WriteState::UnknownExternalState) {
                self.dead_letter("receipt", &key, "unresolved after recovery").await?;
            }
        }
        self.audit("boot", json!({
            "scanned": report.scanned, "committed": report.committed,
            "permanent_failure": report.permanent_failure, "still_unknown": report.still_unknown,
        }))
        .await?;
        Ok(report)
    }

    /// One control tick: drain DUE retry intents (P9). Exhausted/blocked intents are dead-lettered.
    /// Does NOT loop — the host calls `tick` on its own cadence.
    pub async fn tick(&self) -> Result<Vec<DrainReport>, EngineError> {
        let reports = drain_due_retries(self.registry, self.receipts, self.substrate, self.clock, self.passport, self.base_delay).await?;
        for r in &reports {
            if matches!(r.action, DrainAction::Exhausted | DrainAction::Blocked) {
                self.dead_letter("retry_intent", &r.base_key, &format!("{:?}", r.action)).await?;
            }
        }
        self.audit("tick", json!({ "drained": reports.len() })).await?;
        Ok(reports)
    }

    /// A status snapshot — receipt states + distinct dead-lettered keys.
    pub async fn report(&self) -> Result<OrchestratorStatus, EngineError> {
        let mut s = OrchestratorStatus::default();
        for (_k, v) in self.latest_receipts().await? {
            match WriteState::from_str(v.get("state").and_then(|x| x.as_str()).unwrap_or("")) {
                WriteState::Committed => s.receipts_committed += 1,
                WriteState::UnknownExternalState => s.receipts_unknown += 1,
                WriteState::Prepared => s.receipts_prepared += 1,
                _ => {}
            }
        }
        let dead: HashSet<String> = self
            .receipts
            .all_facts()
            .await?
            .into_iter()
            .filter(|f| f.store == DEAD_LETTER_STORE)
            .map(|f| f.key)
            .collect();
        s.dead_letters = dead.len();
        Ok(s)
    }
}
