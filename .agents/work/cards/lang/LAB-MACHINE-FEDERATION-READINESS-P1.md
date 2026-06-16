# Card: LAB-MACHINE-FEDERATION-READINESS-P1 — one machine → a federation (readiness)

> **Front door for the substrate:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md).
> **Coordination seam this extends:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md)
> (its P6 federation spike) · **operational constraint:** [`LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1`](LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1.md).

**Lane:** readiness / architecture / future-network · **Skill:** idd-agent-protocol
**Status: READINESS / DESIGN ONLY — boundary map. NOT authorized implementation.** 2026-06-16.
No code, no distributed runtime, no consensus, no live network, no autonomous agent governance.

## One truth

```
Single-machine substrate:  STRONG (pools/transfer/messenger/recipe/ingress/dedup/fanout + P18–P25)
Federation:                NOT IMPLEMENTED, NOT AUTHORIZED
This card:                 identifies what BREAKS and which invariants MUST hold first
```

Authority ≠ evidence: the strong single-machine surface is **evidence**, not a license to federate.
**Agent authority: readiness/design only.**

## The organizing idea — TWO planes (federate them differently)

```
REPLICATION plane  immutable + content-addressed + append-only  → safe to mirror (no consensus)
                   capsule bytes (by digest), receipts, pool metadata, transfer envelopes, messages
EFFECT plane       live exactly-once execution (run_write_effect_atomic + in-process SingleFlight)
                   → OWNED by exactly one machine per key-space; must NOT be replicated active-active
```

**The hard line:** `exactly-one-effect` is enforced by an **in-process** per-key `SingleFlight`
over ONE RocksDB (P18). That lock does not span machines → the effect plane cannot go active-active
across machines without a distributed CAS gate, which is **explicitly deferred**.

## Deliverable

- **Packet:** [`lab-docs/lang/lab-machine-federation-readiness-p1-v0.md`](../../../lab-docs/lang/lab-machine-federation-readiness-p1-v0.md)
  — answers all 8 questions, grounded in live coordination/capability-IO surfaces, + a future route table.
  1. **Shareable** — capsule bytes by digest, receipts (read-only), pool metadata, transfer
     envelopes, messages: all content-addressed or append-only ⇒ merge by union/dedup, no agreement.
  2. **Locally authoritative** — developer root-of-trust, passport issuer, secret provider, live
     effect execution: trusted across a boundary only pairwise + explicitly; never merged.
  3. **Idempotency across machines** — **single-writer-per-key-space by deterministic
     `hash(key)→owner` routing** (v0); shared-backend **CAS** only if active-active is ever needed
     (deferred); cross-log receipt-key collision = detection backstop.
  4. **Capsule transfer across boundary** — signed P4 envelope → verify-before-import → digest-pull
     → idempotent import; rights apply to target ACL; serving authority minted **locally**.
  5. **Avoiding consensus too early** — everything is immutable-or-single-owner ⇒ agreement never
     required; conflicts → human/developer arbitration, not an automated protocol.
  6. **Minimal v0** — **read-only mirror + signed capsule sync; effects stay single-owner; NO
     active-active.** Delivers distribution/audit-federation/DR with zero consensus.
  7. **Failure modes** — split brain (fail-closed, no auto-failover), duplicate effect (partition
     prevents, collision detects), stale passport (revocation propagation = known gap), divergent
     receipt logs (append-only union; true conflict impossible under single-writer), clock skew
     (identity-keyed idempotency unaffected; ordering is causal not wall-clock).
  8. **Deferred non-goals** — quorum/consensus, leader election, CRDT, public mesh, autonomous agent
     voting, the distributed-lock/CAS prepare gate.
- **This card** (route + status).

## Authority

- Evidence: single-machine coordination (P2 pools / P3 messenger / P4 transfer / ServiceRecipe /
  ingress / dedup / fanout / bridge_effect) + capability-IO P18–P25 + deployment-topology P1.
- Agent authority: **readiness/design only** — done.

## Acceptance (met)

- [x] States federation is **not** authorized implementation (banner + status).
- [x] Identifies the **minimal safe v0** (read-only mirror + signed capsule sync; effects single-owner).
- [x] **Preserves exactly-one-effect** — single-writer-per-key-space; in-process SingleFlight stays
      sufficient because no key is ever held by two machines.
- [x] Names required **authority boundaries** (effect-authority partition, local explicit trust,
      secrets never leave, signed+verified transfer, human conflict arbitration).
- [x] **Separates capsule replication from effect execution** (the two-plane model is the spine).
- [x] Lists **failure modes** (Q7) and **non-goals** (Q8).
- [x] **Recommends a next card** — a low-risk v0 exists (`…-CAPSULE-SYNC-P2`, replication-plane only).

## Recommended next card (low-risk v0 — human-gated to open)

`LAB-MACHINE-FEDERATION-CAPSULE-SYNC-P2` — prove signed export → verify → digest-pull → idempotent
import between **two in-process machine instances** (no network), + read-only receipt/message
mirror. **NO effect crosses a boundary; NO active-active.** Low-risk: replication plane only
(immutable / content-addressed / append-only — the part that needs no consensus). The CAS /
distributed-gate slice that would unblock active-active effects is **separately gated** and must not
be opened without a real horizontal-effect-scale need + review.

## Closed surfaces (held)

No code changes · no distributed runtime · no consensus protocol · no live network · no autonomous
agent governance · no claim that federation is ready or authorized.

## Anti-drift

- Do NOT open active-active effect serving or any consensus/leader-election/CRDT work as "next" —
  all are deferred non-goals (Q8).
- The effect plane is single-owner-per-key-space until the CAS slice exists; replicating effects is
  the one thing that breaks exactly-one.
- This packet is the boundary map; even the recommended P2 is **replication-plane only** and
  human-gated to open.

## Governance

Packet in `igniter-lab/lab-docs/lang/`. Card in `igniter-lab/.agents/work/cards/lang/`. No gov
portfolio entry — readiness map, not a gate decision (smallest-artifact axiom).
