# lab-machine-federation-readiness-p1-v0 — one machine → a federation: what breaks, what must hold

**Card:** `LAB-MACHINE-FEDERATION-READINESS-P1`
**Lane:** readiness / architecture / future-network
**Status:** READINESS / DESIGN ONLY — no code, no distributed runtime, no consensus, no live network.
This identifies the boundary, the invariants, and the **minimal safe v0** before any multi-machine
work. **Federation is NOT authorized for implementation by this card.**

Grounded in live single-machine surfaces: `coordination.rs` (pools / ACL / audit / messenger /
transfer / ServiceRecipe / ingress / dedup / replica fanout), `single_flight.rs`
(`run_write_effect_atomic`), `recovery.rs`, `orchestrator.rs`, `capability.rs` (signed passport),
`secrets.rs`, `bridge_effect.rs`, and the operational shape in
[`lab-machine-deployment-topology-p1-v0`](lab-machine-deployment-topology-p1-v0.md).

---

## The one idea that organizes everything: TWO planes

A federation is safe exactly when you split the system into two planes and federate them
**differently**:

```
REPLICATION plane   immutable + content-addressed + append-only        → safe to mirror freely
  capsule bytes (by digest), receipts (as facts), pool metadata,         (no coordination needed:
  transfer envelopes, messages                                            same digest ⇒ same bytes;
                                                                          append-only ⇒ union-mergeable)

EFFECT plane        the live, mutating, exactly-once execution          → must NOT be replicated;
  run_write_effect_atomic, the SingleFlight gate, secret resolution       it is OWNED by exactly
                                                                          one machine per key-space
```

> **The hard line:** `exactly-one-effect` is enforced today by an **in-process** per-key
> `SingleFlight` lock over **one** RocksDB (P18). That lock does not span machines. Therefore the
> effect plane cannot go active-active across machines without a distributed gate — and that gate
> is **explicitly deferred** (Q8). Everything safe about federation lives in the replication plane;
> everything dangerous lives in the effect plane. Keep them apart.

This is the deployment-topology P1 constraint generalized: *"one effect-process per RocksDB;
partition by capability/tenant if more processes are needed (each its own RocksDB + key space)."*

---

## Q1 — What can be shared across machines

All of these are replication-plane (immutable / content-addressed / append-only) and federate by
**copy or pull**, with no agreement protocol:

| shareable | how it federates safely | conflict risk |
|---|---|---|
| **capsule bytes by content digest** | pull by `content_digest`; **verify digest on arrival** (tamper-evident, no trust in the byte transport). Dedup by digest — N pools/machines, one image. | **none** — same digest ⇒ same bytes by construction (P2 content-addressed `CapsuleRef`). |
| **receipts** | mirror as **read-only audit/provenance facts** (bitemporal). | none for *audit*; but a mirrored receipt does **NOT** confer idempotency authority to execute that key elsewhere — see Q3. |
| **pool metadata** | replicate refs / ACL / visibility as facts; remote copy is a **read mirror** unless ownership is transferred by envelope. | low — metadata is owned by one machine; remote is a follower. |
| **transfer envelopes** | the **designed federation seam** (coordination-meta P6): signed envelope export → verify → import. Two-phase, idempotent, declared-rights (P4). | none if idempotent + signed (re-delivery = same digest = no-op). |
| **messages** | append-only audited facts; **federate by receipt/fact exchange** (gossip), per-thread **causal** order via causation refs — not global order. | none — append-only union; late facts handled by bitemporal valid-time. |

The unifying property: each shareable is **either content-addressed (identity = hash) or
append-only (history = union)**. Neither needs consensus to merge.

---

## Q2 — What must remain locally authoritative

These are the trust/effect roots; they do **not** replicate — they are **trusted across a boundary,
explicitly and pairwise**, or not at all:

| local authority | why it cannot be merged | cross-machine story |
|---|---|---|
| **developer root-of-trust** (`DeveloperConductor`) | each machine's conductor is its own issuer/approver (coordination-meta locked decision #3). | NOT merged. Machine B trusts A's issued artifacts only by **trusting A's issuer public key** — an explicit, audited local act. |
| **signed-passport issuer** (`PassportVerifier.trusted_keys`, P21) | a passport signed by A is authentic on B **iff B trusts A's key**. No global identity. | exchange + explicitly trust issuer keys (today: local blake3 MAC → asymmetric is the deferred slice). Trust is a local allowlist, never inferred. |
| **secret provider** (`secrets.rs`, P22) | secrets must never leave the machine that holds them. | a `{{secret:name}}` **reference** may travel inside a capsule/recipe, but **resolution is local** to the executing machine's `SecretProvider`. Secrets are **never** replicated, never in a fact. |
| **live effect execution** (`run_write_effect_atomic`) | the exactly-one gate is in-process (P18). | stays on **exactly one** machine per key-space. This is the invariant the whole packet protects. |

---

## Q3 — How idempotency works across machines (the heart)

Single-machine: `lookup → prepare → execute` is atomic per key because the `SingleFlight` lock and
the receipt store share one process + one RocksDB (P18/P19). Across machines that atomicity does not
extend. The options, ranked by safety:

1. **Single writer per key-space — RECOMMENDED v0.** Partition effect authority by
   capability/tenant/key-hash so **exactly one machine owns each key-space**. Route an effect to its
   owner; a non-owner **refuses** (fail-closed). No two machines ever hold the same key → the
   in-process `SingleFlight` is *sufficient* unchanged. **Zero consensus, exactly-one preserved.**
2. **Route by hash** — the *mechanism* for (1): deterministic `hash(idempotency_key) → owner
   machine` (consistent hashing later for rebalancing). Stateless, deterministic, no shared state.
3. **Shared receipt store + backend CAS** — if (and only if) active-active on one key-space is ever
   required: a compare-and-set on the `prepared` write makes prepare atomic across machines (the
   distributed-gate slice noted in P18 + topology §9). Stronger, but adds a shared dependency + CAS
   latency. Still **not** consensus. **Deferred (Q8).**
4. **Conflict detection (safety net, not primary)** — receipts are identity-keyed; if two machines
   ever emit receipts for the **same** idempotency key (an ownership/routing bug), the mirrored logs
   collide on that key → **flag + reconcile, never silently merge**. Detection backstops (1).

> **v0 = (1)+(2): single-writer-per-key-space by deterministic routing.** Active-active on the same
> key (3) is out of scope until the CAS slice exists. Never run the same key on two machines without
> (3).

---

## Q4 — How capsule transfers cross a machine boundary

Reuse the P4 two-phase `TransferEnvelope` (`proposed → accepted/rejected/revoked`, idempotent,
declared-rights) and add only what a boundary needs:

1. **Sign** the envelope with the source machine's issuer key.
2. **Verify** the signature on the target against its trusted keys **before** import (refuse-before-
   import, mirrors the capability-IO refuse-before-execute discipline).
3. **Pull capsule bytes by `content_digest`** and **verify the digest on arrival** — tamper-evident;
   the byte transport need not be trusted.
4. **Idempotent import** — re-delivery = same digest = no-op (P4 `duplicate_accept_idempotent`
   already holds; the source capsule stays immutable, accept ADDS a ref, no byte copy).
5. **`rights_granted` apply to the TARGET pool** under the target's ACL — the source cannot grant
   authority it doesn't hold on the target.
6. **`recipe_digest` travels but serving authority is minted LOCALLY** — the target's developer
   (root-of-trust) signs a production `ServiceRecipe` on the target machine. Root-of-trust does
   **not** transfer; only the immutable candidate image does.

This is exactly the coordination-meta P6 seam: *"machine A exports signed transfer envelope; machine
B imports after verification."*

---

## Q5 — How messenger/federation avoids becoming consensus too early

The whole design is arranged so that **agreement is never required**:

- everything shareable is **immutable + content-addressed** (Q1) → merge = union/dedup, not a vote;
- transfers are **two-phase + idempotent** → re-delivery is safe, no quorum;
- effect authority is **partitioned to one owner** (Q3) → no machine ever needs to agree with another
  on "who executed", because only one machine *can*;
- message threads use **per-thread causal order** (causation refs), not a global total order.

Consensus is only forced when **multiple machines must agree on a single mutable value that has no
natural owner**. v0 deliberately never creates that shape: every value is either immutable (no
agreement) or owned by exactly one machine (owner decides). Where a genuine conflict still appears
(e.g. two ownership claims), the resolver is the **developer/human conductor** (audited
arbitration), not an automated protocol. Automation of that decision is the consensus slice —
deferred.

---

## Q6 — Minimal safe v0

Ranked least→most dangerous: **read-only mirror < capsule sync < active-active serving.**

> **v0 = a read-only MIRROR + signed capsule SYNC. Effects stay single-owner. No active-active.**

Concretely, v0 lets machine B:

- **pull capsule bytes by digest** from A (verify digest), and **import via signed transfer
  envelope** (Q4);
- **mirror receipts / messages / pool metadata** as read-only bitemporal facts (audit + provenance
  federation, DR/backup mirror);
- **serve** from synced capsules — but **every effect for a key-space routes to that key-space's
  single owner** (Q3). B executes effects only for the key-spaces B owns.

What v0 explicitly is **not**: active-active execution of the same key-space (needs the CAS slice),
automatic failover of effect ownership (needs leader election — deferred), and any open/public mesh.

v0 delivers real value — capsule distribution, audit/provenance federation, DR mirror, dev→prod
handoff across machines — with **zero consensus** and the **exactly-one invariant intact**, because
it touches only the replication plane plus owner-partitioned serving.

---

## Q7 — Failure modes

| failure mode | cause | mitigation / status |
|---|---|---|
| **split brain** | two machines both believe they own a key-space (partition) | ownership is a **single-assignment** fact; the non-owner **fails closed** (refuses effects), never auto-takes-over. No automatic failover without the CAS slice + a gate. Single-owner = accepted SPOF at this stage (topology §9). |
| **duplicate effect** (cardinal sin) | split brain, routing bug, or active-active without CAS | **prevented** by single-writer partition (Q3-1/2); **detected** by cross-log receipt-key collision (Q3-4). Never allow the same key on two machines without (Q3-3). |
| **stale passport** | A revokes a passport; B still trusts the cached key/passport | `revoked` is **runtime host state**, not in the signature (P21). Mitigations: short `expires_at` windows; B checks its **own** revocation list; **cross-machine revocation propagation is a known gap** → deferred (needs a revocation feed). |
| **divergent receipt logs** | partition causes temporary mirror divergence | receipts are append-only + identity-keyed → merge = **union**; bitemporal valid-time vs transaction-time absorbs late-arriving facts. A *true* conflict (same key, different outcome) is **impossible under single-writer** → if seen, it is a **detected anomaly**, flagged, never auto-merged. |
| **clock skew** | machines' wall clocks differ; receipts carry host `transaction_time` | idempotency is **identity-keyed, not time-keyed** → skew does **not** corrupt exactly-one (same property as topology §7). Mitigations: NTP; treat cross-machine ordering as **causal** (happens-before), never gate correctness on cross-machine time comparison. |

---

## Q8 — What must be explicitly deferred (non-goals)

| deferred | why it is NOT v0 |
|---|---|
| **quorum / consensus** (Raft/Paxos) | only needed for active-active on a single key-space; v0 partitions ownership instead. |
| **leader election** | implies **automatic failover** of effect authority → reintroduces double-effect risk; v0 reassigns ownership only by explicit (human/gated) action. |
| **CRDT** | implies mergeable **mutable shared** state; v0 deliberately has none (immutable + single-owner instead), so CRDTs solve a problem v0 doesn't create. |
| **public mesh** | v0 is **explicit pairwise trust** (exchanged issuer keys), not open membership. |
| **autonomous agent voting / governance** | messages may carry a `vote` kind, but **no automated decision authority** — developer/human arbitration only. |
| **distributed-lock / backend-CAS prepare gate** | the single slice that would unblock active-active effects; deferred until horizontal effect scale is *actually* needed (P18 / topology §9 already name it). |

---

## Required authority boundaries (summary)

1. **Effect authority is partitioned, never replicated** — exactly one machine per key-space.
2. **Trust is local and explicit** — issuer keys are trusted by an audited local act, never inferred;
   no global identity.
3. **Secrets never leave their machine** — references travel; resolution is local.
4. **Capsule transfer is signed + digest-verified + idempotent** — refuse-before-import.
5. **Conflicts resolve by human/developer arbitration**, audited — not by an automated protocol.

## Closed surfaces (held by this readiness card)

No code · no distributed runtime · no consensus protocol · no live network · no autonomous agent
governance · **no claim that federation is ready or authorized.** This is the boundary map only.

## Recommendation (next card — low-risk v0 exists)

A **low-risk v0 is available** and worth a bounded, human-gated spike card (NOT opened by this card):

> **`LAB-MACHINE-FEDERATION-CAPSULE-SYNC-P2`** (recommended, **replication-plane only**) — prove
> signed capsule export → verify → digest-pull → idempotent import between **two in-process machine
> instances** (no network, no sockets), plus read-only receipt/message mirroring. **NO effect crosses
> a boundary; NO active-active; effect ownership stays single-writer.** Low-risk because it touches
> only the immutable, content-addressed, append-only plane — the part that needs no consensus.

The CAS/distributed-gate slice (which would unblock active-active effects) is **separately gated**
and should not be opened until a real horizontal-effect-scale need exists.

---

## Optional future route table

| step | scope | unlocks | risk | gate |
|---|---|---|---|---|
| **P1 (this)** | readiness / boundary map | shared understanding | none | — |
| **P2** `…-CAPSULE-SYNC` | signed export/verify/digest-pull/idempotent import + read-only mirror, two in-process instances | capsule distribution, audit/DR mirror, cross-machine dev→prod handoff | low (replication plane only) | recommended, human-gated to open |
| **P3** ownership routing | deterministic `hash(key)→owner`, non-owner fail-closed | multi-machine serving with single-writer-per-key-space | low–med | after P2 |
| **P4** revocation feed | cross-machine passport revocation propagation | closes the stale-passport gap | med (security) | after P3 |
| **(later)** CAS prepare gate | backend compare-and-set on `prepared` | active-active effects on one key-space | high | separate, needs real scale need + review |
| **(deferred)** consensus / leader election / CRDT / public mesh / agent voting | — | — | — | non-goals; do not open without an explicit new mandate |

## References (evidence only — not authority)

- Coordination seam: [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](../../.agents/work/cards/lang/LAB-MACHINE-AGENT-COORDINATION-META-P1.md)
  (P6 federation spike) · transfer [`LAB-MACHINE-AGENT-TRANSFER-P4`](../../.agents/work/cards/lang/LAB-MACHINE-AGENT-TRANSFER-P4.md)
  · pools/ACL [`LAB-MACHINE-AGENT-POOLS-P2`](../../.agents/work/cards/lang/LAB-MACHINE-AGENT-POOLS-P2.md)
- Effect invariant + the in-process constraint: [`…-ATOMIC-GATE-P18`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18.md)
  · [`…-DURABLE-RECOVERY-P19`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19.md)
- Operational shape (the one-process-per-RocksDB constraint): [`lab-machine-deployment-topology-p1-v0`](lab-machine-deployment-topology-p1-v0.md)
- Security roots: [`…-SIGNED-PASSPORT-P21`](lab-machine-capability-io-signed-passport-p21-v0.md) ·
  [`…-SECRET-PROVIDER-P22`](lab-machine-capability-io-secret-provider-p22-v0.md)
- Front door: [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](../../.agents/work/cards/lang/LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md)
