# LAB-IGNITER-LANG-IO-RUNTIME-P4

**Status:** OPEN — DISPATCH READY / GATED BY LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3  
**Route:** LAB RUNTIME / RUNTIMEMACHINE EXECUTOR WIRING  
**Date:** 2026-06-13  
**Authority:** proof-local runtime wiring only; no real IO and no production runtime claim

## Goal

Wire the proof-local executor substrate into a minimal RuntimeMachine evaluate extension.

This is the first card that should connect these pieces into a runnable IO loop:

1. compiled/evidenced effect intent (`effect_surface_v0_stub` + IO escape boundary),
2. executor registry,
3. capability passport / authority / idempotency preflight,
4. storage executor dispatch,
5. `EffectResult` envelope + receipts.

## Gate

Do not start until:

- `LAB-IGNITER-LANG-IO-RUNTIME-P3` is CLOSED — executor runtime substrate exists and is 129/129 PASS.
- `LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3` is CLOSED — SemanticIR emits `effect_surface_v0_stub` / IO escape boundary evidence.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-io-runtime-p3-storage-executor-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/io_capability_executor/capability_executor_runtime.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p3.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/runtime_machine_memory_proof/compiled_program.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/runtime_machine_memory_proof/runtime_machine_memory_proof.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch7-runtime.md`

## Implementation Guidance

Prefer proof-local extension/wrapper over changing canon runtime unless the card proves the narrow change is safe.

Allowed shapes:

- proof-local `RuntimeMachine` extension module,
- proof-local `CompiledProgram` fixture with effect evidence,
- adapter that consumes `effect_surface_v0_stub` / `escape_boundaries`,
- executor registry from `capability_executor_runtime.rb`.

Runtime behavior must distinguish:

- pre-executor `RuntimeRefusal` — no receipt,
- executor denial-as-data — `EffectResult.denied` with receipt,
- executor success/failure/unknown external state — `EffectResult` with receipt.

## Deliverables

- Proof-local implementation files as needed under experiments/lab proof paths.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p4.rb`, target at least 90 checks.
- Proof doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-io-runtime-p4-runtime-wiring-proof-v0.md`.
- Card update and portfolio update after closure.

## Acceptance

- A minimal runtime evaluation path reads effect evidence and dispatches through executor registry.
- Missing executor/passport/authority/idempotency fails before executor and emits `RuntimeRefusal` with no receipt.
- Successful storage read returns `EffectResult.succeeded` with receipt.
- Denied gate returns `EffectResult.denied` with receipt.
- `unknown_external_state` remains distinct from `failed` per P15.
- Pure input/compute/output runtime behavior from prior proof remains unchanged.

## Closed Surfaces

- No real DB/SQL/ORM/migrations/transactions/persistence.
- No network/file/process IO.
- No Rack or HTTP server.
- No public API claim.
- No Reference Runtime claim.
- No full PROP-035 Effect Surface.
- No storage write family.

## Next Route

After closure: `LAB-IGNITER-LANG-MICROSERVICE-P3` runs the ServiceRequest/ServiceResponse envelope over this actual Runtime P4 path.
