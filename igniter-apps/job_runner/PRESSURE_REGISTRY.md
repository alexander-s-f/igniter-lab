# Job Runner Pressure Registry

Created: 2026-06-14 (off-track app — pulled from `igniter-view-engine/fixtures/sidekiq_core`)

`job_runner` is a pure, Sidekiq-shaped **job dispatch + retry-budget** model. A
`JobRequest` names a job class + args; the runner dispatches STATICALLY to the named
job, then decides — per a static retry budget — whether to retry, exhaust, or
dead-letter, ending in a sealed `JobOutcome` + `JobReceipt`. No Redis, no worker
daemon, no scheduler, no queue.

## Baseline

Dual-toolchain CLEAN (Open3 / MultifileResolver subprocess route).

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/job_runner/types.ig ../igniter-apps/job_runner/jobs.ig \
  ../igniter-apps/job_runner/engine.ig ../igniter-apps/job_runner/example.ig \
  --out /tmp/job_runner.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 4 |
| types | 2 |
| variants | 1 (`JobOutcome` — Done / Retry / Exhausted / DeadLetter) |
| contracts | 19 |
| call_contract / match | 26 / 4 |
| entrypoint | `RunSuccessSecond` |
| source_hash | `sha256:06f8e6d73f4476009011fd6980d0eca86ee3821adb058916ff2e393478d71225` |

## Provenance (fixture → app)

| Fixture | job_runner model |
|---|---|
| `sidekiq_core/job_dispatch_table.ig` (named job contracts, uniform arity) | `jobs.ig` ProcessOrderJob/ComputeReportJob/ValidatePaymentJob + DispatchJob |
| `sidekiq_core/retry_policy.ig` (budget = max - attempt; **BudgetedLocalLoop**) | `engine.ig` RetryBudget + RunWithRetry3 (manual unroll, JR-P03) |
| `sidekiq_core/jobreceipt_schema.ig` (job receipt) | `JobReceipt` + BuildReceipt |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| JR-P01 | **sealed JobOutcome variant** | the lifecycle (Done/Retry/Exhausted/DeadLetter) is a sealed sum, not a stringly status; routing is `match`. | POSITIVE — capability | regression evidence for `LANG-SUMTYPE-CONSTRUCT-MATCH` |
| JR-P02 | **dynamic dispatch avoided** | the production fixture uses `call_contract(job_class, …)` with a VARIABLE callee → Tier-2 Unknown / fail-closed. `DispatchJob` branches on the class STATICALLY (trade_robot/call_router pattern). A typed job registry would let the class be data without losing the static guarantee. | INTENTIONAL fail-closed | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` (policy) + typed contract registry |
| JR-P03 | **managed loop is Rust-only** | the retry simulator wants a managed `loop … max_steps: N` (PROP-039 BudgetedLocalLoop), but that surface is **NOT dual-clean** — the Ruby TC rejects loop-body compute reassignment (`OOF-L7`), Rust accepts it. So `RunWithRetry3` unrolls 3 attempts by hand (per-attempt success injected). | ACTIVE — parity gap | `PROP-039` BudgetedLocalLoop **Ruby parity** (the real fresh finding) |
| JR-P04 | **retry budget is explicit arithmetic** | `RetryBudget = max_attempts - attempt`; pure, no clock, no queue. budget>0 → Retry, =0 → Exhausted. | POSITIVE | — |
| JR-P05 | **no Redis / worker / scheduler / queue** | no durable queue, no worker daemon, no real re-dispatch; attempt success is injected and the loop is bounded by source. A real runner needs all of these as IO. | DOCUMENTED — behind | ServiceLoop/`PROP-037` (standing worker) + effect surface (re-dispatch, queue) |
| JR-P06 | **record-literal factories** | `MakeReq` / `BuildReceipt` pin `JobRequest` / `JobReceipt` (inline literals infer Unknown in Rust). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` |

## Capability Discovery (positive)

The retry railway — `AttemptOutcome` → `ShouldRetry` (match) → unrolled `RunWithRetry3`
threading a `JobOutcome` value through `if/else` branches — is dual-clean, same as
the reconciler. Static name-based dispatch with a fail-closed `KnownJob` gate is the
safe Sidekiq pattern. The single missing piece for a faithful retry loop is **PROP-039
managed-loop Ruby parity** (JR-P03) — the standout gap this app surfaces.

## Safety Interpretation

Proves the language can model job dispatch + bounded retry as a pure, fail-closed
core. It does NOT claim: any Redis/queue/worker/scheduler, real re-dispatch, a clock,
a managed retry loop (unrolled), or Sidekiq compatibility.

## Non-Goals

- No Redis / queue / worker daemon / scheduler.
- No real retry dispatch (attempt outcomes injected).
- No managed `loop` (Rust-only; unrolled by hand).
- No dynamic job dispatch (static, name-based).
- No clock / `now()`.

## Recommended Route

1. **PROP-039 BudgetedLocalLoop Ruby parity** (JR-P03) — the fresh gap; would let the
   retry loop be a real managed loop instead of a 3-unroll.
2. Keep as **regression evidence** for `LANG-SUMTYPE-CONSTRUCT-MATCH` (JR-P01) and
   `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` (JR-P02).
3. ServiceLoop/`PROP-037` + effect surface for a standing worker (JR-P05).
