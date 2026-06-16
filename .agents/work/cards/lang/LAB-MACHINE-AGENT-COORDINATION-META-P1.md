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

## Discussion addendum (2026-06-16)

The meta-doc now carries a locked **discussion addendum**
(`lab-docs/lang/lab-machine-agent-coordination-meta-p1-v0.md`): concurrency model (one machine,
no thread-per-agent), 6 locked decisions (passport≠ACL, AuditEvent-first, developer=local
root-of-trust, transfer≈receipt-gated-write, content-addressed CapsuleRef), and — added by the
developer-conductor — the **production mode**: agentless pool-as-service (a pool of homogeneous
capsules = a stateless replica set over an immutable image, state in the fact log; SparkCRM
webhooks at 2–5k rpm on ONE instance), and the **dev→prod handoff** (N agents → candidate
capsule + `ServiceRecipe` → TransferEnvelope → developer signs/mints prod passport/takes
ownership → agentless serving; audit trail = deployment provenance). The substrate **degrades
gracefully** to plain serving — coordination is a dev-time layer only.

The P2 card below is now written AND **CLOSED 2026-06-16** —
`LAB-MACHINE-AGENT-POOLS-P2.md` (impl `igniter-machine/src/coordination.rs`, 9 tests,
`lab-docs/lang/lab-machine-agent-pools-p2-v0.md`). Foundation proven: AgentRegistry +
CapsulePoolRegistry + PoolGrant ACL + AuditEvent + `verify_passport` reuse + content-addressed
CapsuleRef + audited ownership transfer; production-mode kept reachable, not served.

**P3 MessengerBus CLOSED 2026-06-16** — `LAB-MACHINE-AGENT-MESSENGER-P3.md` (impl in
`coordination.rs`, 9 tests, `lab-docs/lang/lab-machine-agent-messenger-p3-v0.md`). Append-only
messages as facts (note/request+ack/escalation), participant visibility, capsule-refs-aren't-
grants, every op audited — "facts + audit + ACL, not hidden chat".

**P4 CapsuleTransferEnvelope CLOSED 2026-06-16** — `LAB-MACHINE-AGENT-TRANSFER-P4.md` (impl in
`coordination.rs`, 9 tests, `lab-docs/lang/lab-machine-agent-transfer-p4-v0.md`). Audited
two-phase `proposed→accepted/rejected/revoked` (pattern reuse of P6, not the write module);
content-addressed ref import, immutable source, idempotent accept, declared-rights-only,
developer override, carries optional `recipe_digest`. **Coordination track P2→P3→P4 complete:
rights → communication → transfer.**

**P5 ServiceRecipe + agentless serving CLOSED 2026-06-16** — `LAB-MACHINE-SERVICE-RECIPE-P5.md`
(impl in `coordination.rs`, 7 tests, `lab-docs/lang/lab-machine-service-recipe-p5-v0.md`). **THE
BRIDGE is built**: developer signs a `ServiceRecipe` → pool becomes dev-owned `Production` → a
vendor/runtime passport `invoke`s via REAL capsule activation (resume+dispatch, not messenger) →
audited. Homogeneous content-addressed replicas. Proven end-to-end on a real `Add` capsule (→ 5,
42), including the full transfer→accept→sign→invoke handoff. The original vision (agents build →
developer signs/deploys → dumb production serves webhooks) is realized on one audited substrate.
**P6 HTTP ingress front door CLOSED 2026-06-16** — `LAB-MACHINE-SERVICE-HTTP-INGRESS-P6.md`
(impl `igniter-machine/src/ingress.rs` + `coordination::audit_ingress`, 9 tests incl. a real
`127.0.0.1` HTTP/1.1 round-trip, `lab-docs/lang/lab-machine-service-http-ingress-p6-v0.md`). The
INBOUND edge: vendor webhook → validate passport (before activation) → route → production pool →
`hub.invoke` (real capsule activation) → HTTP response → audit (correlation+idempotency). First
"dumb production mode" proof: `HTTP webhook → production capsule service → response` over a real
loopback socket → `200 OK` + `42`. Loopback only; no public internet / outbound effect /
messenger hot path. **Full serving line: capsule → recipe → production pool → HTTP ingress.**
**P7 ingress duplicate policy CLOSED 2026-06-16** — `LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7.md`
(impl `coordination.rs` `DuplicatePolicy` on ServiceRecipe + `ingress.rs` decide/apply, 8 tests,
`lab-docs/lang/lab-machine-service-ingress-duplicate-policy-p7-v0.md`). Duplicate handling is a
CONFIGURABLE BUSINESS strategy on the recipe, NOT a canon default: `idempotency=safety envelope`
(same key+different payload→409) always on; policy decides repeats (`dedup_strict`/`treat_as_fresh`/
`bounded_fresh(n)`/off). Proves Alex's auction lever: same input → distinct generated code per
attempt (1000/1001/1002 via injected attempt_index). All audited; policy lives on the recipe, not
the VM. Next: P8 `pool_sizing`/`activate_many` replica fanout (throughput over the now
correctness-protected serving path); then SparkCRM-shaped ingress behind human-approved staging;
P-votes (deferred); later federation + distributed dedup.

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
