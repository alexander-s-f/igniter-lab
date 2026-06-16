# Card: LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17 — meta focus / gap audit

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md)
> (the P1–P15 substrate) + [`…-CAPSTONE-P15-CHECKPOINT`](LAB-MACHINE-CAPABILITY-IO-CAPSTONE-P15-CHECKPOINT.md).

**Status: META FOCUS — gap audit. ALL IN-LAB BLOCKERS #1–#6 CLOSED (P18–P24); wave stopped at the
hardening capstone [`…-HARDENING-CAPSTONE-P25`](LAB-MACHINE-CAPABILITY-IO-HARDENING-CAPSTONE-P25.md).
Only #7 human-gated live remains.** Not an implementation card. Coordinated the hardening blockers
between the proven correctness model (P1–P15 + bridge) and a real production runtime. **Authority:
no live external network, no SparkCRM staging, no real credentials — every blocker was provable in
the glass box.**

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
   boot recovery (P19) + drain (P9) + dead-letter, explicit loop, no hidden worker. **→
   `LAB-MACHINE-CAPABILITY-IO-ORCHESTRATOR-P20` (CLOSED 2026-06-16, 6 tests).**
4. **Real authority + secrets** (security, MED) — split in two:
   - 4a signed passport — verify the `evidence_digest` signature. **→
     `LAB-MACHINE-CAPABILITY-IO-SIGNED-PASSPORT-P21` (CLOSED 2026-06-16, 5 tests).**
   - 4b real `SecretProvider` (env/file/vault, not the in-process map). **→
     `LAB-MACHINE-CAPABILITY-IO-SECRET-PROVIDER-P22` (CLOSED 2026-06-16, 5 tests).**
   **Blocker #4 (security) CLOSED.**
5. **Observability** (operational, MED) — metrics + dead-letter inbox projected from facts. **→
   `LAB-MACHINE-CAPABILITY-IO-OBSERVABILITY-P23` (CLOSED 2026-06-16, 6 tests).**
6. **Load test 2–5k rpm** (operational) — exercise the gate + durability under the real target
   throughput. **→ `LAB-MACHINE-CAPABILITY-IO-LOAD-P24` (CLOSED 2026-06-16, 3 tests; exactly-one
   held at 2000-way concurrency; ~40–50k effects/s ≫ target).**

**ALL IN-LAB HARDENING (#1–#6) CLOSED.** Only the human-gated step remains:

7. **`P16-live`** — allowlisted staging/prod HTTPS smoke. Real endpoint + vaulted credential +
   explicit human authorization. NOT a continuation of this wave.

## Anti-drift

- Do NOT enter live/staging/SparkCRM smoke before #1–#2 (atomic gate + durable recovery).
- Each blocker is its own bounded card; #1 is the only one started (P18, closed).
- The correctness model is done — these are runtime-hardening, not new primitives.

## Authority

No live network, no real credentials, no SparkCRM staging. All blockers proven in the glass box.
Governance: portfolio capstone `2026-06-16-lab-machine-capability-io-capstone-p15-v0.md`.
