# Card: LAB-MACHINE-SERVING-LOOP-CONCURRENCY-P13 — bounded concurrent serving loop

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: CLOSED (2026-06-17) — implemented + proven (297 machine tests green, +5).** See the
closing report at the bottom. Follow-on to `LAB-MACHINE-SERVING-LOOP-P12`. Non-live, loopback/local
only. This card must not open public ingress, external SparkCRM, deployment, credentials, or a daemon.

## Front door

Read first:

- `LAB-MACHINE-SERVING-LOOP-P12.md`
- `lab-docs/lang/lab-machine-serving-loop-p12-v0.md`
- `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18.md`
- `igniter-machine/IMPLEMENTED_SURFACE.md`

Verify live code before writing:

- `serving_loop::{ServingLoop, ServingPolicy, ServingReport}`
- `ingress::serve_once_effect`
- `single_flight::run_write_effect_atomic`
- existing `tests/serving_loop_tests.rs`
- P24 load proof, if needed, for same-key storm / distinct-key parallel expectations

## Goal

P12 intentionally proved the host shape with **sequential** processing. P13 proves the next server
property: bounded concurrent accept/serve while preserving the central invariant:

```text
same idempotency key  → at most one effect
distinct keys         → may run concurrently up to max_in_flight
host still owns loop  → no daemon, no hidden scheduler
```

This is still an in-lab host helper over loopback. It is not deployment topology and not public
ingress.

## Required decisions

1. **Bounded concurrency only.** Add an explicit `max_in_flight` / concurrency policy. No unbounded
   `spawn` per connection.
2. **Host-owned lifecycle.** The helper may use tasks internally for a bounded run, but when `run`
   returns, all child tasks must be joined/finished/cancelled. No background worker remains.
3. **Atomic gate remains the authority.** The loop must not invent request-level idempotency. Same
   key must still serialize through the existing P18 effect gate.
4. **Tick cadence remains explicit.** Do not run an independent retry scheduler in the background.
   Tick may happen before/after a bounded batch, or via existing P12 cadence rules, but it must be
   host-owned.
5. **Loopback only.** Tests bind `127.0.0.1`. No public address, no TLS ingress, no external host.

## Suggested shape

Agent may choose exact API after verify-first, but keep it additive:

```rust
pub struct ConcurrentServingPolicy {
    pub max_requests: usize,
    pub max_in_flight: usize,
    pub tick_on_stop: bool,
}

pub struct ConcurrentServingReport {
    pub booted: bool,
    pub requests_served: usize,
    pub max_in_flight_observed: usize,
    pub ticks_run: usize,
    pub retries_drained: usize,
}
```

Prefer adding a new method/helper rather than changing P12 sequential semantics:

```rust
ServingLoop::run_concurrent(...)
```

or a separate `ConcurrentServingLoop`, whichever keeps the diff smaller and clearer.

## Acceptance

- [x] Verify-first note confirms P12 is sequential and no bounded concurrent loop already exists.
- [x] Additive API: existing P12 tests still pass unchanged.
- [x] `max_in_flight` is enforced; no unbounded tasks.
- [x] Test proves N distinct-key requests are processed with observed concurrency > 1.
- [x] Test proves same-key concurrent requests still perform exactly one effect and produce one
      committed receipt.
- [x] Test proves distinct keys can execute in parallel while same-key remains serialized by the existing receipt-replay path.
- [x] Test proves deterministic shutdown: after `run_concurrent` returns, no acceptor/task remains.
- [x] Test proves host-owned tick can still drain due retry intents without a background scheduler.
- [x] Real loopback TCP + fake/local executor only.
- [x] No live network, no SparkCRM staging/prod, no credentials, no public bind address.
- [x] `IMPLEMENTED_SURFACE.md` and proof doc updated (public API added).

## Closed surfaces

- Do not change `serve_once_effect` semantics.
- Do not change duplicate policy, effect idempotency, or `single_flight`.
- Do not add public ingress/TLS exposure.
- Do not create a daemon, supervisor, systemd unit, Dockerfile, or deployment topology.
- Do not call real SparkCRM or any external host.
- Do not add Postgres work here; Postgres is on `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2`.

## Deliverables

- Minimal implementation + tests.
- `lab-docs/lang/lab-machine-serving-loop-concurrency-p13-v0.md`
- Closing report in this card.
- `IMPLEMENTED_SURFACE.md` update only if public API is added.

## Next routes

- Graceful long-running serving loop with cancellation token / signal handling.
- Host health/readiness endpoint over facts and orchestrator report.
- Public ingress threat model remains separate and human-gated.
- **Wire-path atomic gate (NEW, named here):** thread `single_flight::run_write_effect_atomic` into
  `ingress::handle_effect` so same-key exactly-one survives a *yielding* receipt backend (e.g. a real
  Postgres receipts store). Today the wire path uses non-atomic `run_write_effect`; the SingleFlight
  gate lives only in `ServiceEffectBridge`. Separate card — it changes `serve_once_effect` internals
  (a closed surface here).

---

## Closing report — CLOSED (2026-06-17)

**Outcome:** bounded concurrent serving proven, additively, over the proven wire-to-effect entrypoint,
via structured concurrency. The invariant holds: distinct keys served concurrently, same-key → one
effect, host owns the loop, no spawned/detached task.

**Verify-first (confirmed live, before writing):**
- P12 `ServingLoop::run` is sequential; no bounded concurrent loop existed.
- `serve_once_effect`→`handle_effect` performs the effect via `write::run_write_effect`
  (`ingress.rs:344`), **NOT** `single_flight::run_write_effect_atomic`. The P18 SingleFlight gate lives
  only in `bridge_effect::ServiceEffectBridge`; the P24 load proof drives the atomic gate directly,
  never through the wire path.
- **Empirical probe (40× · 8-way same-key · 4-worker multi-thread runtime via `FuturesUnordered`):**
  exactly one effect every time. Mechanism: `run_write_effect`'s read→prepare→execute→commit critical
  section runs without an internal yield over the synchronous in-memory receipt store
  (`InMemoryBackend` = `parking_lot::Mutex`), so the receipt-replay gate catches concurrent duplicates.
  Honest limit recorded: a *yielding* receipt backend would need the P18 gate in the wire path → named
  follow-on above. (Probe was a throwaway; not committed.)

**Added (additive — P12 `run`/`ServingPolicy`/`ServingReport` untouched):**
- `igniter-machine/src/serving_loop.rs` — `ConcurrentServingPolicy{max_requests,max_in_flight,
  tick_on_stop}`, `ConcurrentServingReport{booted,requests_served,max_in_flight_observed,ticks_run,
  retries_drained}`, `ServingLoop::run_concurrent`. Structured concurrency via `FuturesUnordered`
  (no `tokio::spawn`, nothing to leak); bounded by `max_in_flight`; host-owned tick.

**Tests:** `tests/serving_loop_concurrency_tests.rs` (5, multi-thread, real `127.0.0.1`, fake executor):
distinct-keys-parallel (observed == bound > 1) · same-key → exactly one effect + one receipt · mixed
batch (one effect per distinct key) · deterministic bounded shutdown (re-entrant, no leaked task) ·
host-owned tick drains a due retry. Stable over 10 consecutive runs.

**Verification:** `cargo test --no-default-features` → **297 passed / 0 failed** (+5 here; includes a
neighbouring Postgres slice's tests). P12's 4 tests pass **unchanged**.

**Acceptance:** all boxes met.
- ✅ Verify-first confirms P12 sequential + no concurrent loop (and the wire-path/atomic-gate truth).
- ✅ Additive API; P12 tests pass unchanged.
- ✅ `max_in_flight` enforced; no unbounded tasks (structured, no spawn).
- ✅ N distinct-key requests with observed concurrency > 1.
- ✅ Same-key concurrent → exactly one effect + one committed receipt.
- ✅ Distinct keys parallel while same-key serialized (mixed batch).
- ✅ Deterministic shutdown; no acceptor/task remains (re-entrant second run proves it).
- ✅ Host-owned tick drains due retries; no background scheduler.
- ✅ Real loopback TCP + fake executor only.
- ✅ No live network / SparkCRM / credentials / public bind.
- ✅ `IMPLEMENTED_SURFACE.md` + proof doc updated (public API added).

**Deliverables:** `src/serving_loop.rs` (additive), `tests/serving_loop_concurrency_tests.rs`,
`lab-docs/lang/lab-machine-serving-loop-concurrency-p13-v0.md`, `IMPLEMENTED_SURFACE.md` update.

**Boundary held:** `serve_once_effect` / duplicate policy / effect idempotency / `single_flight`
unchanged; no public ingress/TLS; no daemon/supervisor/systemd/Dockerfile/topology; no real SparkCRM.
Cooperative structured concurrency (one polling task), not OS-parallel — sufficient for the in-lab
invariants; OS-parallel wire-path safety with a yielding backend is the named follow-on. No Postgres
work here (that is the neighbour's `LAB-MACHINE-POSTGRES-READ-EXECUTOR-P2`).
