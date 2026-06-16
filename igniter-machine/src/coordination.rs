//! Agent / pool coordination foundation (LAB-MACHINE-AGENT-POOLS-P2).
//!
//! The first foundation brick of the agent-coordination substrate (front door:
//! `LAB-MACHINE-AGENT-COORDINATION-META-P1`). It is **Capability IO applied to coordination**:
//!
//! ```text
//! subject action
//!   -> CapabilityPassport authenticates the SUBJECT (who)        (P5 verify_passport)
//!   -> Pool ACL authorizes the OPERATION on the POOL (what)      (this module)
//!   -> every operation writes an AuditEvent fact                 (receipt principle, P1)
//! ```
//!
//! **Passport ≠ ACL**: the passport says *who you are and which op-classes you may ever do*;
//! the ACL says *which pools you may do them on*. Both are checked. Every op (allowed OR
//! denied) writes a bitemporal audit fact. The developer (`kind == Developer`) is the local
//! root-of-trust / conductor — privileged but fully audited, never an invisible root.
//!
//! P2 scope: registries + ACL + audit + content-addressed capsule refs + audited ownership
//! transfer. NO messenger (P3), NO transfer envelope (P4), NO production serving, NO federation.
//! The schema deliberately does NOT preclude production mode (visibility `Production`, a free
//! `String` actor that can later be `vendor:*` / `RuntimeActor`, transferable ownership).

use crate::backend::TBackend;
use crate::capability::{verify_passport, AuthRefusal, CapabilityPassport};
use crate::clock::ClockProvider;
use crate::errors::EngineError;
use crate::fact::Fact;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

/// The capability id every coordination passport authenticates against.
pub const COORDINATION_CAPABILITY: &str = "coordination";
/// Audit facts live in their own bitemporal store namespace (not the IO `__receipts__`).
pub const COORD_AUDIT_STORE: &str = "__coord_audit__";

// ── identities ─────────────────────────────────────────────────────────────────

/// Participant class. `RuntimeActor` exists in the schema for the future agentless
/// production mode (e.g. a `vendor:*` webhook caller) — it is NOT served in P2.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AgentKind {
    Agent,
    Developer,
    System,
    RuntimeActor,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AgentStatus {
    Active,
    Paused,
    Revoked,
}

#[derive(Clone, Debug)]
pub struct AgentIdentity {
    pub agent_id: String,
    pub kind: AgentKind,
    pub label: String,
    pub status: AgentStatus,
    pub registered_at: f64,
}

// ── pools & rights ───────────────────────────────────────────────────────────--

/// Pool visibility. `Production` is reserved for the future agentless serving mode (a pool
/// promoted by the developer at dev→prod handoff); P2 does not serve, but must allow the state.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PoolVisibility {
    Private,
    Shared,
    Production,
}

impl PoolVisibility {
    pub fn as_str(&self) -> &'static str {
        match self {
            PoolVisibility::Private => "private",
            PoolVisibility::Shared => "shared",
            PoolVisibility::Production => "production",
        }
    }
}

/// Strict, explicit pool operations. No implicit cross-pool access.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PoolRight {
    ReadPool,
    ListCapsules,
    ActivateCapsule,
    ForkCapsule,
    ImportCapsule,
    ExportCapsule,
    DropCapsule,
    GrantAccess,
    AdminPool,
}

impl PoolRight {
    pub fn as_str(&self) -> &'static str {
        match self {
            PoolRight::ReadPool => "read_pool",
            PoolRight::ListCapsules => "list_capsules",
            PoolRight::ActivateCapsule => "activate_capsule",
            PoolRight::ForkCapsule => "fork_capsule",
            PoolRight::ImportCapsule => "import_capsule",
            PoolRight::ExportCapsule => "export_capsule",
            PoolRight::DropCapsule => "drop_capsule",
            PoolRight::GrantAccess => "grant_access",
            PoolRight::AdminPool => "admin_pool",
        }
    }
}

/// A content-addressed reference to an immutable capsule frame. Pools hold refs; capsule bytes
/// live ONCE in the content store (dedup by `content_digest`), never copied per pool.
#[derive(Clone, Debug)]
pub struct CapsuleRef {
    pub capsule_id: String, // == content_digest (content-addressed identity)
    pub content_digest: String,
    pub created_by: String,
    pub source_pool: String,
    pub created_at: f64,
    pub labels: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct CapsulePool {
    pub pool_id: String,
    pub name: String,
    pub owner_agent_id: String,
    pub visibility: PoolVisibility,
    pub capsule_refs: Vec<CapsuleRef>,
    pub created_at: f64,
}

/// An explicit ACL grant: agent may perform `right` on `pool_id`.
#[derive(Clone, Debug)]
pub struct PoolGrant {
    pub pool_id: String,
    pub agent_id: String,
    pub right: PoolRight,
    pub granted_by: String,
    pub granted_at: f64,
}

/// Why a pool operation was refused (all → audited deny, no state change).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PoolRefusal {
    Unauthenticated(AuthRefusal),
    UnknownAgent,
    AgentNotActive,
    NoSuchPool,
    NotGranted,
}

impl PoolRefusal {
    fn reason(&self) -> String {
        match self {
            PoolRefusal::Unauthenticated(a) => format!("unauthenticated: {:?}", a),
            PoolRefusal::UnknownAgent => "unknown agent".to_string(),
            PoolRefusal::AgentNotActive => "agent not active".to_string(),
            PoolRefusal::NoSuchPool => "no such pool".to_string(),
            PoolRefusal::NotGranted => "operation not granted on this pool".to_string(),
        }
    }
}

fn digest_bytes(bytes: &[u8]) -> String {
    blake3::hash(bytes).to_hex().to_string()
}

// ── the coordination hub ─────────────────────────────────────────────────────--

/// Local single-machine coordination state. Registries are in-memory (proof-local; a real
/// host wraps this in a lock — the durable/auditable part is the bitemporal fact log).
pub struct CoordinationHub {
    agents: HashMap<String, AgentIdentity>,
    pools: HashMap<String, CapsulePool>,
    grants: Vec<PoolGrant>,
    content: HashMap<String, Vec<u8>>, // content-addressed capsule bytes, deduped by digest
    audit: Arc<dyn TBackend>,
    clock: Arc<dyn ClockProvider>,
}

impl CoordinationHub {
    pub fn new(audit: Arc<dyn TBackend>, clock: Arc<dyn ClockProvider>) -> Self {
        Self {
            agents: HashMap::new(),
            pools: HashMap::new(),
            grants: Vec::new(),
            content: HashMap::new(),
            audit,
            clock,
        }
    }

    /// How many distinct capsule byte-images are stored (dedup proof: identical bytes → 1).
    pub fn content_count(&self) -> usize {
        self.content.len()
    }

    pub fn pool(&self, pool_id: &str) -> Option<&CapsulePool> {
        self.pools.get(pool_id)
    }

    // ── audit ──────────────────────────────────────────────────────────────────

    #[allow(clippy::too_many_arguments)]
    async fn write_audit(
        &self,
        actor: &str,
        operation: &str,
        target_pool: Option<&str>,
        target_capsule: Option<&str>,
        authority_digest: &str,
        outcome: &str,
        reason: Option<&str>,
    ) -> Result<(), EngineError> {
        let now = self.clock.now();
        let event_id = format!("coord:{}:{}:{}", actor, operation, uuid::Uuid::new_v4());
        let value = json!({
            "actor": actor,
            "operation": operation,
            "target_pool": target_pool,
            "target_capsule": target_capsule,
            "authority_digest": authority_digest,
            "outcome": outcome,
            "reason": reason,
        });
        let fact = Fact {
            id: event_id.clone(),
            store: COORD_AUDIT_STORE.to_string(),
            key: event_id,
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: now,
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("coordination")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }

    /// The host boundary for every pool operation. Authenticates the subject (P5), authorizes
    /// the operation on the pool (ACL), and writes an audit fact for BOTH allowed and denied.
    /// `operation` is also the required passport scope (the op-class the subject is cleared for).
    async fn guard(
        &self,
        passport: &CapabilityPassport,
        operation: &str,
        pool_id: Option<&str>,
        right: Option<PoolRight>,
        target_capsule: Option<&str>,
    ) -> Result<String, PoolRefusal> {
        let actor = passport.subject.clone();

        // 1. authenticate WHO (P5). Passport must carry the op-class as a scope.
        let authority_digest =
            match verify_passport(passport, COORDINATION_CAPABILITY, operation, &self.clock) {
                Ok(d) => d,
                Err(a) => {
                    let r = PoolRefusal::Unauthenticated(a);
                    let _ = self
                        .write_audit(&actor, operation, pool_id, target_capsule, "", "denied", Some(&r.reason()))
                        .await;
                    return Err(r);
                }
            };

        // 2. the subject must be a registered, active agent.
        let agent = match self.agents.get(&actor) {
            Some(a) => a,
            None => {
                let r = PoolRefusal::UnknownAgent;
                let _ = self
                    .write_audit(&actor, operation, pool_id, target_capsule, &authority_digest, "denied", Some(&r.reason()))
                    .await;
                return Err(r);
            }
        };
        if agent.status != AgentStatus::Active {
            let r = PoolRefusal::AgentNotActive;
            let _ = self
                .write_audit(&actor, operation, pool_id, target_capsule, &authority_digest, "denied", Some(&r.reason()))
                .await;
            return Err(r);
        }
        let is_developer = agent.kind == AgentKind::Developer;

        // 3. authorize WHAT on WHICH pool (ACL), when the op targets a pool.
        if let (Some(pid), Some(req_right)) = (pool_id, right) {
            let pool = match self.pools.get(pid) {
                Some(p) => p,
                None => {
                    let r = PoolRefusal::NoSuchPool;
                    let _ = self
                        .write_audit(&actor, operation, pool_id, target_capsule, &authority_digest, "denied", Some(&r.reason()))
                        .await;
                    return Err(r);
                }
            };
            let owner = pool.owner_agent_id == actor;
            let granted = self
                .grants
                .iter()
                .any(|g| g.pool_id == pid && g.agent_id == actor && g.right == req_right);
            // owner has all rights; developer-conductor is privileged (but audited); else need a grant.
            if !(owner || is_developer || granted) {
                let r = PoolRefusal::NotGranted;
                let _ = self
                    .write_audit(&actor, operation, pool_id, target_capsule, &authority_digest, "denied", Some(&r.reason()))
                    .await;
                return Err(r);
            }
        }

        // allowed
        let _ = self
            .write_audit(&actor, operation, pool_id, target_capsule, &authority_digest, "allowed", None)
            .await;
        Ok(authority_digest)
    }

    // ── operations ───────────────────────────────────────────────────────────--

    /// Register an identity. Bootstrap / system-or-developer action; audited as `register`.
    pub async fn register_agent(&mut self, identity: AgentIdentity) -> Result<(), EngineError> {
        let id = identity.agent_id.clone();
        let kind = format!("{:?}", identity.kind);
        self.agents.insert(id.clone(), identity);
        self.write_audit(&id, "register", None, None, "", "allowed", Some(&kind)).await
    }

    pub fn set_agent_status(&mut self, agent_id: &str, status: AgentStatus) {
        if let Some(a) = self.agents.get_mut(agent_id) {
            a.status = status;
        }
    }

    /// Create a pool owned by the authenticated subject.
    pub async fn create_pool(
        &mut self,
        passport: &CapabilityPassport,
        pool_id: &str,
        name: &str,
        visibility: PoolVisibility,
    ) -> Result<(), PoolRefusal> {
        self.guard(passport, "create_pool", None, None, None).await?;
        let pool = CapsulePool {
            pool_id: pool_id.to_string(),
            name: name.to_string(),
            owner_agent_id: passport.subject.clone(),
            visibility,
            capsule_refs: Vec::new(),
            created_at: self.clock.now(),
        };
        self.pools.insert(pool_id.to_string(), pool);
        Ok(())
    }

    /// Import a capsule (bytes) into a pool. Content-addressed: identical bytes dedup to one
    /// stored image; the pool gains a `CapsuleRef` by digest. Returns the ref.
    pub async fn add_capsule(
        &mut self,
        passport: &CapabilityPassport,
        pool_id: &str,
        bytes: Vec<u8>,
        labels: Vec<String>,
    ) -> Result<CapsuleRef, PoolRefusal> {
        self.guard(passport, "import_capsule", Some(pool_id), Some(PoolRight::ImportCapsule), None)
            .await?;
        let digest = digest_bytes(&bytes);
        self.content.entry(digest.clone()).or_insert(bytes); // dedup by content
        let cref = CapsuleRef {
            capsule_id: digest.clone(),
            content_digest: digest,
            created_by: passport.subject.clone(),
            source_pool: pool_id.to_string(),
            created_at: self.clock.now(),
            labels,
        };
        if let Some(pool) = self.pools.get_mut(pool_id) {
            pool.capsule_refs.push(cref.clone());
        }
        Ok(cref)
    }

    /// List the capsule refs in a pool (requires `ListCapsules`).
    pub async fn list_capsules(
        &self,
        passport: &CapabilityPassport,
        pool_id: &str,
    ) -> Result<Vec<CapsuleRef>, PoolRefusal> {
        self.guard(passport, "list_capsules", Some(pool_id), Some(PoolRight::ListCapsules), None)
            .await?;
        Ok(self
            .pools
            .get(pool_id)
            .map(|p| p.capsule_refs.clone())
            .unwrap_or_default())
    }

    /// Authorize (and audit) an arbitrary right on a pool without performing it — used to prove
    /// activate/fork/etc. access control. Ok = allowed.
    pub async fn check_right(
        &self,
        passport: &CapabilityPassport,
        pool_id: &str,
        right: PoolRight,
    ) -> Result<(), PoolRefusal> {
        self.guard(passport, right.as_str(), Some(pool_id), Some(right), None).await?;
        Ok(())
    }

    /// Grant a right on a pool to another agent (requires `GrantAccess`: owner or developer).
    /// The grant itself is audited.
    pub async fn grant(
        &mut self,
        passport: &CapabilityPassport,
        pool_id: &str,
        to_agent: &str,
        right: PoolRight,
    ) -> Result<(), PoolRefusal> {
        self.guard(passport, "grant_access", Some(pool_id), Some(PoolRight::GrantAccess), None)
            .await?;
        self.grants.push(PoolGrant {
            pool_id: pool_id.to_string(),
            agent_id: to_agent.to_string(),
            right,
            granted_by: passport.subject.clone(),
            granted_at: self.clock.now(),
        });
        Ok(())
    }

    /// Transfer pool ownership to another agent (requires `AdminPool`: owner or developer).
    /// This is the dev→prod handoff primitive (a developer takes ownership of a candidate
    /// pool) — fully audited. Optionally promote visibility (e.g. → `Production`).
    pub async fn transfer_ownership(
        &mut self,
        passport: &CapabilityPassport,
        pool_id: &str,
        to_agent: &str,
        promote: Option<PoolVisibility>,
    ) -> Result<(), PoolRefusal> {
        self.guard(passport, "admin_pool", Some(pool_id), Some(PoolRight::AdminPool), None)
            .await?;
        if let Some(pool) = self.pools.get_mut(pool_id) {
            pool.owner_agent_id = to_agent.to_string();
            if let Some(v) = promote {
                pool.visibility = v;
            }
        }
        Ok(())
    }
}
