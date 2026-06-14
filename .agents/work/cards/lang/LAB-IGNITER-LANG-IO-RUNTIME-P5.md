# LAB-IGNITER-LANG-IO-RUNTIME-P5

**Status:** OPEN — DISPATCH READY  
**Route:** LAB RUNTIME / IO REGRESSION CONSOLIDATION  
**Date:** 2026-06-14  
**Authority:** proof-local runtime regression only; no new runtime surface

## Goal

Freeze the proof-local IO runtime ladder after the P3/P4/P3 closures.

This card should consolidate the chain:

```text
effect_surface_v0_stub
  -> RuntimeMachine.evaluate_effect
  -> CapabilityExecutorRegistry
  -> CapabilityPassport preflight
  -> StorageCapabilityExecutor
  -> EffectResult + EffectReceipt
  -> ServiceResponse envelope
```

The purpose is regression confidence before any substrate adapter discussion. This is not an implementation expansion card.

## Gate

Start only after all are closed:

- `LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3` — 65/65
- `LANG-IO-CAPABILITY-EXECUTOR-P3` — executor runtime substrate
- `LAB-IGNITER-LANG-IO-RUNTIME-P3` — 129/129
- `LAB-IGNITER-LANG-IO-RUNTIME-P4` — 104/104
- `LAB-IGNITER-LANG-MICROSERVICE-P3` — 90/90

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/io_capability_executor/capability_executor_runtime.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/io_capability_executor/runtime_machine_io_extension.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/effect_surface_runtime_bridge_proof/verify_effect_surface_runtime_bridge_p3.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p3.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p4.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p3.rb`
- Related proof docs under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/`

## Questions

1. Do all existing IO proof runners still pass together after the late-day changes?
2. Is the `effect_surface_v0_stub` shape still consumed by the runtime extension without drift?
3. Are runtime refusals still pre-executor and receipt-free?
4. Are executor denials still data outcomes with receipts?
5. Is P15 still enforced for `timed_out` and `unknown_external_state`?
6. Does the ServiceResponse envelope preserve replay evidence and substrate neutrality?
7. Are any docs claiming Rack/HTTP/real IO authority too early?

## Deliverables

- Consolidated proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p5.rb`, target at least 100 checks.
- Regression doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-io-runtime-p5-regression-v0.md`.
- Update this card with closure summary.
- Portfolio update after closure.

## Acceptance

- P3/P4/P3 upstream proof runners are invoked or statically validated by the P5 runner.
- The proof covers at least: effect stub, escape boundary, registry lookup, preflight refusal, denial-as-data, success, failure, unknown external outcome, replay evidence, and microservice envelope.
- No new implementation files are required. If a tiny harness helper is needed, it must be proof-local.
- Closed surfaces are explicitly checked.

## Closed Surfaces

- No Rack server.
- No HTTP accept loop.
- No real DB/SQL/ORM/migrations/transactions.
- No file/network/process IO.
- No storage write family.
- No production/reference runtime claim.
- No full PROP-035 effect surface implementation.
