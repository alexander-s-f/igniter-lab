# Card: LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17 — meta focus / gap audit

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md)
> (the P1–P15 substrate) + [`…-CAPSTONE-P15-CHECKPOINT`](LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT.md).

**Status: META FOCUS — production-readiness gap audit.** Not an implementation card. Coordinates
the hardening blockers between the proven correctness model (P1–P15 + bridge) and a real
production runtime. **Authority: no live external network, no SparkCRM staging, no real
credentials — every blocker below is provable in the glass box.**

## The honest state

```
Correctness model:    YES (P1–P15 substrate + service↔effect bridge, all local/fake proven)
Production readiness:  NOT YET
Next blocker:          atomic idempotency gate under concurrency
```

The whole protocol guarantees exactly-one-effect for **sequential** duplicates (a replay reads
the prior receipt). It did NOT guarantee it under **concurrency**: two parallel same-key requests
could both read "no receipt", both prepare, both execute → double effect. That breaks the central
invariant more dangerously than the absence of a live SparkCRM smoke. **Do not enter staging
until the atomic gate is in.**

## Hardening blockers — IN ORDER

1. **Atomic idempotency gate** (technical, HIGH) — per-key single-flight / CAS-prepare so
   `lookup→prepare→execute` is atomic per key. **→ `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18`
   (CLOSED 2026-06-16).**
2. **Durable receipt/queue store + crash-recovery** (technical, HIGH) — receipts/retry-queue/dedup
   on a durable backend (RocksDB); restart-recovery sweep (dangling `prepared` → reconcile on
   boot); close the write-succeeded-but-receipt-failed window. **→
   `LAB-MACHINE-CAPABILITY-IO-DURABLE-RECOVERY-P19` (CLOSED 2026-06-16, 7 tests).**
3. **Host-driven orchestrator + tick** (engineering, MED) — drive the existing pieces:
   `unknown → reconcile (P7/P13) → commit | re-issue (P9) | compensate (P12)`. A real
   drain/tick loop (still explicit, no hidden worker) + durable queue across restarts.
4. **Real authority verification** (security, MED) — verify a signed passport / token; today
   `evidence_digest` is opaque (NOT verified). Plus a real `SecretProvider` (vault/env), not the
   in-process map.
5. **Observability** (operational, MED) — metrics/tracing on top of the audit facts; a
   dead-letter path for `blocked`/`exhausted` intents (a stuck `unknown` must be escalable).
6. **Load test 2–5k rpm** (operational) — exercise the gate + durability under the real target
   throughput (depends on #1, #2).

Then, and only then, the human-gated step:

7. **`P16-live`** — allowlisted staging/prod HTTPS smoke. Real endpoint + vaulted credential +
   explicit human authorization. NOT a continuation of this wave.

## Anti-drift

- Do NOT enter live/staging/SparkCRM smoke before #1–#2 (atomic gate + durable recovery).
- Each blocker is its own bounded card; #1 is the only one started (P18, closed).
- The correctness model is done — these are runtime-hardening, not new primitives.

## Authority

No live network, no real credentials, no SparkCRM staging. All blockers proven in the glass box.
Governance: portfolio capstone `2026-06-16-lab-machine-capability-io-capstone-p15-v0.md`.
