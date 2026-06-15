# LAB Job Runner Baseline v0

**Card:** LAB-JOB-RUNNER-BASELINE-P1  
**Status:** CLOSED / PROVED - 190/190 PASS  
**Date:** 2026-06-15  
**Authority:** lab evidence baseline only; no implementation or canon authority

## Decision

`job_runner` is frozen as a positive dual-toolchain baseline and pressure source.

It models a Sidekiq-shaped static job dispatch and retry-budget core:

- `JobRequest` names a job class and arguments.
- `DispatchJob` branches statically to known job contracts.
- `RunWithRetry3` simulates bounded retry with injected attempt outcomes.
- `JobOutcome` is a sealed lifecycle variant.
- `JobReceipt` is a flattened logging receipt, not the routing authority.

No app source edits were made.

## Proof

Runner:

`igniter-view-engine/proofs/verify_lab_job_runner_baseline_p1.rb`

Result:

`190/190 PASS`

The runner uses absolute source paths, `Open3.popen3`, `Dir.mktmpdir`, and a
timeout/kill guard for compiler subprocesses. This is the project-standard
fresh-output proof route for route-sensitive source hashes.

## Compilation Baseline

| Toolchain | Result | Diagnostics | Source hash |
|---|---|---:|---|
| Ruby canon `CompilerOrchestrator.compile_sources` | `ok` | 0 | `sha256:546c30b56c9b79d4b8bf1fbc396bb2252aec0b6ae58ac85bd7e7708932c3b91c` |
| Rust lab `igniter_compiler compile` | `ok` | 0 | `sha256:546c30b56c9b79d4b8bf1fbc396bb2252aec0b6ae58ac85bd7e7708932c3b91c` |

The earlier registry hash
`sha256:06f8e6d73f4476009011fd6980d0eca86ee3821adb058916ff2e393478d71225`
was route-sensitive predecessor metadata. The closed baseline is the absolute
Open3/mktmpdir hash above.

## Shape

| Metric | Value |
|---|---:|
| source files | 4 |
| types | 2 (`JobRequest`, `JobReceipt`) |
| variants | 1 (`JobOutcome`) |
| contracts | 19 |
| textual `call_contract` mentions | 26 |
| executable `call_contract` forms | 25, all string-literal Tier 1 |
| textual `match` mentions | 4 |
| executable `match` expressions | 4 |
| loop forms | 0 |
| entrypoint | `RunSuccessSecond` |

Manifest and SemanticIR both preserve four source units:

- `JobRunnerTypes`
- `JobRunnerJobs`
- `JobRunnerEngine`
- `JobRunnerExample`

## Positive Discovery

`JobOutcome` is the capability witness:

| Arm | Payload |
|---|---|
| `Done` | `result`, `attempts` |
| `Retry` | `budget`, `result` |
| `Exhausted` | `attempts` |
| `DeadLetter` | `reason` |

The lifecycle is routed with `match`, not stringly status. `OutcomeStatus`
flattens the variant only for receipt/logging.

## Static Dispatch

Dynamic callee dispatch stays closed. `DispatchJob` and `KnownJob` branch over
the closed job names:

- `process_order`
- `compute_report`
- `validate_payment`

Unknown job classes fail closed into the `DeadLetter` branch through the
`KnownJob` gate. This preserves `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` rather than
weakening it.

## Retry Boundary

`RetryBudget = max_attempts - attempt` is explicit arithmetic. `RunWithRetry3`
unrolls three attempts by hand because the faithful managed loop remains
Rust-only / Ruby parity pressure under PROP-039 `BudgetedLocalLoop`.

This baseline proves the retry policy can be modeled as a pure core; it does
not prove a scheduler, worker daemon, queue, or real re-dispatch.

## Pressure Routes

| ID | Route |
|---|---|
| JR-P01 | `LANG-SUMTYPE-CONSTRUCT-MATCH` regression evidence for sealed `JobOutcome` |
| JR-P02 | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` fail-closed static-dispatch route |
| JR-P03 | PROP-039 `BudgetedLocalLoop` Ruby parity |
| JR-P04 | positive explicit retry-budget arithmetic |
| JR-P05 | ServiceLoop / PROP-037 plus effect surface for real worker and queue behavior |
| JR-P06 | `LANG-RUBY-RECORD-LITERAL-INFERENCE` record-literal factory pressure |

## Closed Surfaces

- No Redis / queue / scheduler / worker daemon.
- No real retry dispatch.
- No managed-loop implementation.
- No dynamic job dispatch.
- No clock / `now()`.
- No ServiceLoop implementation.
- No DB / SQL / ORM.
- No HTTP / Rack / socket server.
- No app source migration.
