# lab-machine-agent-pools-p2-v0 — agent/pool registry + ACL + audit foundation

**Card:** `LAB-MACHINE-AGENT-POOLS-P2` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1` + its 2026-06-16 discussion addendum)
**Status:** CLOSED — foundation implemented + proven. 9 machine tests
(`tests/coordination_pools_tests.rs`); full machine suite green (`cargo test
--no-default-features`). **No messenger (P3), no transfer envelope (P4), no production serving,
no federation.**

## What P2 builds

The first foundation brick of the coordination substrate — **Capability IO applied to
coordination**:

```text
subject action
  -> CapabilityPassport authenticates the SUBJECT (who)   (P5 verify_passport, reused)
  -> Pool ACL authorizes the OPERATION on the POOL (what) (this module)
  -> every op (allowed OR denied) writes an AuditEvent fact  (receipt principle, P1)
```

`igniter-machine/src/coordination.rs`:
`AgentIdentity`/`AgentKind`/`AgentStatus`, `CapsulePool`/`PoolVisibility`, `PoolRight`,
`CapsuleRef` (content-addressed), `PoolGrant` (ACL), `AuditEvent` (facts in `__coord_audit__`),
and `CoordinationHub` with `register_agent` / `create_pool` / `add_capsule` / `list_capsules` /
`check_right` / `grant` / `transfer_ownership`, all gated by one `guard()` boundary.

## Locked decisions honored

1. **Passport ≠ ACL.** `guard` runs `verify_passport(passport, "coordination", op_class,
   clock)` (WHO + op-class cleared) then the ACL (`owner || developer || explicit PoolGrant`)
   for WHO-on-WHICH-pool. Both required.
2. **AuditEvent is the schema** — `{ actor, operation, target_pool, target_capsule,
   authority_digest, outcome, reason }` + the fact's `transaction_time`, in `__coord_audit__`.
   Reuses the receipt *principle*, its own shape (not `EffectReceipt`).
3. **DeveloperConductor = local root-of-trust** — `kind == Developer` is privileged in the ACL
   (can grant / take ownership on any pool) but **every action is an audited fact** (proven:
   the developer's `grant_access` + `admin_pool` events appear in the trail).
4. **CapsuleTransferEnvelope** — not in P2 (P4); but `transfer_ownership` is the audited
   ownership-handoff primitive it will build on.
5. **CapsuleRef content-addressed** — `capsule_id == content_digest` (blake3 of bytes); the
   content store dedups identical bytes to one image (proven: two adds of identical bytes →
   `content_count == 1`, two refs sharing a digest).
6. **Concurrency v0 = one machine** — in-memory registries (proof-local; a real host wraps them
   in a lock), audit facts in the bitemporal `TBackend`.

## Production-mode constraints kept open (not implemented)

- `PoolVisibility::Production` is a valid state (a pool can be created/promoted to it);
- pool **ownership is data and transferable** (`transfer_ownership` → owner changes, audited);
- `AuditEvent.actor` is a free `String`, and `AgentKind::RuntimeActor` + a `vendor:*` subject
  are first-class (proven) — so agentless production serving and the dev→prod handoff remain
  reachable without a redesign. No `ServiceRecipe`, transfer, or serving built here.

## Proof (9 tests, `tests/coordination_pools_tests.rs`)

| acceptance | test |
|---|---|
| owner creates a pool and adds a capsule (audited) | `owner_creates_pool_and_adds_capsule` |
| another agent cannot list/activate/fork without a grant | `other_agent_denied_without_grant` |
| an explicit grant enables ONLY the granted op | `explicit_grant_enables_only_granted_op` |
| content-addressed dedup (identical bytes → one image) | `content_addressed_dedup` |
| developer grants + takes ownership; audited; visibility→production | `developer_grants_and_takes_ownership_audited` |
| revoked agent cannot access | `revoked_agent_cannot_access` |
| passport failure refused before ACL, audited, no state change | `passport_failure_refused_before_acl` |
| every op (allowed + denied) produces a bitemporal audit fact | `every_operation_is_audited` |
| runtime/vendor actor schema supported (`vendor:acme`, `RuntimeActor`) | `runtime_vendor_actor_schema_supported` |

## Closed (held)

No messenger. No transfer envelope. No `ServiceRecipe` / production serving. No federation /
consensus. No network. No autonomous scheduler. No crypto signatures (identity registry-local;
real keys later). No language change. No VM change (the VM never learns about agents/pools).
No MCP hot-path.

## Next route

- **P3 — MessengerBus**: append-only audited messages (note/request/ack/escalation), capsule
  refs in messages, strict visibility by participant/pool grant — reuses `guard` + audit.
- **P4 — CapsuleTransferEnvelope**: `proposed → accepted/rejected/revoked` (≅ receipt-gated
  write), import into target pool with rights — builds on `transfer_ownership`.
- later: `ServiceRecipe` + dev→prod handoff + agentless production serving; then federation.
- engineering: a real host wraps `CoordinationHub` in a lock (or registries in `RwLock`); audit
  facts already concurrency-safe via the sharded log.
