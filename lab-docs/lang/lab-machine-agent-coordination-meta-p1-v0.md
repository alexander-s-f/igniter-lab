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

## Next card

`LAB-MACHINE-AGENT-POOLS-P2` — local AgentRegistry + CapsulePoolRegistry + strict ACL
proof over existing capsules, with all operations audited as facts.
