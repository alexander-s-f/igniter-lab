# Card: LAB-MACHINE-AGENT-POOLS-P2 — local agent/pool registry + ACL + audit

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) (+ its 2026-06-16 discussion addendum) — read the meta-focus first. This is the first foundation brick of that direction.

**Status: READY — foundation implementation card.** First concrete slice after the
coordination meta-focus. Local single-machine only: identities, pools, strict ACL, and a single
audit-event schema. **No messenger (P3), no transfer envelope (P4), no federation/consensus.**

## Goal

Prove the coordination **foundation** on one `igniter-machine`:

```text
AgentRegistry            -- registered participants (agents / developer / system)
CapsulePoolRegistry      -- named pools, each owned by an agent, holding content-addressed refs
PoolGrant ACL            -- strict, explicit rights per (agent, pool, operation); no implicit access
AuditEvent (facts)       -- every pool operation writes one bitemporal audit fact
CapabilityPassport reuse -- the SUBJECT is authenticated by P5 verify_passport, not a new auth path
content-addressed CapsuleRef -- refs point at capsule bytes by content_digest (dedup, no copy)
```

## Locked decisions (from the meta-doc addendum — do not re-open)

1. **Passport ≠ ACL.** Passport authenticates *who* (P5 `verify_passport`, subject + boundary);
   PoolGrant ACL authorizes *what on which pool*. Host checks both.
2. **AuditEvent is THE first schema** — everything downstream depends on it. Shape:
   `{ event_id, actor (agent_id), operation, target_pool, target_capsule?, authority_digest,
   outcome (allowed|denied), reason, transaction_time }`. Stored as facts in a `__coord_audit__`
   store. Reuses the receipt *principle*, NOT the write `EffectReceipt` schema.
3. **DeveloperConductor = local root-of-trust** — issuer/approver of grants; every conductor
   action is itself an AuditEvent (visible, not invisible root).
4. **CapsuleRef content-addressed** — `CapsuleRef { capsule_id, content_digest, created_by,
   source_pool, created_at, labels }`; pools hold refs, capsule bytes live once (dedup by digest).
5. **Concurrency v0 = one machine** — immutable frames + `ShardedFactLog`; no thread-per-agent,
   no second instance.

## Production-mode design constraints (do NOT preclude; do NOT implement here)

Per the addendum's dev→prod handoff + agentless serving:

- `CapsulePool.visibility` enum must be extensible to include `production` (P2 may define
  `private | shared | public_read`; leave room for `production`).
- pool **ownership must be transferable** later (store owner as data, not a const).
- `AuditEvent.actor` must be able to be a non-agent subject later (e.g. `vendor:*`) — keep
  `actor` a free `String` subject, not an `enum agent-only`.
- These keep the dev→prod handoff (`ServiceRecipe`, developer sign-off) and agentless pool-as-
  service reachable without a redesign. No recipe / transfer / serving in P2.

## Surfaces to build (proof-local, machine-local)

`igniter-machine/src/coordination.rs` (suggested):
- `AgentIdentity` + `AgentRegistry` (register / get / set_status; status `active|paused|revoked`).
- `CapsulePool` + `CapsulePoolRegistry` (create_pool, add_capsule_ref, list, drop).
- `PoolRight` enum + `PoolGrant` + ACL store; `authorize(agent, pool, right)` checks owner OR
  an explicit grant.
- `CapsuleRef` (content-addressed; digest computed from the capsule bytes via `CapsuleManager`).
- `AuditEvent` writer — every op (allowed or denied) writes one fact to `__coord_audit__`.
- `run_pool_op(registry, acl, audit, clock, passport, op)` — the host boundary: P5
  `verify_passport` (who) → ACL `authorize` (what) → perform on `CapsuleManager` → AuditEvent.

Reuse, don't reinvent: `CapsuleManager` (frames), `verify_passport` (P5), `ClockProvider` (P4),
`TBackend` (audit facts), `blake3` (digests).

## Must-answer

1. Exact `AuditEvent` fields + store namespace (lock the schema — downstream depends).
2. ACL model: owner-implicit + explicit `PoolGrant` per (agent, pool, right)? Where stored?
3. How does a pool op authenticate the subject — `verify_passport` with which capability_id /
   scope convention (e.g. `pool` capability + scope `pool:<id>:<right>`)?
4. `CapsuleRef` digest source — `CapsuleManager` bytes (deterministic) hashed with blake3?
5. What is a runtime refusal (denied, audited, no state change) vs an allowed op (state change +
   audited)? (Mirror the IO boundary: denial-as-data.)
6. Where does the DeveloperConductor privilege live — a `kind == developer` identity that the
   ACL treats as able to grant? And is that grant itself audited?
7. Proof that the VM/contract path is untouched (no contract learns about agents/pools).

## Acceptance (≥ 50 checks or Rust machine tests)

- owner can create a pool and add a capsule ref;
- another agent CANNOT list / activate / fork without a grant (denied + audited);
- an explicit grant enables ONLY the granted operation (not others);
- a content-addressed `CapsuleRef` dedups identical capsule bytes by digest;
- developer-conductor can grant access and the grant is itself an audited fact;
- a revoked agent cannot access the pool;
- EVERY operation (allowed and denied) produces a bitemporal `AuditEvent` fact;
- passport failure (wrong subject / missing scope) is refused before ACL, audited, no change;
- VM `dispatch` still has no pool/agent/ACL access (structural).

## Closed (P2)

No messenger. No transfer envelope. No ServiceRecipe / production serving. No federation /
consensus. No network. No autonomous scheduler. No language change. No VM change. No MCP
hot-path. No crypto signatures (identity is registry-local; real keys later).

## Next

- P3 — MessengerBus (append-only audited messages; direct/request/ack/escalation; capsule refs).
- P4 — CapsuleTransferEnvelope (proposed→accepted/rejected/revoked ≅ receipt-gated write).
- (later) ServiceRecipe + dev→prod handoff + agentless production serving; then federation.
