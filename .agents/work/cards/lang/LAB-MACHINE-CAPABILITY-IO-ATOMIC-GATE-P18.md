# Card: LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18 — exactly-one-effect under concurrency

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> meta focus [`…-PRODUCTION-HARDENING-P17`](LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17.md) (blocker #1).

**Status: CLOSED 2026-06-16 — the concurrency gap in the idempotency gate is closed.** 4 machine
tests (`tests/capability_io_atomic_tests.rs`) + 1 bridge-path concurrency test
(`tests/capability_io_bridge_tests.rs`); default suite green (224). Design doc:
`lab-docs/lang/lab-machine-capability-io-atomic-gate-p18-v0.md`.

## The gap (and why it mattered most)

The receipt protocol guaranteed exactly-one-effect for SEQUENTIAL duplicates. Under CONCURRENCY
the `lookup → prepare → execute` critical section was not atomic per key:

```text
parallel A/B, same idempotency key:
  both read "no receipt" → both prepare → both execute → DOUBLE EFFECT
```

This silently broke the central invariant under load — the top production blocker.

## Fix

`single_flight.rs`: `SingleFlight` (per-key async lock registry) + `run_write_effect_atomic(sf,
…)` — wraps the ENTIRE `run_write_effect` in a per-key lock keyed by `capability:idempotency_key`.
Concurrent same-key requests serialize: the first performs the effect, the rest replay its
receipt. Different keys never contend. The bridge (`bridge_effect::ServiceEffectBridge`) now holds
a `&SingleFlight` and uses the atomic path.

In-process scope (single-process machine). Multi-process → distributed lock / backend CAS is a
later slice. Lock map is unbounded (one entry per key seen) — a production impl evicts idle locks.

## Proof

| acceptance | test |
|---|---|
| two concurrent same-key requests → effect ONCE (attempts=1, max-in-flight=1, serialized) | `concurrent_same_key_performs_one_effect` |
| different keys still run in PARALLEL (max-in-flight=2 → per-key, not global, lock) | `concurrent_different_keys_run_in_parallel` |
| same key + different payload → one commits, the other refused | `concurrent_same_key_different_payload_one_wins` |
| a dangling `prepared` (crash) stays recoverable (unknown, no blind re-exec) | `dangling_prepared_stays_recoverable` |
| bridge path: two concurrent same-key webhooks → effect ONCE | `concurrent_same_webhook_performs_effect_once` |

Probe executor yields mid-flight so concurrent calls genuinely overlap; `max_in_flight` makes
serialization observable (=1 for same key, =2 for different keys).

## Closed

In-process single-flight only (no distributed lock / backend CAS). No durability change (blocker
#2). No language change. No live network.

## Next (P17 order)

#2 durable receipt/queue store + crash-recovery sweep → #3 host-driven orchestrator → #4 real
auth/secrets → #5 observability → #6 load test → (#7 human-gated live).
