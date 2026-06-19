//! ViewArtifact action → real `CoordinationHub` serving bridge
//! (LAB-FRAME-IG-BINDING-MACHINE-BRIDGE-P17).
//!
//! HOST-SIDE. This replaces P16's fixture executor with the REAL serving invoke path: a declared
//! ViewArtifact action resolves to a registered contract and is executed by activating a real
//! capsule through `CoordinationHub::invoke` (passport + production pool + signed recipe). It lives
//! in `igniter-machine` precisely so that `igniter-ui-kit` / the browser stay machine-free — the UI
//! emits a declared action *request*; this host bridge runs it.
//!
//! Scope of this card: serving INVOKE only. It does NOT run a capability-IO write effect or produce
//! a `__receipts__` receipt (that is a later effect-bridge card). The `ContractRegistry` is a
//! declaration/metadata gate here, not an executor — the executor is the coordination invoke path.
//!
//! The gates, in order:
//!   1. declared   — `actions.<name>` exists in the ViewArtifact manifest;
//!   2. registered — `action.contract` is in the host `ContractRegistry`;
//!   3. recipe     — `action.contract` matches the pool's accepted `ServiceRecipe.entry_contract`;
//!   (1)-(3) refuse BEFORE invoke. Then `CoordinationHub::invoke` enforces passport/grant/production.

use crate::capability::CapabilityPassport;
use crate::coordination::{CoordinationHub, PoolRefusal};
use crate::registry::ContractRegistry;
use serde_json::Value;

/// The minimal action parsed from a ViewArtifact `actions.<name>` entry (no UI compile).
#[derive(Debug, Clone, PartialEq)]
pub struct FrameBindingAction {
    pub name: String,
    pub contract: String,
}

/// Why a bound action did not execute. Distinct variants so the refusal is precise.
#[derive(Debug, Clone)]
pub enum FrameBindingRefusal {
    BadArtifact(String),         // not parseable JSON
    MissingDeclaration(String),  // gate 1: not in the manifest
    NotRegistered(String),       // gate 2: not in the ContractRegistry
    NoRecipe(String),            // no accepted recipe for the pool
    RecipeMismatch { action: String, recipe: String }, // gate 3
    Pool(PoolRefusal),           // the coordination invoke gate (passport / grant / production)
}

/// The outcome of `handle_action`.
#[derive(Debug)]
pub enum FrameBindingResult {
    Ok(Value),
    Refused(FrameBindingRefusal),
}

impl FrameBindingResult {
    pub fn ok(&self) -> Option<&Value> {
        match self {
            FrameBindingResult::Ok(v) => Some(v),
            _ => None,
        }
    }
    pub fn refusal(&self) -> Option<&FrameBindingRefusal> {
        match self {
            FrameBindingResult::Refused(r) => Some(r),
            _ => None,
        }
    }
}

/// The host bridge. Stateless: it composes a parsed manifest, a `ContractRegistry` (the declaration
/// gate), and a `CoordinationHub` (the real executor).
pub struct FrameBindingBridge;

impl FrameBindingBridge {
    /// Parse just `actions.<action_name>` from a ViewArtifact JSON string. No rendering/compiling.
    pub fn parse_action(artifact_json: &str, action_name: &str) -> Result<FrameBindingAction, FrameBindingRefusal> {
        let v: Value = serde_json::from_str(artifact_json).map_err(|e| FrameBindingRefusal::BadArtifact(e.to_string()))?;
        let action = v
            .get("actions")
            .and_then(|a| a.get(action_name))
            .ok_or_else(|| FrameBindingRefusal::MissingDeclaration(format!("actions.{action_name}")))?;
        let contract = action
            .get("contract")
            .and_then(|c| c.as_str())
            .ok_or_else(|| FrameBindingRefusal::MissingDeclaration(format!("actions.{action_name}.contract")))?;
        Ok(FrameBindingAction { name: action_name.to_string(), contract: contract.to_string() })
    }

    /// Resolve + execute one declared action through the real coordination serving path.
    ///
    /// Gates 1-3 (declared / registered / recipe-match) refuse before any invoke. The
    /// passport/grant/production gate is enforced inside `CoordinationHub::invoke`. Returns the real
    /// capsule result (e.g. `5` for `Add{a:2,b:3}`) or a precise refusal.
    pub async fn handle_action(
        artifact_json: &str,
        action_name: &str,
        payload: Value,
        passport: &CapabilityPassport,
        pool_id: &str,
        hub: &CoordinationHub,
        registry: &ContractRegistry,
    ) -> FrameBindingResult {
        // gate 1: declared in the artifact manifest
        let action = match Self::parse_action(artifact_json, action_name) {
            Ok(a) => a,
            Err(r) => return FrameBindingResult::Refused(r),
        };
        // gate 2: registered in the host ContractRegistry (declaration/metadata authority)
        if registry.get(&action.contract).is_none() {
            return FrameBindingResult::Refused(FrameBindingRefusal::NotRegistered(action.contract));
        }
        // gate 3: the action contract must match the pool's accepted recipe entry contract
        match hub.read_recipe(pool_id).await {
            Some(recipe) => {
                if recipe.entry_contract != action.contract {
                    return FrameBindingResult::Refused(FrameBindingRefusal::RecipeMismatch {
                        action: action.contract,
                        recipe: recipe.entry_contract,
                    });
                }
            }
            None => return FrameBindingResult::Refused(FrameBindingRefusal::NoRecipe(pool_id.to_string())),
        }
        // execute: the REAL serving invoke — passport / grant / production gate enforced inside
        match hub.invoke(passport, pool_id, payload).await {
            Ok(v) => FrameBindingResult::Ok(v),
            Err(pr) => FrameBindingResult::Refused(FrameBindingRefusal::Pool(pr)),
        }
    }
}
