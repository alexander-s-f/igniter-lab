# Card: LAB-MACHINE-AGENT-COORDINATION-META-P1 — agent coordination substrate

**Status: READY — META FOCUS / DESIGN DIRECTION.** This card formalizes the idea of
using `igniter-machine` as the substrate for between-agent coordination. It is not a full
implementation card.

## Goal

Define a machine-native coordination model:

```text
Agent identities
+ named capsule pools with strict rights
+ audited capsule transfer protocol
+ bitemporal messenger bus
+ meta-card journal
+ developer-as-conductor role
```

The aim is to create a future platform for distributed agent organization without
collapsing VM purity, MCP control-plane, and production IO data-plane.

## Core validation

This direction fits current machine surfaces:

- capsules already exist as immutable machine frames;
- `CapsuleManager` already supports snapshot/list/activate/fork/diff/activate_many;
- `TBackend` already stores bitemporal facts;
- capability IO P1-P7 already proved receipts, idempotency, host clock, passports,
  read/write, and reconciliation;
- MCP already gives an agent control plane;
- VM remains deterministic and has no executor/agent/messenger access.

Therefore the missing piece is **coordination semantics**, not raw storage.

## Formal model

### AgentIdentity

Registered participant:

```text
agent_id, kind(agent|developer|system), label, owner_ref, status,
default_pool, registered_at, metadata_digest
```

### CapsulePool

A named namespace of capsules controlled by an agent or group. Use `pool`, not
`workspace`.

```text
pool_id, name, owner_agent_id, visibility, capsule_refs, acl, created_at
```

Rights are explicit:

```text
read_pool, list_capsules, activate_capsule, fork_capsule, import_capsule,
export_capsule, drop_capsule, grant_access, admin_pool
```

No implicit cross-pool access.

### CapsuleTransferEnvelope

Audited handoff between agents/pools:

```text
transfer_id, from_agent, to_agent, from_pool, to_pool,
capsule_id, capsule_digest, rights_granted, reason, status, receipt_ref
```

Transfers import a capsule/ref into the target pool; source capsules remain immutable.

### MessengerBus

Append-only bitemporal message facts:

```text
message_id, thread_id, from_agent, to, kind, body_digest,
body_ref, capsule_refs, requires_ack, created_at, valid_time
```

Kinds: `note`, `request`, `proposal`, `vote`, `decision`, `ack`, `escalation`.

### MetaCardJournal

Bitemporal journal of agent focus/status:

```text
card_id, agent_id, focus, status, scope_digest, evidence_refs,
created_at, updated_at
```

### DeveloperConductor

The developer has privileged messenger status: route, pause, approve transfer/grant,
request evidence, arbitrate. Privilege must be explicit and audited; no invisible root
side-channel.

## P1 deliverables

- Design note:
  `lab-docs/lang/lab-machine-agent-coordination-meta-p1-v0.md`
- This meta-card.
- No implementation.

## Recommended next card: LAB-MACHINE-AGENT-POOLS-P2

Implement/prove local single-machine registry only:

- `AgentRegistry`;
- `CapsulePoolRegistry`;
- strict ACL for pool operations;
- create/list/import/export capsule refs;
- every operation writes an audit fact;
- no messenger yet except audit events.

Proof target: at least 50 checks or Rust machine tests covering:

- owner can create pool and add capsule;
- other agent cannot list/activate/fork without grant;
- explicit grant enables only granted operation;
- transfer/import creates target ref but source frame remains immutable;
- developer conductor can approve grant and the approval is audited;
- revoked agent cannot access pool;
- all operations produce bitemporal audit facts.

## Later route

- P3 — MessengerBus proof: direct message, request/ack, developer escalation, capsule refs.
- P4 — Transfer protocol: propose/accept/reject/revoke envelopes.
- P5 — votes/coordination as messages; no consensus yet.
- P6 — multi-machine/federation spike; signed transfer envelopes; conflict/replay handling.

## Closed surfaces

- No network between machines.
- No distributed consensus.
- No autonomous agent scheduler.
- No hidden mutable chat state.
- No language actor model.
- No VM changes.
- No production authority.
- No MCP hot-path expansion beyond local tool facade.

## Anti-drift rule

Agent coordination is **machine-host substrate**. It is not contract IO, not VM semantics,
not canon language authority, and not a replacement for the capability IO data-plane.
