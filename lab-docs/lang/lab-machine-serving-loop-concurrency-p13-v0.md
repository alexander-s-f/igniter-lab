# LAB-MACHINE-SERVING-LOOP-CONCURRENCY-P13: bounded concurrent serving loop

**Status:** CLOSED — implementation proof.
**Scope:** local/loopback only; no daemon, no public ingress, no live SparkCRM, no credentials.
**Follow-on to** `LAB-MACHINE-SERVING-LOOP-P12` (which proved the host shape *sequentially*).

## What was missing

P12's `ServingLoop::run` serves one connection at a time. P13 proves the next server property —
**bounded concurrent** accept/serve — without weakening the central invariant:

```text
same idempotency key  → at most one effect
distinct keys         → may run concurrently up to max_in_flight
host still owns loop  → no daemon, no spawned/detached task, no hidden scheduler
```

## Verify-first (live code, before writing)

- `serving_loop::{ServingLoop, ServingPolicy, ServingReport}` — P12, **sequential** (`run` awaits each
  `serve_once_effect` before the next). No concurrent loop existed.
- `ingress::serve_once_effect` — serves exactly one connection through the P11 wire-to-effect contour.
- **The wire path does NOT use the P18 atomic gate.** `handle_effect` (what `serve_once_effect` calls)
  performs the effect via `write::run_write_effect` (`ingress.rs:344`), **not**
  `single_flight::run_write_effect_atomic`. The SingleFlight gate is used only by
  `bridge_effect::ServiceEffectBridge`, a separate entry. The P24 load proof drives
  `run_write_effect_atomic` directly on a multi-thread runtime — it never goes through
  `serve_once_effect`.
- **Empirical probe (recorded before designing):** 8 concurrent same-vendor-key requests driven
  through `serve_once_effect` (via `FuturesUnordered`), repeated 40× on a 4-worker multi-thread
  runtime → **exactly one effect every time**. So the wire path *does* collapse same-key concurrency
  to one effect — see the mechanism below.

### Why same-key collapses to one effect on the wire path (precise mechanism)

It is **not** the SingleFlight lock (the wire path doesn't use it). It is the
read→prepare→execute→commit receipt critical section in `run_write_effect` running **without an
internal yield point** over the in-memory receipt store (`InMemoryBackend` = a synchronous
`parking_lot::Mutex`). The only `Pending` awaits in the wire path are network IO (accept/read/write);
once a connection enters `handle_effect`, the dedup-decision + effect run to completion before another
in-flight future is polled, so the first writes the committed receipt and the rest replay it.

**Honest limit (named, not papered over):** this guarantee holds for the in-lab loopback + in-memory
receipt store. A *yielding* receipt backend (e.g. a real Postgres receipts store that suspends
mid-protocol) could let two same-key effects interleave on the wire path — exactly the gap
`single_flight::run_write_effect_atomic` (P18) closes. That gate currently sits in
`ServiceEffectBridge`, **not** in `serve_once_effect`. Threading it into the wire path is a named
follow-on (below), not this card — this card must not change `serve_once_effect` semantics.

## Implementation

`igniter-machine/src/serving_loop.rs` — **additive** (P12 `run`/`ServingPolicy`/`ServingReport`
untouched):

- `ConcurrentServingPolicy { max_requests, max_in_flight, tick_on_stop }` (+ `new`, `tick_on_stop`).
- `ConcurrentServingReport { booted, requests_served, max_in_flight_observed, ticks_run, retries_drained }`.
- `ServingLoop::run_concurrent(&EffectOrchestrator, &ConcurrentServingPolicy)`.

```text
boot recovery once
  → drive a FuturesUnordered of serve_once_effect calls, topped up to max_in_flight
  → record peak in-flight as max_in_flight_observed
  → stop when max_requests connections are served (bounded)
  → optional host-owned tick on stop
  → return a derived report
```

### Concurrency model — structured, not spawned

The in-flight `serve_once_effect` calls live in a `futures::stream::FuturesUnordered` polled by the
**same task** that called `run_concurrent`. There is **no `tokio::spawn`**, no detached task, and so
nothing that can outlive the call. When `run_concurrent` returns, the set is dropped; any
still-pending future is cancelled (in practice the loop awaits them all first). This is a strictly
stronger "no leaked worker" property than join-on-shutdown: there is no worker to leak. Concurrency is
real — multiple connections are in flight at once, interleaving at every accept/read/write/effect
await — and strictly bounded by `max_in_flight`.

## Invariants held

- **Bounded concurrency.** `max_in_flight` (clamped ≥ 1) caps in-flight calls; never an unbounded
  fan-out. `max_in_flight_observed` reports the peak actually reached.
- **Host owns the loop.** Cadence and stop are the host's; the machine still only exposes functions.
- **No new idempotency.** The loop invents no request-level dedup; each connection runs the unchanged
  `serve_once_effect`. Same-key collapse comes entirely from the existing duplicate-policy +
  receipt-replay path.
- **Tick stays explicit.** `tick_on_stop` runs one host-owned `EffectOrchestrator::tick`; no
  background retry scheduler.
- **Facts remain truth.** The report is a derived counter; `observe()` / `EffectOrchestrator::report()`
  remain the authoritative view.

## Tests

`igniter-machine/tests/serving_loop_concurrency_tests.rs` (multi-thread runtime, real `127.0.0.1`,
fake executor):

1. `concurrent_distinct_keys_run_in_parallel` — 6 distinct keys, `max_in_flight=4` → served 6,
   `max_in_flight_observed == 4` (> 1, and == the bound), 6 effects, 6 committed receipts.
2. `concurrent_same_key_exactly_one_effect` — 6 same-key concurrent → exactly one effect, one
   committed receipt, all 6 responses 200.
3. `concurrent_distinct_parallel_same_key_serialized` — mixed `[A,A,B,B,C,C]` in one batch → 3 effects
   (one per distinct key; duplicates serialized away), `max_in_flight_observed == 6`.
4. `concurrent_deterministic_shutdown_no_leak` — a bounded run stops after exactly its budget; a second
   run on the same instance proceeds normally (re-entrant, nothing lingering); system stays queryable.
5. `concurrent_tick_drains_due_retry` — a due retry intent is drained by `tick_on_stop` while the loop
   stays host-owned; served effects + retried effect all reach the executor.

P12's `serving_loop_tests.rs` (4) pass **unchanged** (additive API). Concurrency tests verified stable
over 10 consecutive runs. Full machine suite: `cargo test --no-default-features` → **297 passed / 0
failed** at implementation time (includes a neighbouring Postgres slice's tests).

## Boundary

This is **not** deployment topology and **not** public ingress:

- no daemon/supervisor/systemd/Dockerfile, no public bind address, no TLS ingress;
- no live SparkCRM/external network, no credentials;
- `serve_once_effect`, the duplicate policy, effect idempotency, and `single_flight` are unchanged;
- cooperative structured concurrency (one polling task), not OS-parallel request handling — sufficient
  for the in-lab invariants here; OS-parallel wire-path safety with a yielding backend is the named
  follow-on.

## Next routes

- **Wire-path atomic gate:** thread `single_flight::run_write_effect_atomic` into `handle_effect` so
  same-key exactly-one survives a *yielding* receipt backend (the in-memory guarantee proven here would
  then hold for, e.g., a Postgres receipts store). Separate card — changes `serve_once_effect`'s
  internals.
- Graceful long-running serving loop with a cancellation token / signal handling.
- Host health/readiness endpoint over facts + orchestrator report.
- Public ingress threat model — separate, human-gated.
