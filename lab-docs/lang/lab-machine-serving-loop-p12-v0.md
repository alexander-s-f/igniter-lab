# LAB-MACHINE-SERVING-LOOP-P12: host-owned serving loop over wire-to-effect

**Status:** CLOSED — implementation proof.  
**Scope:** local/loopback only; no daemon, no public ingress, no live SparkCRM, no credentials.

## What was missing

`ingress::serve_once_effect` already proved the wire-to-effect contour one connection at a time:

```text
real HTTP POST
  → parser
  → passport
  → duplicate policy
  → one replica
  → capsule intent
  → one effect + receipt
  → HTTP response
```

P12 adds the smallest host shell around that entrypoint so the machine can be described as a process
without inventing a daemon:

```text
boot recovery once
  → serve exactly N loopback connections through serve_once_effect
  → optionally tick retry queue on a host-owned cadence
  → return a derived report
```

## Implementation

`igniter-machine/src/serving_loop.rs` exposes:

- `ServingPolicy { max_requests, tick_every, tick_on_stop }`
- `ServingReport { booted, requests_served, ticks_run, retries_drained }`
- `ServingLoop { listener, router, hub, cfg }`
- `ServingLoop::run(&EffectOrchestrator, &ServingPolicy)`

The loop composes existing surfaces only:

- `EffectOrchestrator::boot()` before serving;
- repeated `ingress::serve_once_effect(...)`;
- optional `EffectOrchestrator::tick()` after every N requests or on stop.

It does **not** spawn, does **not** own a background worker, does **not** install a scheduler, and
does **not** open a socket address itself. The caller passes the listener, so this proof stays
loopback/local.

## Invariants held

- **Host owns cadence.** The machine exposes functions; the host decides when to run them.
- **Bounded stop.** `max_requests` is the deterministic stop condition; no unbounded loop in this
  slice.
- **No new effect semantics.** Effects still go through the P10/P11 bridge and P18 atomic gate.
- **Sequential serving in v0.** This proof introduces no request concurrency. Same-key duplicates
  therefore cannot bypass the existing idempotency path.
- **Facts remain truth.** `ServingReport` is a derived counter for the host/operator, not a side-log.
  `observe()` and `EffectOrchestrator::report()` remain the authoritative view.

## Tests

`igniter-machine/tests/serving_loop_tests.rs`:

1. `loop_serves_two_requests` — one loop instance boots once, serves two real loopback HTTP requests,
   and `observe()` projects two committed effects from receipts.
2. `loop_dedup_same_key_one_effect` — two same-key requests over the loop produce exactly one effect.
3. `loop_tick_drains_due_retry` — a due retry intent is drained by `tick_on_stop`; served effect +
   retried effect both reach the fake executor.
4. `loop_deterministic_shutdown_no_leak` — a bounded run stops after exactly one request and the same
   listener/loop can be used again; the system remains queryable.

The closing card reports `cargo test --no-default-features` → 283 passed at implementation time.

## Boundary

This is **not** deployment topology:

- no daemon/supervisor/systemd/Dockerfile;
- no public bind address;
- no public ingress threat review;
- no TLS ingress;
- no live SparkCRM or external network;
- no credentials;
- no HA/multi-process design.

Those remain separate operational cards/gates.

## Next routes

- Public serving packaging or deployment topology implementation — separate.
- Public ingress threat model — separate and human-gated.
- SparkCRM live/staging smoke remains behind `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`.
