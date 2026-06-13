# LAB-IGNITER-LANG-MICROSERVICE-P1

**Status:** CLOSED — PROOF COMPLETE (72/72)  
**Route:** LAB SERVICE ENVELOPE / MICROSERVICE READINESS  
**Date closed:** 2026-06-13  
**Authority:** envelope design + proof only; no server implementation

## Goal

Define the Igniter microservice envelope after IO Runtime P1: ingress, contract evaluation,
effect execution, response, receipts, and audit. This is not a Rack framework card.

The purpose is to prevent the old half-measure: `HTTP host -> pure contract -> JSON`.
A real Igniter microservice must include effect execution through CapabilityExecutor.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RACK-P14.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-LANG-HTTP-TYPES-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/examples/experimental_executable_quickstart_v0/quickstart.rb`

## Questions

1. What is the service request envelope: route, contract_id, input, authority, capability passport, idempotency key?
2. What is the response envelope: output, diagnostics, receipts, effect outcomes, correlation id?
3. What is host/substrate vs Igniter semantics?
4. What must be allowlisted: contract ids, artifact digest, capability ids, profiles?
5. How does replay work for a request with real IO?
6. Which parts of Rack-shaped prior work are reusable as typed HTTP shapes, and which are explicitly not authority?

## Deliverables

- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-microservice-envelope-p1-v0.md`
- Proof/static runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p1.rb`, target at least 45 checks.
- Card update and portfolio update after closure.

## Acceptance

- Defines a microservice envelope that includes CapabilityExecutor effects.
- Keeps Rack/HTTP as substrate binding only.
- No server implementation, no production/runtime claim.

---

## Closure

| Artifact | Path | Status |
|---|---|---|
| Lab doc | `lab-docs/lang/lab-igniter-lang-microservice-envelope-p1-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p1.rb` | ✅ DONE — 72/72 PASS |
| Card update | `.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

### Acceptance Criteria — all satisfied

- [x] Defines a microservice envelope that includes CapabilityExecutor effects (8-gate pipeline, EffectPlan, EffectReceipt).
- [x] Keeps Rack/HTTP as substrate binding only (three-layer separation: host / substrate / Igniter semantics).
- [x] No server implementation, no production/runtime claim.
- [x] Proof runner passes 72/72 across 8 sections.
- [x] Q6 Rack reuse boundary explicit: reusable typed shapes vs not-authority surfaces.

### Key Deliverables

**ServiceRequest envelope:** `correlation_id`, `contract_id`, `effect_names`, `input: Map[String, Value]`,
`authority_ref`, `capability_passports`, `idempotency_key`, `artifact_digest`, `ingress_timestamp`
(clock binding, not `now()`), `profile_ids` (declared-only gate).

**ServiceResponse envelope:** `kind`, `output`, `diagnostics`, `receipts: [EffectReceipt]`,
`effect_outcomes`, `response_observation` (P26 audit closure with `evidence_digest`).

**8 fail-closed gates:** contract_id allowlist → artifact_digest → capability_id allowlist →
profile_id allowlist → authority_ref → passport validity → idempotency_key → executor registration.

**Replay invariant:** same `inputs_hash` + `idempotency_key` + `capability_id` = idempotent re-execution.
`unknown_external_state` requires reconciliation, not retry (P15 enforced).

**Rack reuse boundary:** `HttpRequest`/`HttpResponse` shapes and `ContractResult` 6-branch
status taxonomy (LAB-RACK-P14) are reusable as typed substrate shapes. `call_contract`,
Rack env, accept-loop, and `Igniter::ContractBuilder` are explicitly not authority.
