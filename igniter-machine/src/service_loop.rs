//! ServiceLoop host entrypoint (LAB-MACHINE-CAPABILITY-IO-P2).
//!
//! Connects a **declared-effect contract** to the capability runtime. A contract's IR
//! already carries its effect surface (`modifier`, `capabilities`[{name,type}],
//! `effects`[{name,capability_ref}]); this host entrypoint discovers that surface,
//! validates the effect → capability → executor binding, and routes through `run_effect`:
//!
//! ```text
//! loaded program (declared-effect contract)
//! -> discover declared effect/capability surface (from existing IR — no new SIR)
//! -> ServiceLoop host entrypoint: validate binding + authority + idempotency
//! -> run_effect(...) -> fake executor OR receipt replay
//! -> receipt fact written/read -> typed response
//! ```
//!
//! The contract **body stays pure** — the host performs the effect through an executor,
//! never the contract. This is machine-host IO, NOT language IO.

use crate::capability::{
    run_effect, CapabilityExecutorRegistry, EffectOutcome, EffectRequest, RunMode,
};
use crate::errors::EngineError;
use crate::machine::IgniterMachine;
use serde_json::Value;

/// The declared effect surface of a contract, read from its already-emitted IR fields.
#[derive(Debug, Clone)]
pub struct EffectDescriptor {
    pub contract: String,
    pub modifier: String,
    /// capability name → capability *type* (the executor id),
    /// e.g. `"storage"` → `"IO.StorageCapability"`.
    pub capabilities: Vec<(String, String)>,
    /// effect name → capability_ref (the capability name it uses),
    /// e.g. `"read_file"` → `"storage"`.
    pub effects: Vec<(String, String)>,
}

impl EffectDescriptor {
    /// A `pure` contract declaring no effects performs no external IO.
    pub fn is_pure(&self) -> bool {
        self.modifier == "pure" && self.effects.is_empty()
    }

    /// Resolve a declared effect to its capability *type* (the executor id) via its
    /// `capability_ref`. `None` if the effect is not declared or its capability is unknown.
    pub fn capability_type_for(&self, effect_name: &str) -> Option<String> {
        let cap_ref = self
            .effects
            .iter()
            .find(|(n, _)| n == effect_name)
            .map(|(_, r)| r)?;
        self.capabilities
            .iter()
            .find(|(n, _)| n == cap_ref)
            .map(|(_, t)| t.clone())
            .filter(|t| !t.is_empty())
    }
}

/// Discover the declared effect/capability surface of a registered contract.
/// Verify-first: reads exactly the IR the compiler already emits — `modifier`,
/// `capabilities` (`{name, type:{name}}`), `effects` (`{name, capability_ref}`).
pub fn discover_effect_surface(
    machine: &IgniterMachine,
    contract: &str,
) -> Result<EffectDescriptor, EngineError> {
    let cj = {
        let reg = machine.registry.read();
        reg.get(contract).cloned()
    }
    .ok_or(EngineError::NotFound)?;

    let modifier = cj
        .get("modifier")
        .and_then(|m| m.as_str())
        .unwrap_or("pure")
        .to_string();

    let capabilities = cj
        .get("capabilities")
        .and_then(|c| c.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|c| {
                    let name = c.get("name")?.as_str()?.to_string();
                    // type is `{name, params}` in the IR; fall back to a bare string.
                    let ty = c
                        .get("type")
                        .and_then(|t| t.get("name"))
                        .and_then(|n| n.as_str())
                        .or_else(|| c.get("type").and_then(|t| t.as_str()))
                        .unwrap_or("")
                        .to_string();
                    Some((name, ty))
                })
                .collect()
        })
        .unwrap_or_default();

    let effects = cj
        .get("effects")
        .and_then(|e| e.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|e| {
                    let name = e.get("name")?.as_str()?.to_string();
                    let cap_ref = e.get("capability_ref")?.as_str()?.to_string();
                    Some((name, cap_ref))
                })
                .collect()
        })
        .unwrap_or_default();

    Ok(EffectDescriptor {
        contract: contract.to_string(),
        modifier,
        capabilities,
        effects,
    })
}

/// A host request to perform a declared effect of a loaded contract.
pub struct HostRequest {
    pub contract: String,
    /// Which declared effect of the contract to perform (e.g. `"read_file"`).
    pub effect: String,
    pub idempotency_key: String,
    pub authority_ref: Option<String>,
    pub args: Value,
}

/// The ServiceLoop host entrypoint. Discovers the contract's declared effect surface,
/// resolves the effect → capability → executor binding, then routes through `run_effect`
/// (which enforces authority/idempotency preflight + receipt/idempotency/replay).
///
/// Receipts are written to the machine's own `TBackend` (`machine.storage`), so effect
/// receipts live alongside domain facts. The contract body is never executed for IO here.
pub async fn run_service(
    machine: &IgniterMachine,
    registry: &CapabilityExecutorRegistry,
    req: &HostRequest,
    mode: RunMode,
) -> Result<EffectOutcome, EngineError> {
    let surface = discover_effect_surface(machine, &req.contract)?;

    // A pure contract declares no effect to perform. This entrypoint is for declared
    // effects only; pure contracts go through `dispatch` (no executor, no receipt).
    if surface.is_pure() {
        return Ok(EffectOutcome::denied(
            "preflight: contract declares no effect (pure)",
        ));
    }

    // Resolve the declared effect → its capability type (the executor id). Refuse here,
    // before any executor, if the contract does not declare this effect.
    let capability_id = match surface.capability_type_for(&req.effect) {
        Some(t) => t,
        None => {
            return Ok(EffectOutcome::denied(
                "preflight: effect not declared by contract",
            ))
        }
    };

    let effect_req = EffectRequest {
        capability_id,
        idempotency_key: req.idempotency_key.clone(),
        authority_ref: req.authority_ref.clone(),
        args: req.args.clone(),
    };
    run_effect(registry, &machine.storage, &effect_req, mode).await
}
