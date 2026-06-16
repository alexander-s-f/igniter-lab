# LAB-MACHINE-AGENT-COORDINATION-META-P1 — Agent Coordination Substrate

Status: meta-focus / design direction  
Date: 2026-06-16  
Authority: lab direction only; no canon language claim; no full implementation authorized

## Thesis

`igniter-machine` can become the coordination substrate for multi-agent work without
turning the Igniter language into an IO/chat/runtime system.

The shape is:

```text
Capsule pools  = private/shared state frames
Protocol       = transfer/activation/permission rules
Messenger bus  = audited bitemporal communication facts
Meta journal   = agent registration, focus cards, status, receipts
Developer      = privileged conductor/supervisor role, not an unlogged side-channel
```

This is a host/machine layer. Contracts remain pure. VM remains deterministic. MCP remains
a control/debug plane. Production-style data-plane capabilities remain governed by the
capability IO boundary.

## Current building blocks

Verify-first surfaces already exist:

- `CapsuleManager`: immutable capsule frames, snapshot/list/activate/fork/diff/activate_many.
- `TBackend`: bitemporal fact store with transaction-time and valid-time axes.
- Capability IO P1-P7: receipts as facts, idempotency, host clock, capability passports,
  read/write executors, unknown-write reconciliation.
- MCP control plane: agent can drive machine tools, but this is not language IO.

The missing layer is not raw storage. It is **coordination semantics**: identities,
rights, transfers, messages, and governance receipts.

## Core objects

### AgentIdentity

A registered participant.

Suggested fields:

```text
agent_id: String
kind: agent | developer | system
label: String
owner_ref: String
public_key_ref: Option[String]     # later; no crypto in P1
default_pool: Option[String]
status: active | paused | revoked
registered_at: f64
metadata_digest: String
```

P1 keeps identity proof-local / registry-local. Real cryptographic signatures are later.

### CapsulePool

A named namespace of capsule refs controlled by one or more agents. This is the word to
use instead of `workspace`, because workspace is too overloaded.

```text
pool_id: String
name: String
owner_agent_id: String
visibility: private | shared | public_read
capsule_refs: [CapsuleRef]
acl: [PoolGrant]
created_at: f64
```

Rights are strict and explicit:

```text
read_pool | list_capsules | activate_capsule | fork_capsule | import_capsule |
export_capsule | drop_capsule | grant_access | admin_pool
```

No implicit access to other agents' pools.

### CapsuleRef

A stable reference to an immutable frame.

```text
capsule_id: String
content_digest: String
created_by: agent_id
source_pool: pool_id
created_at: f64
labels: [String]
```

### CapsuleTransferEnvelope

The audited object used when an agent sends a capsule or capsule reference to another
agent/pool.

```text
transfer_id: String
from_agent: agent_id
to_agent: agent_id | group_id
from_pool: pool_id
to_pool: pool_id
capsule_id: String
capsule_digest: String
rights_granted: [PoolRight]
reason: String
status: proposed | accepted | rejected | revoked
receipt_ref: String
```

Transfer does not mutate the source capsule. It creates an import/ref in the target pool
with explicit rights.

### MessengerBus

An append-only audited message bus backed by bitemporal facts, not an opaque chat log.

```text
message_id: String
thread_id: String
from_agent: agent_id
to: agent_id | group_id | developer
kind: note | request | proposal | vote | decision | ack | escalation
body_digest: String
body_ref: Option[String]
capsule_refs: [CapsuleRef]
requires_ack: Bool
created_at: f64
valid_time: Option[f64]
```

The bus should support direct messages, group threads, requests to developer, and future
consensus/vote messages. P1 does not implement consensus.

### MetaCardJournal

A bitemporal journal of agent intent and state:

```text
card_id: String
agent_id: String
focus: String
status: proposed | active | blocked | done | superseded
scope_digest: String
evidence_refs: [String]
created_at: f64
updated_at: f64
```

This is how agents register what they are doing and avoid invisible side quests.

### DeveloperConductor

The developer is a privileged role in the messenger, but not an invisible root user.

Allowed:

- issue meta focus / route decisions;
- approve transfers or grants;
- pause/revoke agents;
- request status or evidence;
- arbitrate conflicts.

Required:

- actions are written as messages/receipts;
- overrides are explicit;
- developer authority is visible in the audit trail.

## Model

Single-machine v0:

```text
one igniter-machine instance
  -> AgentRegistry
  -> CapsulePoolRegistry
  -> MessengerBus facts
  -> MetaCardJournal facts
  -> CapabilityPassport checks for pool/message operations
```

Multi-machine later:

```text
machine A exports signed transfer envelope
machine B imports after verification
messenger threads federate by receipt exchange
consensus/voting becomes a higher protocol over audited messages
```

P1 must not jump to distributed consensus. First prove local correctness.

## Validation

Why this fits Igniter:

- capsules are already immutable frames;
- TBackend already stores bitemporal facts;
- capability passports already enforce host-boundary authority;
- receipts already give idempotency/audit/replay;
- MCP already gives an agent control plane;
- VM stays deterministic and does not learn about agents or messages.

Main risks:

- turning messenger into hidden mutable chat state;
- giving agents implicit cross-pool access;
- treating developer intervention as out-of-band authority;
- opening network/federation before local ACL/audit is proven;
- confusing this with language-level actor/concurrency semantics.

Guardrail:

> Agent coordination is machine-host substrate. It is not contract IO, not VM semantics,
> and not canon language authority.

## Recommended sequence

### P1 — meta focus / readiness

This document and card. No code.

### P2 — local registry proof

Implement proof-local or machine-local:

- AgentRegistry;
- CapsulePoolRegistry;
- pool ACL checks;
- create/list/import/export capsule refs;
- audit facts for every operation.

No messenger yet beyond audit receipts.

### P3 — messenger bus proof

Implement append-only audited messages:

- direct message;
- request/ack;
- developer escalation;
- capsule refs inside messages;
- strict visibility by participant/pool grants.

### P4 — transfer protocol

Implement capsule transfer envelopes:

- propose;
- accept/reject;
- import into target pool with rights;
- revoke future access;
- source capsule remains immutable.

### P5 — multi-agent orchestration

Add votes/coordination patterns as messages:

- proposal;
- vote;
- decision receipt;
- no consensus/federation yet.

### P6 — multi-machine/federation spike

> **Readiness map PREPARED (2026-06-16): `LAB-MACHINE-FEDERATION-READINESS-P1`
> → `lab-docs/lang/lab-machine-federation-readiness-p1-v0.md`** — two-plane model (replication vs
> effect), single-writer-per-key-space idempotency, failure modes, deferred non-goals, and a
> low-risk v0 (`…-CAPSULE-SYNC-P2`, replication-plane only). Design only; not authorized.

Only after local model is proven:

- export/import envelope between machine instances;
- signed digest or key material;
- conflict/replay handling.

## Closed surfaces for P1

- No implementation.
- No network between machines.
- No consensus algorithm.
- No autonomous agent scheduler.
- No hidden chat state.
- No language actor model.
- No VM changes.
- No production authority.

## Discussion addendum (2026-06-16) — concurrency, decisions, production mode

> Locked in discussion with the developer-conductor and Meta-Architect. Recorded here so the
> next agents do not re-open these. The coordination substrate is **Capability IO (P1–P9,
> +P10 HTTP readiness) applied to a new domain**, not a separate "agent chat platform".

### Reframe: same boundary, new domain

```text
agent/vendor action
  -> CapabilityPassport authenticates the SUBJECT (who)        (P5, already built)
  -> Pool ACL authorizes the OPERATION on the RESOURCE (what)  (new, P2)
  -> operation writes an AuditEvent fact                       (receipt principle, P1)
  -> capsule/message/transfer stays replayable + inspectable   (bitemporal TBackend)
```

~70% of the substrate already exists: passport = rights, receipt = audit, bitemporal store =
journal, capsule = immutable frame, `ShardedFactLog` = concurrency, reconcile/retry/queue =
durable effect semantics. The genuinely new layer is **identity + pool partitioning + ACL +
one audit schema**.

### Concurrency model (v0) — answers "многопоточность?"

Two different meanings must not be conflated:

1. **Concurrent agents on ONE machine — already safe, no thread-per-agent.** Capsules are
   immutable (fork = new frame); `activate_many` already runs concurrently via `join_all` with
   no data races; the only contended resource (the fact log: membership, ACL, messages) is a
   `ShardedFactLog` with per-shard `RwLock`, so appends serialize per shard. v0 multi-agent
   needs **no** extra instances and **no** OS-thread-per-agent.
2. **Multiple `igniter-machine` INSTANCES** (a network of machines) is the
   federation/consensus axis — deferred (P6). That is distribution, NOT "multithreading".

→ v0 = one instance, one fact log, sharded locking. Concurrency is solved by the immutable
model itself.

### Locked design decisions

1. **Passport ≠ ACL.** Passport = *who you are* (subject authenticated at the boundary, P5).
   Pool ACL = *what you may do on this pool* (grants stored as facts). Do not stuff per-pool
   grants into passport scopes (scope explosion). The host checks both.
2. **AuditEvent is the FIRST brick (P2), before messenger/transfer.** Everything downstream
   writes audit events, so fix the schema first:
   `{ actor, operation, target_pool, target_capsule, authority_digest, outcome, reason,
   transaction_time }`. It reuses the receipt *principle*, but is its own fact shape — NOT the
   write `EffectReceipt` schema.
3. **DeveloperConductor = local root-of-trust**, not a "privileged chat user". In v0 the
   developer is the **issuer/approver of passports and grants** and the **production sign-off**.
   Every conductor action is itself an audited fact — visible in the trail, not an invisible
   root side-channel.
4. **CapsuleTransferEnvelope ≈ receipt-gated write (P6).** `proposed → accepted/rejected/
   revoked` is isomorphic to `prepared → committed/denied`: a transfer is a "write" whose gate
   is the recipient's acceptance. P4 reuses the two-phase receipt machinery directly.
5. **CapsuleRef is content-addressed.** A pool stores `CapsuleRef(content_digest)`, never a
   per-pool byte copy. Dedup by digest, or a shared mesh bloats fast.
6. **Concurrency v0 = one machine** (see above).

### Production mode — agentless pool-as-service

The substrate must **degrade gracefully** to a plain service runtime with no agents (e.g. a
SparkCRM pool serving vendor webhooks at 2–5k rpm). Two actor classes, ONE boundary:

- **dev-time actors** (agents + developer): build and coordinate (pools, messenger, transfer);
- **runtime actors** (external callers / webhooks): invoke a deployed service pool.

A vendor presents a passport exactly like an agent (`subject="vendor:acme"`, scope
`invoke:pool:X`); the activation writes an audit/receipt fact. So agentless production is the
**same** pool + passport + audit + activation + capability-IO — just with the
messenger/transfer (dev-time) layer absent at runtime. **Coordination is a dev-time layer; the
runtime is plain serving.**

### "Pool of homogeneous capsules = server architecture?" — YES, precisely

A **stateless replica set over an immutable image**, with state in the fact log, not the
capsules:

- replicas are **provably identical** (same `content_digest`) — not "hopefully the same";
- the single bitemporal fact log is the single source of truth + audit;
- closer to **event-sourced stateless workers** than stateful app servers — and webhooks **are
  events** (arrive → append → done);
- `activate_many` already gives the horizontal compute parallelism.

At 2–5k rpm (~30–80 writes/sec): activations are lock-free parallel (immutability), writes
serialize per-shard in `ShardedFactLog` but are **not** the bottleneck at that rate. One
instance suffices; sharding pools across instances is a later throughput lever (federation),
not a correctness need.

### Dev → prod handoff (developer-owned production pool)

The lifecycle bridge, built from existing primitives — **no new mechanism**:

```text
[dev]      N agents build in their pools → converge on a CANDIDATE capsule (immutable image)
           + a ServiceRecipe (how to run it)
[handoff]  package as a CapsuleTransferEnvelope to the developer (proposed)
[sign-off] developer REVIEWS the candidate's audit trail + recipe + passport scopes →
           ACCEPT + SIGN: mints a production passport (P5; conductor = root-of-trust),
           promotes pool visibility → production, takes ownership (audited ACL transfer)
[prod]     the pool is now developer-owned, agentless, serving webhooks under the prod passport
```

The audit trail IS the **deployment provenance**: "who authored this production service, who
approved it" is answerable from facts — directly useful for SparkCRM compliance.

### New object: `ServiceRecipe` (deployment descriptor)

The candidate capsule is the immutable image; the recipe is the deploy descriptor the developer
signs:

```text
recipe_id, candidate_capsule_id, candidate_digest, entry_contract,
capability_bindings: [{ capability_id -> executor_binding }],
required_scopes: [String], pool_sizing: Int, signed_by: agent_id (developer), signed_at: f64
```

Immutable, digest-addressed; the developer's acceptance is the "signature" (a fact). Analogous
to an image + deployment manifest. This is the missing link between "a capsule" and "a running
service".

### Implication for the P2 foundation (do not preclude production mode)

P2 stays the pure foundation (registry + ACL + audit, no messenger), but must not box out
production mode:

- `CapsulePool.visibility` must be extensible to include `production`;
- pool ownership must be transferable (later) to the developer;
- `AuditEvent` must be able to record runtime invocations, not only dev-time ops.

These are P2 **design constraints**, not P2 implementation.

## Next card

`LAB-MACHINE-AGENT-POOLS-P2` — local AgentRegistry + CapsulePoolRegistry + strict PoolGrant ACL
+ AuditEvent schema + CapabilityPassport reuse + content-addressed CapsuleRef, all operations
audited as facts. No messenger (P3), no transfer (P4), no federation. See the addendum's design
constraints so the foundation keeps production-mode and the dev→prod handoff reachable.
