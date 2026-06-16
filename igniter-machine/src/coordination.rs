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
use crate::machine::IgniterMachine;
use serde_json::{json, Value};
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
    pub fn from_str(s: &str) -> Option<PoolRight> {
        Some(match s {
            "read_pool" => PoolRight::ReadPool,
            "list_capsules" => PoolRight::ListCapsules,
            "activate_capsule" => PoolRight::ActivateCapsule,
            "fork_capsule" => PoolRight::ForkCapsule,
            "import_capsule" => PoolRight::ImportCapsule,
            "export_capsule" => PoolRight::ExportCapsule,
            "drop_capsule" => PoolRight::DropCapsule,
            "grant_access" => PoolRight::GrantAccess,
            "admin_pool" => PoolRight::AdminPool,
            _ => return None,
        })
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

/// Why a pool/message operation was refused (all → audited deny, no state change).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PoolRefusal {
    Unauthenticated(AuthRefusal),
    UnknownAgent,
    AgentNotActive,
    NoSuchPool,
    NotGranted,
    /// Messenger-specific input/visibility refusal (P3): unknown recipient, not a thread
    /// participant, request not found / not ackable, etc.
    Invalid(String),
}

impl PoolRefusal {
    fn reason(&self) -> String {
        match self {
            PoolRefusal::Unauthenticated(a) => format!("unauthenticated: {:?}", a),
            PoolRefusal::UnknownAgent => "unknown agent".to_string(),
            PoolRefusal::AgentNotActive => "agent not active".to_string(),
            PoolRefusal::NoSuchPool => "no such pool".to_string(),
            PoolRefusal::NotGranted => "operation not granted on this pool".to_string(),
            PoolRefusal::Invalid(m) => m.clone(),
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

    /// The ACL decision (no audit, no IO): owner of the pool, or developer-conductor, or an
    /// explicit `PoolGrant` for `(agent, pool, right)`. Reused by `guard` and transfer ops.
    fn pool_authorized(
        &self,
        actor: &str,
        is_developer: bool,
        pool_id: &str,
        right: PoolRight,
    ) -> Result<(), PoolRefusal> {
        let pool = self.pools.get(pool_id).ok_or(PoolRefusal::NoSuchPool)?;
        let owner = pool.owner_agent_id == actor;
        let granted = self
            .grants
            .iter()
            .any(|g| g.pool_id == pool_id && g.agent_id == actor && g.right == right);
        if owner || is_developer || granted {
            Ok(())
        } else {
            Err(PoolRefusal::NotGranted)
        }
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
            if let Err(r) = self.pool_authorized(&actor, is_developer, pid, req_right) {
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

// ── Messenger bus (LAB-MACHINE-AGENT-MESSENGER-P3) ──────────────────────────────
//
// Messages are append-only FACTS in `__messenger__`, NOT a mutable inbox. "List my inbox" is
// a QUERY over message facts filtered by recipient + visibility. A request that `requires_ack`
// stays pending until an `Ack` fact links back to it (`in_reply_to`). Developer escalation is a
// message addressed to `"developer"`. Carrying a `CapsuleRef` in a message does NOT grant
// access — pool ACL (P2) still governs. Every message op writes an audit fact.

/// Messages live in their own bitemporal store namespace.
pub const MESSENGER_STORE: &str = "__messenger__";
/// The reserved recipient for developer-conductor escalations.
pub const DEVELOPER_RECIPIENT: &str = "developer";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MessageKind {
    Note,
    Request,
    Ack,
    Escalation,
    Decision,
}

impl MessageKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            MessageKind::Note => "note",
            MessageKind::Request => "request",
            MessageKind::Ack => "ack",
            MessageKind::Escalation => "escalation",
            MessageKind::Decision => "decision",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "request" => MessageKind::Request,
            "ack" => MessageKind::Ack,
            "escalation" => MessageKind::Escalation,
            "decision" => MessageKind::Decision,
            _ => MessageKind::Note,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Message {
    pub message_id: String,
    pub thread_id: String,
    pub from_agent: String,
    pub to: String,
    pub kind: MessageKind,
    pub body_digest: String,
    pub capsule_refs: Vec<String>,
    pub requires_ack: bool,
    pub in_reply_to: Option<String>,
    pub created_at: f64,
}

impl CoordinationHub {
    fn is_active_agent(&self, id: &str) -> bool {
        self.agents.get(id).map(|a| a.status == AgentStatus::Active).unwrap_or(false)
    }

    /// Authenticate a subject for a message op (no audit, no IO): passport (P5) + registered +
    /// active. Returns `(authority_digest, is_developer)`. The caller writes the single audit.
    fn authed(
        &self,
        passport: &CapabilityPassport,
        operation: &str,
    ) -> Result<(String, bool), PoolRefusal> {
        let digest = verify_passport(passport, COORDINATION_CAPABILITY, operation, &self.clock)
            .map_err(PoolRefusal::Unauthenticated)?;
        let agent = self.agents.get(&passport.subject).ok_or(PoolRefusal::UnknownAgent)?;
        if agent.status != AgentStatus::Active {
            return Err(PoolRefusal::AgentNotActive);
        }
        Ok((digest, agent.kind == AgentKind::Developer))
    }

    async fn deny_msg(&self, actor: &str, op: &str, digest: &str, err: &PoolRefusal) {
        let _ = self
            .write_audit(actor, op, None, None, digest, "denied", Some(&err.reason()))
            .await;
    }

    async fn write_message(&self, m: &Message) -> Result<(), EngineError> {
        let value = json!({
            "message_id": m.message_id,
            "thread_id": m.thread_id,
            "from_agent": m.from_agent,
            "to": m.to,
            "kind": m.kind.as_str(),
            "body_digest": m.body_digest,
            "capsule_refs": m.capsule_refs,
            "requires_ack": m.requires_ack,
            "in_reply_to": m.in_reply_to,
            "created_at": m.created_at,
        });
        let fact = Fact {
            id: m.message_id.clone(),
            store: MESSENGER_STORE.to_string(),
            key: m.message_id.clone(),
            value,
            value_hash: String::new(),
            causation: m.in_reply_to.clone(),
            transaction_time: m.created_at,
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("messenger")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }

    /// Read all message facts (proof-local scan; a real host indexes by recipient/thread).
    async fn all_messages(&self) -> Vec<Message> {
        self.audit
            .all_facts()
            .await
            .unwrap_or_default()
            .into_iter()
            .filter(|f| f.store == MESSENGER_STORE)
            .map(|f| {
                let v = &f.value;
                Message {
                    message_id: v["message_id"].as_str().unwrap_or("").to_string(),
                    thread_id: v["thread_id"].as_str().unwrap_or("").to_string(),
                    from_agent: v["from_agent"].as_str().unwrap_or("").to_string(),
                    to: v["to"].as_str().unwrap_or("").to_string(),
                    kind: MessageKind::from_str(v["kind"].as_str().unwrap_or("note")),
                    body_digest: v["body_digest"].as_str().unwrap_or("").to_string(),
                    capsule_refs: v["capsule_refs"]
                        .as_array()
                        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                        .unwrap_or_default(),
                    requires_ack: v["requires_ack"].as_bool().unwrap_or(false),
                    in_reply_to: v["in_reply_to"].as_str().map(String::from),
                    created_at: v["created_at"].as_f64().unwrap_or(0.0),
                }
            })
            .collect()
    }

    /// Send a message from the authenticated subject to a registered agent (or `"developer"`).
    /// `kind` `Request` with `requires_ack` stays pending until acked. Returns the message id.
    #[allow(clippy::too_many_arguments)]
    pub async fn send_message(
        &self,
        passport: &CapabilityPassport,
        to: &str,
        thread_id: &str,
        kind: MessageKind,
        body: &[u8],
        capsule_refs: Vec<String>,
        requires_ack: bool,
    ) -> Result<String, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, _) = match self.authed(passport, "send_message") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "send_message", "", &e).await;
                return Err(e);
            }
        };
        // recipient must be a registered active agent, or the developer-conductor mailbox.
        if to != DEVELOPER_RECIPIENT && !self.is_active_agent(to) {
            let e = PoolRefusal::Invalid("unknown or inactive recipient".to_string());
            self.deny_msg(&actor, "send_message", &digest, &e).await;
            return Err(e);
        }
        let message_id = format!("msg:{}", uuid::Uuid::new_v4());
        let m = Message {
            message_id: message_id.clone(),
            thread_id: thread_id.to_string(),
            from_agent: actor.clone(),
            to: to.to_string(),
            kind,
            body_digest: digest_bytes(body),
            capsule_refs,
            requires_ack,
            in_reply_to: None,
            created_at: self.clock.now(),
        };
        let _ = self.write_message(&m).await;
        let _ = self
            .write_audit(&actor, "send_message", None, None, &digest, "allowed", Some(kind.as_str()))
            .await;
        Ok(message_id)
    }

    /// Escalate to the developer-conductor (a message addressed to `"developer"`). Audited.
    pub async fn escalate(
        &self,
        passport: &CapabilityPassport,
        thread_id: &str,
        body: &[u8],
        capsule_refs: Vec<String>,
    ) -> Result<String, PoolRefusal> {
        self.send_message(passport, DEVELOPER_RECIPIENT, thread_id, MessageKind::Escalation, body, capsule_refs, true)
            .await
    }

    /// Acknowledge a request addressed to the subject. Links the ack to the request via
    /// `in_reply_to` and routes it back to the requester. Audited.
    pub async fn ack(
        &self,
        passport: &CapabilityPassport,
        request_id: &str,
    ) -> Result<String, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, _) = match self.authed(passport, "send_message") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "ack", "", &e).await;
                return Err(e);
            }
        };
        let msgs = self.all_messages().await;
        let request = msgs.iter().find(|m| m.message_id == request_id);
        let request = match request {
            Some(r) if r.kind == MessageKind::Request && r.requires_ack && r.to == actor => r,
            _ => {
                let e = PoolRefusal::Invalid("request not found, not ackable, or not addressed to you".to_string());
                self.deny_msg(&actor, "ack", &digest, &e).await;
                return Err(e);
            }
        };
        let message_id = format!("msg:{}", uuid::Uuid::new_v4());
        let m = Message {
            message_id: message_id.clone(),
            thread_id: request.thread_id.clone(),
            from_agent: actor.clone(),
            to: request.from_agent.clone(),
            kind: MessageKind::Ack,
            body_digest: String::new(),
            capsule_refs: Vec::new(),
            requires_ack: false,
            in_reply_to: Some(request_id.to_string()),
            created_at: self.clock.now(),
        };
        let _ = self.write_message(&m).await;
        let _ = self
            .write_audit(&actor, "ack", None, Some(request_id), &digest, "allowed", None)
            .await;
        Ok(message_id)
    }

    /// List messages addressed to `agent_id`. Only the agent itself or a developer may read an
    /// inbox. (A query over facts — no mutable inbox.) Audited.
    pub async fn list_inbox(
        &self,
        passport: &CapabilityPassport,
        agent_id: &str,
    ) -> Result<Vec<Message>, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "read_message") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "read_message", "", &e).await;
                return Err(e);
            }
        };
        if actor != agent_id && !is_dev {
            let e = PoolRefusal::NotGranted;
            self.deny_msg(&actor, "read_message", &digest, &e).await;
            return Err(e);
        }
        let inbox: Vec<Message> = self.all_messages().await.into_iter().filter(|m| m.to == agent_id).collect();
        let _ = self
            .write_audit(&actor, "read_message", None, None, &digest, "allowed", None)
            .await;
        Ok(inbox)
    }

    /// Read a thread. Only a participant (sender or recipient of any message in the thread) or a
    /// developer may read it. Audited.
    pub async fn read_thread(
        &self,
        passport: &CapabilityPassport,
        thread_id: &str,
    ) -> Result<Vec<Message>, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "read_message") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "read_message", "", &e).await;
                return Err(e);
            }
        };
        let thread: Vec<Message> = self.all_messages().await.into_iter().filter(|m| m.thread_id == thread_id).collect();
        let participant = thread.iter().any(|m| m.from_agent == actor || m.to == actor);
        if !participant && !is_dev {
            let e = PoolRefusal::NotGranted;
            self.deny_msg(&actor, "read_message", &digest, &e).await;
            return Err(e);
        }
        let _ = self
            .write_audit(&actor, "read_message", Some(thread_id), None, &digest, "allowed", None)
            .await;
        Ok(thread)
    }

    /// Requests addressed to `agent_id` that require an ack and have none yet (computed from
    /// facts: requests minus their acks). Read-only — not audited.
    pub async fn pending_requests(&self, agent_id: &str) -> Vec<Message> {
        let msgs = self.all_messages().await;
        let acked: std::collections::HashSet<String> = msgs
            .iter()
            .filter(|m| m.kind == MessageKind::Ack)
            .filter_map(|m| m.in_reply_to.clone())
            .collect();
        msgs.into_iter()
            .filter(|m| {
                m.kind == MessageKind::Request
                    && m.requires_ack
                    && m.to == agent_id
                    && !acked.contains(&m.message_id)
            })
            .collect()
    }
}

// ── Capsule transfer envelopes (LAB-MACHINE-AGENT-TRANSFER-P4) ──────────────────
//
// An audited TWO-PHASE handoff of a capsule ref between agents/pools. Pattern (not module)
// reuse of the P6 write lifecycle: `proposed ≈ prepared`, `accepted ≈ committed`,
// `rejected`/`revoked ≈ denied/aborted`. Idempotent (re-accept is a replay, no second import),
// the source capsule/ref is immutable (accept ADDS a content-addressed ref to the target pool,
// it does not copy bytes or remove the source), and every state transition is an audit fact.
// `expired` is a reserved design-only state (the host clock exists, P4 does not produce it).

/// Transfer envelopes live in their own bitemporal store namespace.
pub const TRANSFERS_STORE: &str = "__transfers__";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TransferState {
    Proposed,
    Accepted,
    Rejected,
    Revoked,
    /// Reserved design-only (clock exists); P4 never produces it.
    Expired,
}

impl TransferState {
    pub fn as_str(&self) -> &'static str {
        match self {
            TransferState::Proposed => "proposed",
            TransferState::Accepted => "accepted",
            TransferState::Rejected => "rejected",
            TransferState::Revoked => "revoked",
            TransferState::Expired => "expired",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "accepted" => TransferState::Accepted,
            "rejected" => TransferState::Rejected,
            "revoked" => TransferState::Revoked,
            "expired" => TransferState::Expired,
            _ => TransferState::Proposed,
        }
    }
}

#[derive(Clone, Debug)]
pub struct TransferEnvelope {
    pub transfer_id: String,
    pub from_agent: String,
    pub to_agent: String,
    pub from_pool: String,
    pub to_pool: String,
    pub capsule_id: String,
    pub capsule_digest: String,
    pub rights_granted: Vec<PoolRight>,
    pub reason: String,
    pub state: TransferState,
    /// Optional forward-looking field for the dev→prod handoff; P4 does NOT serve / deploy.
    pub recipe_digest: Option<String>,
    pub created_at: f64,
}

impl CoordinationHub {
    async fn write_transfer(&self, env: &TransferEnvelope) -> Result<(), EngineError> {
        let rights: Vec<&str> = env.rights_granted.iter().map(|r| r.as_str()).collect();
        let value = json!({
            "transfer_id": env.transfer_id,
            "from_agent": env.from_agent,
            "to_agent": env.to_agent,
            "from_pool": env.from_pool,
            "to_pool": env.to_pool,
            "capsule_id": env.capsule_id,
            "capsule_digest": env.capsule_digest,
            "rights_granted": rights,
            "reason": env.reason,
            "state": env.state.as_str(),
            "recipe_digest": env.recipe_digest,
            "created_at": env.created_at,
        });
        let fact = Fact {
            // state in the id → distinct facts on one transfer_id timeline; latest tx wins.
            id: format!("transfer:{}:{}", env.transfer_id, env.state.as_str()),
            store: TRANSFERS_STORE.to_string(),
            key: env.transfer_id.clone(),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("transfer")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }

    /// Read the latest state of a transfer envelope (`read_as_of` MAX = latest fact).
    pub async fn read_transfer(&self, transfer_id: &str) -> Option<TransferEnvelope> {
        let fact = self
            .audit
            .read_as_of(TRANSFERS_STORE, transfer_id, f64::MAX)
            .await
            .ok()
            .flatten()?;
        let v = &fact.value;
        let rights = v["rights_granted"]
            .as_array()
            .map(|a| a.iter().filter_map(|x| x.as_str().and_then(PoolRight::from_str)).collect())
            .unwrap_or_default();
        Some(TransferEnvelope {
            transfer_id: v["transfer_id"].as_str().unwrap_or("").to_string(),
            from_agent: v["from_agent"].as_str().unwrap_or("").to_string(),
            to_agent: v["to_agent"].as_str().unwrap_or("").to_string(),
            from_pool: v["from_pool"].as_str().unwrap_or("").to_string(),
            to_pool: v["to_pool"].as_str().unwrap_or("").to_string(),
            capsule_id: v["capsule_id"].as_str().unwrap_or("").to_string(),
            capsule_digest: v["capsule_digest"].as_str().unwrap_or("").to_string(),
            rights_granted: rights,
            reason: v["reason"].as_str().unwrap_or("").to_string(),
            state: TransferState::from_str(v["state"].as_str().unwrap_or("proposed")),
            recipe_digest: v["recipe_digest"].as_str().map(String::from),
            created_at: v["created_at"].as_f64().unwrap_or(0.0),
        })
    }

    /// Propose a transfer of a capsule (must be in `from_pool`) to `to_agent`/`to_pool`.
    /// Requires `ExportCapsule` on `from_pool`. Returns the transfer id.
    #[allow(clippy::too_many_arguments)]
    pub async fn propose_transfer(
        &self,
        passport: &CapabilityPassport,
        to_agent: &str,
        from_pool: &str,
        to_pool: &str,
        capsule_id: &str,
        rights_granted: Vec<PoolRight>,
        reason: &str,
        recipe_digest: Option<String>,
    ) -> Result<String, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "propose_transfer") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "propose_transfer", "", &e).await;
                return Err(e);
            }
        };
        if let Err(e) = self.pool_authorized(&actor, is_dev, from_pool, PoolRight::ExportCapsule) {
            self.deny_msg(&actor, "propose_transfer", &digest, &e).await;
            return Err(e);
        }
        // the capsule must actually be in the source pool.
        let cref = self
            .pools
            .get(from_pool)
            .and_then(|p| p.capsule_refs.iter().find(|r| r.capsule_id == capsule_id).cloned());
        let cref = match cref {
            Some(c) => c,
            None => {
                let e = PoolRefusal::Invalid("capsule not in source pool".to_string());
                self.deny_msg(&actor, "propose_transfer", &digest, &e).await;
                return Err(e);
            }
        };
        if !self.is_active_agent(to_agent) {
            let e = PoolRefusal::Invalid("unknown or inactive recipient".to_string());
            self.deny_msg(&actor, "propose_transfer", &digest, &e).await;
            return Err(e);
        }
        let transfer_id = format!("xfer:{}", uuid::Uuid::new_v4());
        let env = TransferEnvelope {
            transfer_id: transfer_id.clone(),
            from_agent: actor.clone(),
            to_agent: to_agent.to_string(),
            from_pool: from_pool.to_string(),
            to_pool: to_pool.to_string(),
            capsule_id: capsule_id.to_string(),
            capsule_digest: cref.content_digest,
            rights_granted,
            reason: reason.to_string(),
            state: TransferState::Proposed,
            recipe_digest,
            created_at: self.clock.now(),
        };
        let _ = self.write_transfer(&env).await;
        let _ = self
            .write_audit(&actor, "propose_transfer", Some(from_pool), Some(capsule_id), &digest, "allowed", None)
            .await;
        Ok(transfer_id)
    }

    /// Accept a proposed transfer (recipient or developer). Imports a content-addressed ref into
    /// the target pool and grants the declared rights. Idempotent on an already-accepted
    /// transfer; the source pool/ref is untouched. Requires `ImportCapsule` on `to_pool`.
    pub async fn accept_transfer(
        &mut self,
        passport: &CapabilityPassport,
        transfer_id: &str,
    ) -> Result<TransferState, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "accept_transfer") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "accept_transfer", "", &e).await;
                return Err(e);
            }
        };
        let env = match self.read_transfer(transfer_id).await {
            Some(e) => e,
            None => {
                let e = PoolRefusal::Invalid("no such transfer".to_string());
                self.deny_msg(&actor, "accept_transfer", &digest, &e).await;
                return Err(e);
            }
        };
        if env.to_agent != actor && !is_dev {
            let e = PoolRefusal::NotGranted;
            self.deny_msg(&actor, "accept_transfer", &digest, &e).await;
            return Err(e);
        }
        match env.state {
            // idempotent: re-accepting a committed transfer is a replay, no second import.
            TransferState::Accepted => {
                let _ = self
                    .write_audit(&actor, "accept_transfer", Some(&env.to_pool), Some(&env.capsule_id), &digest, "allowed", Some("idempotent"))
                    .await;
                return Ok(TransferState::Accepted);
            }
            TransferState::Rejected | TransferState::Revoked | TransferState::Expired => {
                let e = PoolRefusal::Invalid(format!("transfer is {}", env.state.as_str()));
                self.deny_msg(&actor, "accept_transfer", &digest, &e).await;
                return Err(e);
            }
            TransferState::Proposed => {}
        }
        // ACL: the acceptor must be able to import into the target pool.
        if let Err(e) = self.pool_authorized(&actor, is_dev, &env.to_pool, PoolRight::ImportCapsule) {
            self.deny_msg(&actor, "accept_transfer", &digest, &e).await;
            return Err(e);
        }

        // import a content-addressed ref into the target pool (bytes already deduped in the
        // content store; the source ref is NOT removed → immutable source).
        let now = self.clock.now();
        if let Some(pool) = self.pools.get_mut(&env.to_pool) {
            pool.capsule_refs.push(CapsuleRef {
                capsule_id: env.capsule_id.clone(),
                content_digest: env.capsule_digest.clone(),
                created_by: env.from_agent.clone(),
                source_pool: env.from_pool.clone(),
                created_at: now,
                labels: vec!["transferred".to_string()],
            });
        }
        // grant the recipient ONLY the declared rights on the target pool.
        for right in &env.rights_granted {
            self.grants.push(PoolGrant {
                pool_id: env.to_pool.clone(),
                agent_id: env.to_agent.clone(),
                right: *right,
                granted_by: env.from_agent.clone(),
                granted_at: now,
            });
        }
        let mut committed = env.clone();
        committed.state = TransferState::Accepted;
        let _ = self.write_transfer(&committed).await;
        let _ = self
            .write_audit(&actor, "accept_transfer", Some(&env.to_pool), Some(&env.capsule_id), &digest, "allowed", None)
            .await;
        Ok(TransferState::Accepted)
    }

    /// Reject a proposed transfer (recipient or developer). No import. Idempotent on rejected.
    pub async fn reject_transfer(
        &self,
        passport: &CapabilityPassport,
        transfer_id: &str,
    ) -> Result<TransferState, PoolRefusal> {
        self.terminalize(passport, transfer_id, TransferState::Rejected, "reject_transfer").await
    }

    /// Revoke a proposed transfer (proposer or developer) → prevents any future accept.
    /// Cannot revoke an already-accepted transfer. Idempotent on revoked.
    pub async fn revoke_transfer(
        &self,
        passport: &CapabilityPassport,
        transfer_id: &str,
    ) -> Result<TransferState, PoolRefusal> {
        self.terminalize(passport, transfer_id, TransferState::Revoked, "revoke_transfer").await
    }

    /// Shared terminal transition for reject/revoke (no import; just a state fact). `reject` is
    /// authorized for the recipient, `revoke` for the proposer; developer may do either.
    async fn terminalize(
        &self,
        passport: &CapabilityPassport,
        transfer_id: &str,
        target: TransferState,
        op: &str,
    ) -> Result<TransferState, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, op) {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, op, "", &e).await;
                return Err(e);
            }
        };
        let env = match self.read_transfer(transfer_id).await {
            Some(e) => e,
            None => {
                let e = PoolRefusal::Invalid("no such transfer".to_string());
                self.deny_msg(&actor, op, &digest, &e).await;
                return Err(e);
            }
        };
        // reject → recipient; revoke → proposer; developer may do either.
        let allowed_actor = match target {
            TransferState::Rejected => env.to_agent == actor,
            TransferState::Revoked => env.from_agent == actor,
            _ => false,
        };
        if !allowed_actor && !is_dev {
            let e = PoolRefusal::NotGranted;
            self.deny_msg(&actor, op, &digest, &e).await;
            return Err(e);
        }
        match env.state {
            s if s == target => {
                let _ = self.write_audit(&actor, op, None, None, &digest, "allowed", Some("idempotent")).await;
                return Ok(target);
            }
            TransferState::Proposed => {}
            other => {
                let e = PoolRefusal::Invalid(format!("transfer is {}", other.as_str()));
                self.deny_msg(&actor, op, &digest, &e).await;
                return Err(e);
            }
        }
        let mut next = env.clone();
        next.state = target;
        let _ = self.write_transfer(&next).await;
        let _ = self.write_audit(&actor, op, None, None, &digest, "allowed", None).await;
        Ok(target)
    }
}

// ── ServiceRecipe: dev→prod handoff + agentless serving (LAB-MACHINE-SERVICE-RECIPE-P5) ──
//
// The bridge from agent-built candidate to a running, agentless production service:
//
// ```text
// agent-built candidate capsule  (P2 pool + P4 transfer carried a recipe_digest)
//   -> developer SIGNS a ServiceRecipe (capsule_digest + entry_contract + scopes)  (root-of-trust)
//   -> the pool becomes `production`, owned by the developer/system
//   -> a vendor/runtime-actor passport INVOKES the entry contract
//   -> invocation = real capsule ACTIVATION (resume bytes + dispatch), NOT messenger
//   -> an audit/receipt fact is written
// ```
//
// A production pool of N capsule refs sharing one `content_digest` is a homogeneous service
// replica set. Invocation is an in-process host call — no external HTTP server, no MCP hot path,
// and the dispatched contract body still does no IO (the VM path has no executor registry).

/// Signed service recipes live in their own store, keyed by the production pool id.
pub const RECIPES_STORE: &str = "__recipes__";
/// Ingress duplicate-tracking facts, keyed by `route:duplicate_key`.
pub const INGRESS_DEDUP_STORE: &str = "__ingress_dedup__";

/// A **business** ingress duplicate-handling strategy (LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-
/// POLICY-P7). NOT a canon language/VM behavior — it lives on the `ServiceRecipe`/route. The
/// safety envelope (idempotency identity = duplicate_key + payload_digest) is always enforced;
/// the *duplicate policy* decides what a repeat MEANS for this service.
///
/// `mode`: `"dedup_strict"` (repeat → recorded response, no re-activation),
/// `"treat_as_fresh"` (repeat re-activates, audit-linked), `"bounded_fresh"` (first `max_fresh`
/// repeats re-activate, then `after_limit`), `"off"` (no tracking, every request fresh).
/// `after_limit`: `"dedup_last"` | `"deny"`. `seed_field`: the input field the deterministic
/// `attempt_index` is injected into (so a service can mint a distinct code per duplicate, e.g.
/// the vendor-auction case). `variant_payload=false` (default) → same key + different payload =
/// conflict (the safety invariant). `require_key`: a missing duplicate key is rejected vs allowed.
#[derive(Clone, Debug)]
pub struct DuplicatePolicy {
    pub mode: String,
    pub key_header: String,
    pub max_fresh: u32,
    pub after_limit: String,
    pub seed_field: String,
    pub variant_payload: bool,
    pub require_key: bool,
}

/// The deploy descriptor a developer signs to turn a candidate capsule into a service. The
/// capsule is the immutable image; the recipe is "how to run it".
#[derive(Clone, Debug)]
pub struct ServiceRecipe {
    pub recipe_id: String,
    pub capsule_digest: String,
    pub entry_contract: String,
    pub input_schema_digest: Option<String>,
    pub capability_bindings: Vec<String>,
    pub required_scopes: Vec<String>,
    pub receipt_policy: String,
    pub retry_policy_ref: Option<String>,
    pub pool_sizing: u32,
    pub created_by: String,
    pub accepted_by: Option<String>,
    pub accepted_at: Option<f64>,
    /// Configurable business duplicate strategy (None = no dedup; every request is fresh).
    pub duplicate_policy: Option<DuplicatePolicy>,
}

impl CoordinationHub {
    async fn write_recipe(&self, pool_id: &str, recipe: &ServiceRecipe) -> Result<(), EngineError> {
        let value = json!({
            "recipe_id": recipe.recipe_id,
            "capsule_digest": recipe.capsule_digest,
            "entry_contract": recipe.entry_contract,
            "input_schema_digest": recipe.input_schema_digest,
            "capability_bindings": recipe.capability_bindings,
            "required_scopes": recipe.required_scopes,
            "receipt_policy": recipe.receipt_policy,
            "retry_policy_ref": recipe.retry_policy_ref,
            "pool_sizing": recipe.pool_sizing,
            "created_by": recipe.created_by,
            "accepted_by": recipe.accepted_by,
            "accepted_at": recipe.accepted_at,
            "duplicate_policy": recipe.duplicate_policy.as_ref().map(|p| json!({
                "mode": p.mode,
                "key_header": p.key_header,
                "max_fresh": p.max_fresh,
                "after_limit": p.after_limit,
                "seed_field": p.seed_field,
                "variant_payload": p.variant_payload,
                "require_key": p.require_key,
            })),
        });
        let fact = Fact {
            id: format!("recipe:{}:{}", pool_id, recipe.recipe_id),
            store: RECIPES_STORE.to_string(),
            key: pool_id.to_string(),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("service-recipe")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }

    /// The accepted recipe bound to a production pool (latest fact), if any.
    pub async fn read_recipe(&self, pool_id: &str) -> Option<ServiceRecipe> {
        let fact = self.audit.read_as_of(RECIPES_STORE, pool_id, f64::MAX).await.ok().flatten()?;
        let v = &fact.value;
        let str_vec = |k: &str| -> Vec<String> {
            v[k].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default()
        };
        Some(ServiceRecipe {
            recipe_id: v["recipe_id"].as_str().unwrap_or("").to_string(),
            capsule_digest: v["capsule_digest"].as_str().unwrap_or("").to_string(),
            entry_contract: v["entry_contract"].as_str().unwrap_or("").to_string(),
            input_schema_digest: v["input_schema_digest"].as_str().map(String::from),
            capability_bindings: str_vec("capability_bindings"),
            required_scopes: str_vec("required_scopes"),
            receipt_policy: v["receipt_policy"].as_str().unwrap_or("").to_string(),
            retry_policy_ref: v["retry_policy_ref"].as_str().map(String::from),
            pool_sizing: v["pool_sizing"].as_u64().unwrap_or(1) as u32,
            created_by: v["created_by"].as_str().unwrap_or("").to_string(),
            accepted_by: v["accepted_by"].as_str().map(String::from),
            accepted_at: v["accepted_at"].as_f64(),
            duplicate_policy: {
                let p = &v["duplicate_policy"];
                if p.is_object() {
                    Some(DuplicatePolicy {
                        mode: p["mode"].as_str().unwrap_or("off").to_string(),
                        key_header: p["key_header"].as_str().unwrap_or("").to_string(),
                        max_fresh: p["max_fresh"].as_u64().unwrap_or(0) as u32,
                        after_limit: p["after_limit"].as_str().unwrap_or("dedup_last").to_string(),
                        seed_field: p["seed_field"].as_str().unwrap_or("attempt").to_string(),
                        variant_payload: p["variant_payload"].as_bool().unwrap_or(false),
                        require_key: p["require_key"].as_bool().unwrap_or(false),
                    })
                } else {
                    None
                }
            },
        })
    }

    /// Append a duplicate-tracking fact for an ingress request. Keyed by `route:duplicate_key`.
    #[allow(clippy::too_many_arguments)]
    pub async fn record_ingress_dedup(
        &self,
        route: &str,
        duplicate_key: &str,
        payload_digest: &str,
        attempt_index: u32,
        status: u16,
        response: &Value,
        decision: &str,
        correlation_id: &str,
    ) -> Result<(), EngineError> {
        let key = format!("{}:{}", route, duplicate_key);
        let value = json!({
            "route": route,
            "duplicate_key": duplicate_key,
            "payload_digest": payload_digest,
            "attempt_index": attempt_index,
            "status": status,
            "response": response,
            "decision": decision,
            "correlation_id": correlation_id,
        });
        let fact = Fact {
            id: format!("dedup:{}:{}", key, uuid::Uuid::new_v4()),
            store: INGRESS_DEDUP_STORE.to_string(),
            key,
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("ingress-dedup")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }

    /// All duplicate-tracking facts for a `(route, duplicate_key)`, oldest first.
    pub async fn ingress_dedup_history(&self, route: &str, duplicate_key: &str) -> Vec<Value> {
        let key = format!("{}:{}", route, duplicate_key);
        let mut facts = self.audit.facts_for(INGRESS_DEDUP_STORE, &key, None, None).await.unwrap_or_default();
        facts.sort_by(|a, b| a.transaction_time.partial_cmp(&b.transaction_time).unwrap_or(std::cmp::Ordering::Equal));
        facts.into_iter().map(|f| f.value).collect()
    }

    /// The developer (root-of-trust) signs a recipe and promotes the pool to production.
    /// The recipe's `capsule_digest` must match a capsule actually in the pool. The pool becomes
    /// `Production` and is owned by the signing developer. Audited.
    pub async fn accept_recipe(
        &mut self,
        passport: &CapabilityPassport,
        pool_id: &str,
        mut recipe: ServiceRecipe,
    ) -> Result<(), PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "accept_recipe") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "accept_recipe", "", &e).await;
                return Err(e);
            }
        };
        // only the developer-conductor (root-of-trust) signs a production recipe.
        if !is_dev {
            let e = PoolRefusal::NotGranted;
            self.deny_msg(&actor, "accept_recipe", &digest, &e).await;
            return Err(e);
        }
        let present = self
            .pools
            .get(pool_id)
            .map(|p| p.capsule_refs.iter().any(|r| r.content_digest == recipe.capsule_digest))
            .unwrap_or(false);
        if !present {
            let e = PoolRefusal::Invalid("recipe capsule_digest not present in pool".to_string());
            self.deny_msg(&actor, "accept_recipe", &digest, &e).await;
            return Err(e);
        }
        recipe.accepted_by = Some(actor.clone());
        recipe.accepted_at = Some(self.clock.now());
        if let Some(p) = self.pools.get_mut(pool_id) {
            p.visibility = PoolVisibility::Production;
            p.owner_agent_id = actor.clone(); // production owned by developer/system
        }
        let _ = self.write_recipe(pool_id, &recipe).await;
        let _ = self
            .write_audit(&actor, "accept_recipe", Some(pool_id), None, &digest, "allowed", None)
            .await;
        Ok(())
    }

    /// Invoke a production service: a runtime/vendor passport activates the pool's capsule and
    /// runs the recipe's entry contract. The invocation is a real capsule ACTIVATION (resume +
    /// dispatch), NOT a message. Writes an audit/receipt fact and returns the typed result.
    pub async fn invoke(
        &self,
        passport: &CapabilityPassport,
        pool_id: &str,
        inputs: Value,
    ) -> Result<Value, PoolRefusal> {
        let actor = passport.subject.clone();
        let (digest, is_dev) = match self.authed(passport, "invoke") {
            Ok(x) => x,
            Err(e) => {
                self.deny_msg(&actor, "invoke", "", &e).await;
                return Err(e);
            }
        };
        // there must be a signed recipe and the pool must be in production.
        let recipe = match self.read_recipe(pool_id).await {
            Some(r) if r.accepted_by.is_some() => r,
            _ => {
                let e = PoolRefusal::Invalid("no accepted recipe for pool".to_string());
                self.deny_msg(&actor, "invoke", &digest, &e).await;
                return Err(e);
            }
        };
        let production = self.pools.get(pool_id).map(|p| p.visibility == PoolVisibility::Production).unwrap_or(false);
        if !production {
            let e = PoolRefusal::Invalid("pool is not in production".to_string());
            self.deny_msg(&actor, "invoke", &digest, &e).await;
            return Err(e);
        }
        // the caller's passport must carry the recipe's required scopes.
        if !recipe.required_scopes.iter().all(|s| passport.scopes.iter().any(|p| p == s)) {
            let e = PoolRefusal::Invalid("missing required invoke scope".to_string());
            self.deny_msg(&actor, "invoke", &digest, &e).await;
            return Err(e);
        }
        // the caller needs an invoke grant (ActivateCapsule) on the production pool.
        if let Err(e) = self.pool_authorized(&actor, is_dev, pool_id, PoolRight::ActivateCapsule) {
            self.deny_msg(&actor, "invoke", &digest, &e).await;
            return Err(e);
        }
        // the pool's capsule digest must match the signed recipe (homogeneous service image).
        let matches = self
            .pools
            .get(pool_id)
            .map(|p| p.capsule_refs.iter().any(|r| r.content_digest == recipe.capsule_digest))
            .unwrap_or(false);
        if !matches {
            let e = PoolRefusal::Invalid("capsule digest mismatch".to_string());
            self.deny_msg(&actor, "invoke", &digest, &e).await;
            return Err(e);
        }
        // ACTIVATE: resume the capsule bytes and dispatch the entry contract (real activation,
        // content-addressed → any replica is identical; pick by digest).
        let bytes = match self.content.get(&recipe.capsule_digest) {
            Some(b) => b.clone(),
            None => {
                let e = PoolRefusal::Invalid("capsule bytes missing".to_string());
                self.deny_msg(&actor, "invoke", &digest, &e).await;
                return Err(e);
            }
        };
        let machine = match IgniterMachine::resume_bytes(&bytes, None, "in_memory").await {
            Ok(m) => m,
            Err(_) => {
                let e = PoolRefusal::Invalid("capsule activation failed (resume)".to_string());
                self.deny_msg(&actor, "invoke", &digest, &e).await;
                return Err(e);
            }
        };
        let result = match machine.dispatch(&recipe.entry_contract, inputs).await {
            Ok(r) => r,
            Err(_) => {
                let e = PoolRefusal::Invalid("capsule activation failed (dispatch)".to_string());
                self.deny_msg(&actor, "invoke", &digest, &e).await;
                return Err(e);
            }
        };
        let _ = self
            .write_audit(&actor, "invoke", Some(pool_id), Some(&recipe.capsule_digest), &digest, "allowed", Some(&recipe.entry_contract))
            .await;
        Ok(result)
    }
}

impl CoordinationHub {
    /// Record an HTTP ingress event (accepted or denied) as a bitemporal audit fact, carrying
    /// the correlation id + idempotency key. Used by the `ingress` front door for events the
    /// inner `invoke` audit does not cover (e.g. missing passport / no route). (P6)
    pub async fn audit_ingress(
        &self,
        actor: &str,
        path: &str,
        outcome: &str,
        reason: Option<&str>,
        correlation_id: &str,
        idempotency_key: Option<&str>,
    ) -> Result<(), EngineError> {
        let value = json!({
            "actor": actor,
            "operation": "ingress",
            "path": path,
            "outcome": outcome,
            "reason": reason,
            "correlation_id": correlation_id,
            "idempotency_key": idempotency_key,
        });
        let fact = Fact {
            id: format!("ingress:{}:{}", correlation_id, uuid::Uuid::new_v4()),
            store: COORD_AUDIT_STORE.to_string(),
            key: format!("ingress:{}", correlation_id),
            value,
            value_hash: String::new(),
            causation: None,
            transaction_time: self.clock.now(),
            valid_time: None,
            schema_version: 1,
            producer: Some(json!("ingress")),
            derivation: None,
        };
        self.audit.write_fact(fact).await
    }
}
