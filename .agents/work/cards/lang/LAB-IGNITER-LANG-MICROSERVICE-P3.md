# LAB-IGNITER-LANG-MICROSERVICE-P3

**Status:** CLOSED — PROOF COMPLETE (90/90)  
**Route:** LAB SERVICE ENVELOPE / RUNTIME-WIRED STORAGE EXECUTION  
**Date:** 2026-06-13  
**Authority:** proof-only service integration; no HTTP server and no production API

## Goal

Re-run the microservice envelope over the actual Runtime P4 executor-dispatch path.

P2 proved the envelope over a mock runner. P3 must prove the same ServiceRequest/ServiceResponse shapes can carry a runtime-wired storage read result where the RuntimeMachine path performs registry lookup and executor dispatch.

## Gate

Do not start until:

- `LAB-IGNITER-LANG-MICROSERVICE-P2` is CLOSED — envelope proof 60/60.
- `LAB-IGNITER-LANG-IO-RUNTIME-P4` is CLOSED — runtime-wired executor dispatch exists.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P4.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/io_capability_executor/capability_executor_runtime.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RACK-P14.md`

## Scope

Validate the envelope over these scenarios:

1. successful storage read,
2. pre-executor runtime refusal,
3. executor denial-as-data,
4. unknown external state,
5. deterministic replay evidence.

Preserve the substrate boundary: HTTP/Rack/queue are ingress/egress adapters only and are not authority.

## Deliverables

- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p3.rb`, target at least 75 checks.
- Card update and portfolio update after closure.

## Acceptance

- ServiceRequest supplies contract id, artifact digest, inputs, authority_ref, capability passports, profile ids, idempotency key.
- Runtime P4 path, not a mock-only runner, produces the effect outcome.
- ServiceResponse carries output/diagnostics/receipts/effect_outcomes and response observation.
- Replay fields remain deterministic: inputs_hash, idempotency_key, capability_id, evidence_digest.
- Rack/HTTP remains substrate-only.

## Closed Surfaces

- No HTTP server.
- No Rack middleware.
- No real IO.
- No database, SQL, ORM, migrations, queues, files, sockets, or processes.
- No public API claim.
- No production runtime claim.
- No broad service framework implementation.

---

## Closure

**Closed:** 2026-06-13
**Score:** 90/90 PASS

| Artifact | Path | Status |
|---|---|---|
| Lab doc | `lab-docs/lang/lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p3.rb` | ✅ DONE — 90/90 PASS |
| Card update | `.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P3.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

### Acceptance Criteria — all satisfied

- [x] ServiceRequest supplies contract id, artifact digest, inputs, authority_ref, capability passports (CapabilityPassport structs), profile ids, idempotency key.
- [x] Runtime P4 path (`RuntimeMachine.evaluate_effect`) produces the effect outcome — not a mock-only runner.
- [x] ServiceResponse carries output/diagnostics/receipts/effect_outcomes and ResponseObservation.
- [x] Replay fields deterministic: `inputs_hash`, `idempotency_key`, `capability_id`, `evidence_digest`.
- [x] Rack/HTTP remains substrate-only (`ingress_substrate` recorded but not used for dispatch).

### Key Deliverables

**RuntimeEnvelopeAdapter (proof-local):** wraps `RuntimeMachine.evaluate_effect` in P1
ServiceRequest/ServiceResponse shapes. 8-gate preflight from IO Runtime P4 runs inside
the machine before executor dispatch.

**Five scenarios proved:**
1. Succeeded: `ServiceResponse{kind:"ok", receipts:[{outcome:"succeeded"}]}`
2. RuntimeRefusal (machine preflight — revoked/expired/wrong-family/nil passport, unknown contract):
   `ServiceResponse{kind:"runtime_refusal", receipts:[]}`
3. Executor denial-as-data (G1/G2/G3): `ServiceResponse{kind:"denied", receipts:[{outcome:"denied", denial_gate:"G1"}]}`
4. Unknown external state (P15 — via proof-local UnknownStateStorageExecutor):
   `ServiceResponse{kind:"effect_failure", receipts:[{outcome:"unknown_external_state"}]}`
5. Deterministic replay: same inputs → same `inputs_hash`; same correlation → same `evidence_digest`.

**CapabilityPassport struct form:** P3 `capability_passports` values are proper
`CapabilityExecutorRuntime::CapabilityPassport` structs (7 fields), enabling the machine's
preflight gates (`revoked?`, `expired?`, `valid_family?`) to run without any bridge layer.

**P15 enforcement:** `unknown_external_state` receipt outcome ≠ `"failed"`. Response uses
`kind:"effect_failure"` but consumer must branch on `receipts[0].outcome`.

**ResponseObservation** (P26 audit closure): `evidence_digest = sha256(receipt_refs + output + outcome_kind)`.
