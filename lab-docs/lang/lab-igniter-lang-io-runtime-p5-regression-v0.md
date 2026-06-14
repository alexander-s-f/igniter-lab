# LAB-IGNITER-LANG-IO-RUNTIME-P5 - Regression Consolidation v0

**Card:** LAB-IGNITER-LANG-IO-RUNTIME-P5  
**Route:** LAB RUNTIME / IO REGRESSION CONSOLIDATION  
**Status:** CLOSED - PROOF COMPLETE (145/145)  
**Date:** 2026-06-14  
**Authority:** proof-local runtime regression only; no new runtime surface

## Scope

P5 freezes the proof-local IO runtime ladder after the P3/P4 runtime closures
and the microservice P3 envelope closure.

The consolidated path is:

```text
effect_surface_v0_stub
  -> RuntimeMachine.evaluate_effect
  -> CapabilityExecutorRegistry
  -> CapabilityPassport preflight
  -> StorageCapabilityExecutor
  -> EffectResult + EffectReceipt
  -> ServiceResponse envelope
```

This document and proof runner do not open substrate adapter work. They add no
canon runtime API, no production runtime claim, and no public/stable surface.

## Upstream Proofs Invoked

The P5 runner invokes the upstream proof runners as subprocesses and checks
their expected pass counts:

| Upstream proof | Expected result |
|---|---:|
| LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3 | 65/65 |
| LAB-IGNITER-LANG-IO-RUNTIME-P3 | 129/129 |
| LAB-IGNITER-LANG-IO-RUNTIME-P4 | 104/104 |
| LAB-IGNITER-LANG-MICROSERVICE-P3 | 90/90 |

The dependency-card check uses the concrete executor chain that exists in the
repositories: `LANG-IO-CAPABILITY-EXECUTOR-P1` (80/80), `P2` (86/86), and the
runtime substrate implementation closed by `LAB-IGNITER-LANG-IO-RUNTIME-P3`
(129/129). There is no separate tracked `LANG-IO-CAPABILITY-EXECUTOR-P3` card in
this checkout.

## What P5 Proves

1. The `effect_surface_v0_stub` shape is still consumable by the runtime
   extension without drifting into full PROP-035 authority.
2. Runtime preflight refusals remain pre-executor and receipt-free.
3. Executor denials remain data outcomes with receipts.
4. Success, failure, denial, clamp, and unknown external outcomes still flow
   through `EffectResult` and `EffectReceipt`.
5. P15 remains enforced: `timed_out` and `unknown_external_state` classify as
   unknown external outcomes, not observed failures.
6. The proof-local ServiceResponse envelope preserves replay evidence and
   substrate neutrality.
7. Closed surfaces remain closed: no Rack server, no HTTP accept loop, no real
   DB/SQL/ORM, no file/network/process IO, no storage write family, and no
   production/reference runtime claim.

## Proof Runner

**Path:** `igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p5.rb`  
**Result:** 145/145 PASS

| Section | Scope | Checks |
|---|---|---:|
| A | Upstream proof runners invoked and counted | 16 |
| B | Dependency cards and docs | 21 |
| C | Effect surface stub shape | 12 |
| D | Runtime wiring source shape | 12 |
| E | Runtime preflight refusals | 24 |
| F | Executor outcomes | 18 |
| G | Receipt and replay evidence | 12 |
| H | ServiceResponse envelope | 18 |
| I | Closed surfaces | 12 |
| **Total** | | **145** |

## Regression Findings

No runtime drift was found.

The proof confirmed:

- `RuntimeRefusal` is still separate from executor-side `EffectResult.denied`.
- Runtime refusal paths still emit no receipt and no `effect_result`.
- Executor-side G1/G2/G3 denials still return `{ outcome: "denied" }` with a
  receipt.
- G4 row-limit clamping remains a success outcome, not a denial.
- G5 include-all policy violation remains `failed/query_error`.
- G6 simulated system error remains `failed/system_error`.
- A proof-local unknown-state executor maps to `unknown_external_state`, and
  the ServiceResponse envelope maps that to `effect_failure` while preserving
  the receipt outcome for replay/reconciliation.
- `inputs_hash`, `receipt_id`, `idempotency_key`, `idempotency_used`,
  `capability_id`, `authority_ref`, and `evidence_digest` remain deterministic
  replay evidence.

## Closed Surfaces

P5 keeps the following closed:

- No Rack server.
- No HTTP accept loop.
- No real DB, SQL, ORM, migrations, or transactions.
- No file, network, or process IO.
- No storage write family.
- No production runtime claim.
- No Reference Runtime claim.
- No public/stable runtime API.
- No full PROP-035 effect surface implementation.

## Next Route

Substrate adapter discussion remains blocked behind a separate readiness card.
The safe next route is governance/readiness only, not implementation: validate
which adapter family, authority source, and replay semantics would be allowed
before opening any real substrate.
