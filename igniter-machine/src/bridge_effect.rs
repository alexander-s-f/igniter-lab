//! Service↔effect bridge (LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16).
//!
//! Ties the two completed lines together. The COORDINATION serving line (`ingress` →
//! `CoordinationHub::invoke`) activates a served capsule and yields its output. The CAPABILITY-IO
//! line then performs that output as a DECLARED EFFECT (`run_write_effect` → receipt) with the
//! full stack: idempotency, authority, reconciliation, retry, compensation.
//!
//! ```text
//! vendor webhook
//!   -> hub.invoke(serving_passport, pool)   = real capsule activation (resume + dispatch, pure)
//!   -> capsule output = the effect INTENT
//!   -> run_write_effect(effect_passport, …) = the host PERFORMS the effect (receipt)
//!   -> map effect outcome → HTTP response
//! ```
//!
//! TWO authorities, by design: the **vendor** passport authorizes the pool activation (who may
//! call the service); the **host** effect passport authorizes the downstream effect (the
//! machine's own authority to mutate the external substrate on the vendor's behalf). The capsule
//! body still does no IO — it only produces the pure intent; the host executes it.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::coordination::CoordinationHub;
use crate::ingress::{map_refusal, IngressRequest};
use crate::write::{run_write_effect, WriteRequest, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

pub struct BridgeOutcome {
    pub status: u16,
    pub body: Value,
    /// `None` if the effect never ran (serving refusal / missing idempotency key).
    pub write_state: Option<WriteState>,
    pub correlation_id: String,
}

/// Bridges a coordination service pool to a capability-IO effect. The effect executor (any
/// `CapabilityExecutor` — fake, TBackend write, or the P15 SparkCRM executor) lives in `registry`.
pub struct ServiceEffectBridge<'a> {
    pub registry: &'a CapabilityExecutorRegistry,
    pub receipts: &'a Arc<dyn TBackend>,
    pub clock: &'a Arc<dyn ClockProvider>,
    /// The HOST's authority to perform the downstream effect (distinct from the vendor passport).
    pub effect_passport: &'a CapabilityPassport,
    pub capability_id: String,
    pub operation: String,
    pub scope: String,
}

impl ServiceEffectBridge<'_> {
    /// webhook → capsule activation (serving auth) → declared effect (capability-IO) → response.
    pub async fn serve(
        &self,
        hub: &CoordinationHub,
        serving_passport: &CapabilityPassport,
        pool_id: &str,
        webhook: &IngressRequest,
    ) -> BridgeOutcome {
        let correlation = webhook.header("x-correlation-id").unwrap_or("cid-none").to_string();
        let idem = webhook.header("idempotency-key").unwrap_or("").to_string();

        // 1. Activate the served capsule (coordination authority: pool ACL + recipe + production).
        let intent = match hub.invoke(serving_passport, pool_id, webhook.body.clone()).await {
            Ok(v) => v,
            Err(e) => {
                let (status, body) = map_refusal(&e);
                return BridgeOutcome { status, body, write_state: None, correlation_id: correlation };
            }
        };

        // 2. An effect requires an idempotency key — fail closed (webhook supplies it).
        if idem.is_empty() {
            return BridgeOutcome {
                status: 400,
                body: json!({ "error": "missing idempotency-key for effect" }),
                write_state: None,
                correlation_id: correlation,
            };
        }

        // 3. Perform the capsule's output as a declared effect through the capability-IO substrate.
        let write_req = WriteRequest {
            capability_id: self.capability_id.clone(),
            operation: self.operation.clone(),
            idempotency_key: idem,
            payload: json!({ "intent": intent, "correlation_id": correlation }),
        };
        let outcome = match run_write_effect(
            self.registry,
            self.receipts,
            self.clock,
            self.effect_passport,
            &self.scope,
            &write_req,
            RunMode::Live,
        )
        .await
        {
            Ok(o) => o,
            Err(_) => {
                return BridgeOutcome {
                    status: 500,
                    body: json!({ "error": "effect error" }),
                    write_state: None,
                    correlation_id: correlation,
                }
            }
        };

        // 4. Map the effect outcome → HTTP (the epistemic taxonomy reaches the edge).
        let (status, body) = match outcome.state {
            WriteState::Committed => (200, json!({ "status": "committed", "result": outcome.result })),
            // accepted but the external fate is unknown → 202; resolve later via reconcile (P7/P13).
            WriteState::UnknownExternalState => (202, json!({ "status": "accepted_unknown", "correlation_id": correlation })),
            WriteState::Denied => (403, json!({ "status": "denied", "detail": outcome.detail })),
            WriteState::Retryable => (503, json!({ "status": "retry_later" })),
            WriteState::PermanentFailure => (502, json!({ "status": "failed", "detail": outcome.detail })),
            other => (500, json!({ "status": format!("{other:?}") })),
        };
        BridgeOutcome { status, body, write_state: Some(outcome.state), correlation_id: correlation }
    }
}
