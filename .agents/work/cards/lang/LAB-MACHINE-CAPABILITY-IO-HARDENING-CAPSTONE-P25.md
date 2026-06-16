# Card: LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25 — hardening wave stop + live gate

> **Front door:** the capability-IO substrate is [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> the correctness-model stop is [`…-CAPSTONE-P15-CHECKPOINT`](LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT.md);
> the hardening audit/order is [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md).
> THIS card is the hardening wave-stop: in-lab production hardening is COMPLETE; live is gated.

**Status: CHECKPOINT — in-lab production hardening (P18–P24) COMPLETE and STOPPED here.**
2026-06-16. Default suite green (`cargo test --no-default-features`). Coordination artifact, not
an implementation card.

## One truth

```
Correctness model:           DONE (P1–P15, capstone checkpoint).
In-lab production hardening:  DONE (P18–P24, this checkpoint).
Live external runtime:        NOT DONE, NOT AUTHORIZED — human-gated only.
```

The hardening wave took the substrate from "correct on a single thread, happy path" to "holds the
central invariant under concurrency, crashes, retries, and load — observably." That is the
boring, load-bearing layer that makes the elegant model safe to run.

## What is CLOSED (P18–P24)

| # | blocker | card | what it proved |
|---|---|---|---|
| 1 | concurrency | `…-ATOMIC-GATE-P18` | per-key single-flight → exactly-one-effect under concurrent same-key duplicates; distinct keys parallel |
| 2 | crash recovery | `…-DURABLE-RECOVERY-P19` | durable receipts (RocksDB) + boot sweep reconciling dangling `prepared`; closes write-succeeded-but-receipt-failed; never re-executes |
| 3 | orchestration | `…-ORCHESTRATOR-P20` | host-driven boot/tick/report loop tying recovery + drain + dead-letter; no daemon; no silent stuck-unknown |
| 4 | security | `…-SIGNED-PASSPORT-P21` + `…-SECRET-PROVIDER-P22` | verifiable signed authority (no scope escalation) + allowlisted/traversal-safe secret sources (never in a fact) |
| 5 | observability | `…-OBSERVABILITY-P23` | metrics + dead-letter inbox as a pure projection FROM facts (no side-log, no daemon) |
| 6 | load | `…-LOAD-P24` | exactly-one held at 2000-way same-key storm; distinct 3000 no-dup; ~40–50k effects/s ≫ 2–5k rpm; no code tuning |

## DO NOT infer live readiness (the gate)

In-lab hardening done is NOT live readiness. The following do NOT exist and have NOT been
reviewed — an agent must NOT proceed past them as "the next step":

- no real SparkCRM (or any third-party) endpoint touched;
- no real vaulted credential — `SecretProvider` is env/file in the glass box;
- no deployment topology (process/replica/failover/backups/clock-source) designed;
- no public-ingress threat review (auth surface, rate/cost abuse, DoS, input validation at scale);
- no operational runbook (on-call, dead-letter triage, rollback);
- no human approval.

`P16-live` (or any live/staging smoke) is a **separate operational + security decision**, gated on
the above, NOT a continuation of this engineering wave.

## Next routes (the wave is intentionally stopped)

- **optional live-gate packet** — a single document gathering the deltas above for a human gate
  decision (NOT executed by an agent). **PREPARED: [`LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`](LAB-MACHINE-SPARKCRM-LIVE-GATE-P1.md)
  (2026-06-16)** — answers the 10 gate questions; still human-gated, NOT executed.
- **deployment topology design** — readiness card for the operational shape (still in-lab/design).
  **DONE: `LAB-MACHINE-DEPLOYMENT-TOPOLOGY-P1` (2026-06-16)** — process model / storage / boot
  order / ingress / pools / backup / clock-secrets-passport / operator commands / risks. Hard
  constraint surfaced: exactly-one is in-process → one effect-process per RocksDB.
- **switch track** — the substrate is done enough; other tracks (frame/GUI, coordination
  federation, language) may be the higher-value move.

## Post-capstone storage addendum (2026-06-16)

After this checkpoint, an audit of the **physical** fact store (the "durable backend (RocksDB)" the
P19 row above relies on) found it was a pure-Rust `.mpk` file store with non-atomic, non-fsync'd
writes that could **silently lose** receipts under a torn write — `LAB-MACHINE-ROCKSDB-DURABILITY-P2`.
That gap is now **narrowed by `LAB-MACHINE-FACTSTORE-DURABILITY-HARDENING-P3`**: atomic
temp→fsync→rename writes, observable+refused corruption, receipt spine on the hardened path, backend
renamed `MpkFileBackend`. **Still gated for live:** full cross-platform **power-loss** durability
(macOS `F_FULLFSYNC`, cloud-volume fsync honoring) — an operational property under this human-gate,
not an in-lab engineering gap.

## Anti-drift

- Do NOT open live/staging/SparkCRM smoke as the next card — it is human-gated.
- Read the milestone front door + this checkpoint before pulling any single P-slice out of context.
- Hardening is composition of the existing substrate — no new effect primitives were added.
- The persistent backend is `MpkFileBackend` (a `.mpk` file store), NOT RocksDB — don't reintroduce
  the misnomer; physical durability is P2 (audit) + P3 (fix).

## Governance

Portfolio: `igniter-gov/portfolio/governance/2026-06-16-lab-machine-capability-io-hardening-capstone-p25-v0.md`.
Live index: `igniter-machine/IMPLEMENTED_SURFACE.md`.
