# Job Runner — Pressure Report

## What This Is

`job_runner` is a pure, Sidekiq-shaped **job dispatch + retry-budget** model, pulled
from `igniter-view-engine/fixtures/sidekiq_core`. A job request is dispatched to a
named job, then run through a bounded retry budget:

```
JobRequest ──► DispatchJob (static) ──► AttemptOutcome ──► RunWithRetry3 ──► JobOutcome ──► JobReceipt
 (class+args)   (by name, fail-closed)   (ok? budget?)      (bounded retry)   (sealed)        (audit)
```

No Redis, no worker daemon, no scheduler, no queue. Whether an attempt succeeds is
injected; a real runner re-dispatches a real effect.

## Why This App Exists

It exercises two things nothing else in the fleet did: a **job dispatch table** and a
**retry budget loop** — and it surfaces a crisp, fresh parity gap: the production
fixture's managed `loop … max_steps` (PROP-039 BudgetedLocalLoop) is **Rust-only**.

## Pressure 1 — managed loop is Rust-only (JR-P03, the fresh finding)

The fixture models retries as a managed local loop:

```igniter
loop RetryLoop outcome in outcomes max_steps: 5 {
  compute total_attempts = total_attempts + 1
}
```

Rust accepts this; the **Ruby TC rejects it** (`OOF-L7` — loop-body compute
reassignment). So it is **not dual-clean**, and a dual-clean app cannot use it. We
unroll three attempts by hand instead:

```igniter
o1 = AttemptOutcome(result, ok1, 1, max)
o2 = if ShouldRetry(o1) { AttemptOutcome(result, ok2, 2, max) } else { o1 }
o3 = if ShouldRetry(o2) { AttemptOutcome(result, ok3, 3, max) } else { o2 }
```

The clean unlock is **PROP-039 BudgetedLocalLoop Ruby parity** — then the retry loop
becomes a real bounded loop, and (with fold-over-state) a fold. This is the headline
pressure this app contributes.

## Pressure 2 — dynamic dispatch avoided (JR-P02)

The fixture's `JobDispatcher` calls `call_contract(job_class, …)` with a **variable**
callee — which is Tier-2 Unknown / fail-closed (`LAB-DYNAMIC-CONTRACT-DISPATCH-P2`).
So `DispatchJob` branches on the class **statically** (the trade_robot/call_router
pattern), gated by a fail-closed `KnownJob`. We *want* `call_contract(job.class, …)`
to be data-driven; the safe future is a **typed contract registry** (a sealed set of
job refs), not a runtime string.

## Pressure 3 — the lifecycle is a sealed variant (JR-P01)

`JobOutcome { Done | Retry | Exhausted | DeadLetter }` with `match` routing — Done
carries the result + attempt count, Retry carries the remaining budget, DeadLetter a
reason. A stringly status could confuse "exhausted" with "dead_letter"; the variant
cannot. Same variant/match strength as the reconciler.

## What We Need From IO

A real job runner is the canonical **standing-worker** application:

| Subsystem | What it needs from IO | Track |
|---|---|---|
| **Queue** | a durable queue read/write (enqueue, reserve, ack) | effect surface + storage/queue capability |
| **Worker loop** | a standing loop that pulls and runs jobs | ServiceLoop/`PROP-037` |
| **Re-dispatch** | an effect to actually re-run a failed job (idempotent) | effect surface + idempotency |
| **Receipt persistence** | a write capability to record each `JobReceipt` | effect write family |

The pure core (`DispatchJob`, `AttemptOutcome`, `RunWithRetry3`) stays CORE; IO is the
membrane — the queue, the worker loop, the re-dispatch, the receipts.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 4 files, 2 types, 1 variant (4 arms), 19
contracts, `entrypoint RunSuccessSecond`. See `PRESSURE_REGISTRY.md`.
