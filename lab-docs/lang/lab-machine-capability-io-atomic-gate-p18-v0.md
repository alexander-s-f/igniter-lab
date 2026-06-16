# lab-machine-capability-io-atomic-gate-p18-v0 — exactly-one-effect under concurrency

**Card:** `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18` (production-hardening blocker #1, meta
`LAB-MACHINE-CAPABILITY-IO-PRODUCTION-HARDENING-P17`)
**Status:** CLOSED — the concurrency gap in the idempotency gate is closed. 4 + 1 machine tests;
default suite green (`cargo test --no-default-features`: 224).
**Boundary held:** in-process single-flight only; no durability change; no live network.

## The gap

Every receipt-protocol proof before P18 assumed serialized per-key access. The idempotency
guarantee was therefore **sequential-only**:

```text
sequential duplicate  → one effect   (PROVEN, P6)
parallel A/B same key → both read "no receipt" → both prepare → both execute → DOUBLE EFFECT
```

`run_write_effect`'s `lookup → prepare → execute` is three separate `await`s; nothing serialized
two concurrent calls on the same idempotency key. Under 2–5k rpm with retry storms (the exact
condition that produces duplicates), this silently breaks exactly-one-effect — the central
invariant. It was the #1 production blocker, ahead of any live concern.

## Fix — per-key single-flight

`igniter-machine/src/single_flight.rs`:
- `SingleFlight` — a registry of per-key async locks (`HashMap<key, Arc<tokio::Mutex<()>>>`),
  cheap to share via `&SingleFlight`.
- `run_write_effect_atomic(sf, registry, receipts, clock, passport, scope, req, mode)` — acquires
  the lock for `capability_id:idempotency_key` (the same key the receipt uses) and holds it across
  the ENTIRE `run_write_effect`. Concurrent same-key calls serialize; the first performs the
  effect, the rest replay its receipt. Different keys take different locks → no contention.

The bridge (`bridge_effect::ServiceEffectBridge`) gained a `&SingleFlight` and routes its effect
through `run_write_effect_atomic`, so the served-webhook path is atomic too.

Why hold the lock across `execute` (not just the prepare): a same-key duplicate should wait for
the in-flight effect to finish and then see its committed receipt — that is exactly the
exactly-one semantics. The throughput cost falls only on same-key duplicates (retry storms),
which is precisely where serialization is wanted; distinct keys are unaffected.

## Scope / limits (honest)

- **In-process single-process** machine. A multi-process / multi-replica deployment needs a
  distributed lock or a backend compare-and-set on the `prepared` write — a later slice. (The
  coordination homogeneous-pool model already keeps a single replica per effect via the serving
  side, but the effect substrate's own multi-process story is open.)
- **Lock map is unbounded** (one entry per key ever seen). A production impl evicts idle locks
  (e.g. weak refs / sharded LRU). Noted, not done.
- No durability change — that is blocker #2.

## Proof (5 tests)

| claim | test | file |
|---|---|---|
| concurrent same key → effect ONCE; serialized (max-in-flight=1) | `concurrent_same_key_performs_one_effect` | atomic |
| different keys run in PARALLEL (max-in-flight=2) — per-key, not global | `concurrent_different_keys_run_in_parallel` | atomic |
| same key + different payload → one commits, other refused | `concurrent_same_key_different_payload_one_wins` | atomic |
| dangling `prepared` (crash) stays recoverable (unknown, no blind re-exec) | `dangling_prepared_stays_recoverable` | atomic |
| bridge path: concurrent same-key webhooks → effect ONCE | `concurrent_same_webhook_performs_effect_once` | bridge |

The `ProbeExecutor`/`SlowEcho` yield mid-flight (8× `yield_now`) so concurrent calls genuinely
overlap on the single-thread runtime; `max_in_flight` makes serialization observable: **1** for
same-key (serialized), **2** for different keys (parallel — the lock did not over-serialize).

## Closed

In-process single-flight only. No distributed lock / backend CAS. No durability/crash-recovery
change (blocker #2). No language change. No live network.

## Next (P17 hardening order)

#2 durable receipt/queue store + crash-recovery sweep → #3 host-driven orchestrator → #4 real
authority verification + real SecretProvider → #5 observability + dead-letter → #6 load test →
(#7 human-gated live).
