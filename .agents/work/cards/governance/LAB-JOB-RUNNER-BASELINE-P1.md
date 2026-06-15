# LAB-JOB-RUNNER-BASELINE-P1

**Status:** OPEN  
**Route:** lab / app baseline / job_runner  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `job_runner` as a positive dual-toolchain baseline and pressure source.

`job_runner` models Sidekiq-shaped static job dispatch plus retry-budget logic as
a pure core. It intentionally keeps Redis, queue, scheduler, worker daemon, clock,
and real re-dispatch outside the app.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/jobs.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/engine.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/example.ig`
- `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`
- `LANG-SUMTYPE-CONSTRUCT-MATCH-P1/P2/P3` if P3 has landed.
- BudgetedLocalLoop / PROP-039 docs if available.

## Proof Questions

1. Does the full app compile cleanly in Ruby and Rust?
2. Are the registry metrics stable: 4 files, 2 types, 1 variant, 19 contracts, 26 `call_contract`, 4 `match`, `entrypoint RunSuccessSecond`?
3. Is source hash stable under the project-standard Open3/mktmpdir compile route?
4. Does `JobOutcome` remain a positive sealed-sum capability witness?
5. Does static job dispatch remain fail-closed and not dynamic callee dispatch?
6. Does JR-P03 correctly identify managed loop as Rust-only / Ruby parity pressure?
7. Are JR-P01..JR-P06 preserved and routed accurately?

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_job_runner_baseline_p1.rb`, target at least 90 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-job-runner-baseline-v0.md`.
- Update `job_runner/PRESSURE_REGISTRY.md` with closure summary.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Source hash and app metrics are frozen.
- JR-P01..JR-P06 remain documented and routed.
- No app source edits.

## Closed Surfaces

- No Redis / queue / scheduler / worker daemon.
- No real retry dispatch.
- No managed-loop implementation.
- No dynamic job dispatch.
- No clock / `now()`.
- No ServiceLoop implementation.

## Agent Recommendation

Give this to **Gemini** or **Sonnet 4.6**. The companion readiness card
`LANG-BUDGETED-LOCAL-LOOP-RUBY-P1` can run in parallel.
