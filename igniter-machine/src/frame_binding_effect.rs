//! ViewArtifact action → capability-IO effect bridge
//! (LAB-FRAME-IG-BINDING-EFFECT-BRIDGE-P18).
//!
//! HOST-SIDE. The next step after P17: P17 ran a declared action through `CoordinationHub::invoke`
//! and returned the real capsule activation result. P18 performs that result as a DECLARED EFFECT
//! through the capability-IO substrate, writing a receipt:
//!
//! ```text
//!   declared ViewArtifact action
//!     -> [P17 gates] declared + registered + recipe-match
//!     -> CoordinationHub::invoke(SERVING passport, pool)   = real capsule activation (pure)
//!     -> capsule output is DATA (the effect payload)
//!     -> validate the action's declared `effect` intent
//!     -> run_write_effect_atomic(HOST effect passport, …)  = the host PERFORMS the effect
//!     -> receipt in __receipts__ + state/id back to the caller
//! ```
//!
//! DOUBLE AUTHORITY: the serving passport authorizes capsule activation (who may call the service);
//! a SEPARATE host effect passport authorizes the downstream capability-IO effect. Vendor/browser
//! authority is never reused for the effect. This composes existing surfaces — `FrameBindingBridge`
//! (P17) for the gated invoke and `run_write_effect_atomic` for the effect — with no new primitive.
//! Serving-line refusals and effect-line outcomes stay distinct. Local + proof-scoped: fake
//! executor only, no real HTTP/TLS/SparkCRM/network.

use crate::backend::TBackend;
use crate::capability::{CapabilityExecutorRegistry, CapabilityPassport, RunMode};
use crate::clock::ClockProvider;
use crate::coordination::CoordinationHub;
use crate::frame_binding::{FrameBindingBridge, FrameBindingRefusal, FrameBindingResult};
use crate::registry::ContractRegistry;
use crate::single_flight::{run_write_effect_atomic, SingleFlight};
use crate::write::{WriteRequest, WriteState};
use serde_json::{json, Value};
use std::sync::Arc;

/// The effect block declared by a ViewArtifact action (`actions.<name>.effect`).
#[derive(Debug, Clone, PartialEq)]
pub struct EffectDecl {
    pub capability_id: String,
    pub operation: String,
    pub scope: String,
}

/// Why a bound effect action did not complete.
#[derive(Debug)]
pub enum FrameBindingEffectRefusal {
    /// A P17 gate refused (declared / registered / recipe-match / coordination invoke).
    Binding(FrameBindingRefusal),
    /// The declared effect intent is absent or malformed — refused BEFORE the executor.
    MalformedEffect(String),
    /// The capability-IO substrate errored (not a normal refusal/outcome).
    EffectError(String),
}

/// The result of a bound effect action: the capsule activation result + the capability-IO receipt.
#[derive(Debug)]
pub struct FrameBindingEffectResult {
    pub invoke_result: Value,      // the real capsule activation output
    pub receipt_state: WriteState, // the capability-IO outcome (committed / unknown / denied / …)
    pub receipt_key: String,       // "<capability_id>:<idempotency_key>" (the receipt id, no secret)
    pub result: Value,             // the effect's returned value
}

impl FrameBindingEffectResult {
    /// Project this host bridge result into a plain `HostActionRecord`-shaped JSON for a frame
    /// console (LAB-FRAME-BINDING-CONSOLE-E2E-P20). The console consumes DATA only; this conversion
    /// stays HOST-SIDE — it carries an id/state/digest, never a secret, passport, or machine handle.
    pub fn to_host_action_json(
        &self,
        action_id: &str,
        action_name: &str,
        contract: &str,
        pool_id: &str,
        idempotency_key: &str,
        correlation_id: &str,
    ) -> Value {
        let hex = blake3::hash(serde_json::to_string(&self.invoke_result).unwrap_or_default().as_bytes()).to_hex();
        json!({
            "action_id": action_id,
            "action_name": action_name,
            "contract": contract,
            "pool_id": pool_id,
            "invoke_digest": format!("blake3:{}", &hex[..16]),
            "effect_receipt_id": self.receipt_key,
            "effect_state": self.receipt_state.as_str(),
            "idempotency_key": idempotency_key,
            "correlation_id": correlation_id,
        })
    }
}

/// The effect bridge. Stateless over: the contract `registry` (P17 declaration gate), the capability
/// executor `registry`, the receipts store, the clock, the HOST effect passport, and the single-flight
/// gate (exactly-once per idempotency key).
pub struct FrameBindingEffectBridge<'a> {
    pub contracts: &'a ContractRegistry,
    pub executors: &'a CapabilityExecutorRegistry,
    pub receipts: &'a Arc<dyn TBackend>,
    pub clock: &'a Arc<dyn ClockProvider>,
    pub effect_passport: &'a CapabilityPassport,
    pub single_flight: &'a SingleFlight,
}

impl FrameBindingEffectBridge<'_> {
    /// Validate the action's declared `effect` block (capability_id required; operation/scope default).
    fn parse_effect(artifact_json: &str, action_name: &str) -> Result<EffectDecl, FrameBindingEffectRefusal> {
        let v: Value = serde_json::from_str(artifact_json)
            .map_err(|e| FrameBindingEffectRefusal::MalformedEffect(format!("bad artifact json: {e}")))?;
        let eff = v
            .get("actions")
            .and_then(|a| a.get(action_name))
            .and_then(|a| a.get("effect"))
            .ok_or_else(|| FrameBindingEffectRefusal::MalformedEffect(format!("actions.{action_name}.effect missing")))?;
        let cap = eff
            .get("capability_id")
            .and_then(|c| c.as_str())
            .ok_or_else(|| FrameBindingEffectRefusal::MalformedEffect("effect.capability_id missing".into()))?;
        Ok(EffectDecl {
            capability_id: cap.to_string(),
            operation: eff.get("operation").and_then(|o| o.as_str()).unwrap_or("perform").to_string(),
            scope: eff.get("scope").and_then(|s| s.as_str()).unwrap_or("write").to_string(),
        })
    }

    /// Run the P17 gated invoke (SERVING authority), then perform the capsule output as the declared
    /// capability-IO effect (HOST authority) → receipt. Idempotent per `idempotency_key`.
    pub async fn handle_effect_action(
        &self,
        artifact_json: &str,
        action_name: &str,
        invoke_payload: Value,
        idempotency_key: &str,
        serving_passport: &CapabilityPassport,
        pool_id: &str,
        hub: &CoordinationHub,
    ) -> Result<FrameBindingEffectResult, FrameBindingEffectRefusal> {
        // P17 gates 1-3 + real capsule activation under the SERVING passport
        let invoke_result = match FrameBindingBridge::handle_action(
            artifact_json, action_name, invoke_payload, serving_passport, pool_id, hub, self.contracts,
        )
        .await
        {
            FrameBindingResult::Ok(v) => v,
            FrameBindingResult::Refused(r) => return Err(FrameBindingEffectRefusal::Binding(r)),
        };

        // validate the declared effect intent BEFORE the executor (no effect/receipt if malformed)
        let effect = Self::parse_effect(artifact_json, action_name)?;
        if idempotency_key.is_empty() {
            return Err(FrameBindingEffectRefusal::MalformedEffect("missing idempotency_key".into()));
        }

        // the capsule output is DATA; the HOST performs the effect through capability-IO
        let req = WriteRequest {
            capability_id: effect.capability_id.clone(),
            operation: effect.operation.clone(),
            idempotency_key: idempotency_key.to_string(),
            payload: json!({ "result": invoke_result }),
        };
        let outcome = run_write_effect_atomic(
            self.single_flight,
            self.executors,
            self.receipts,
            self.clock,
            self.effect_passport, // HOST authority — distinct from the serving passport
            &effect.scope,
            &req,
            RunMode::Live,
        )
        .await
        .map_err(|e| FrameBindingEffectRefusal::EffectError(e.to_string()))?;

        Ok(FrameBindingEffectResult {
            invoke_result,
            receipt_state: outcome.state,
            receipt_key: format!("{}:{}", effect.capability_id, idempotency_key),
            result: outcome.result,
        })
    }
}
