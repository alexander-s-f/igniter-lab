# LAB-IGNITER-LANG-MICROSERVICE-P2

**Status:** CLOSED — PROOF COMPLETE (60/60)  
**Route:** LAB SERVICE ENVELOPE / MOCK EXECUTION INTEGRATION  
**Date closed:** 2026-06-13  
**Authority:** proof-only service envelope integration; no server implementation

## Goal

Validate the `ServiceRequest` / `ServiceResponse` envelope from `LAB-IGNITER-LANG-MICROSERVICE-P1` against the mocked storage executor path from IO Runtime P3.

This is not a Rack server card. It is a proof that the service envelope can carry:

- contract id and artifact digest
- input values
- authority reference
- capability passports
- idempotency key
- effect outcomes
- receipts
- diagnostics and replay evidence

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-microservice-envelope-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RACK-P14.md`

## Scope

- No HTTP server.
- No Rack middleware.
- No real IO.
- No public API claim.
- Use static/mock request envelopes and executor outcomes.

## Deliverables

- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md`
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p2.rb`, target at least 60 checks.
- Card update and portfolio update.

## Acceptance

- Service envelope can represent successful storage read + denied + unknown_external_state.
- Replay evidence fields are sufficient and deterministic.
- Rack/HTTP remains substrate-only.
- No server implementation is introduced.

---

## Closure

| Artifact | Path | Status |
|---|---|---|
| Lab doc | `lab-docs/lang/lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igniter_lang_microservice_p2.rb` | ✅ DONE — 60/60 PASS |
| Card update | `.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

### Acceptance Criteria — all satisfied

- [x] Service envelope represents successful storage read (kind `"ok"`, outcome `"succeeded"`).
- [x] Service envelope represents denied outcome (kind `"denied"`, receipt has `denial_gate: "G1"`).
- [x] Service envelope represents unknown_external_state (kind `"effect_failure"`, receipt has `outcome: "unknown_external_state"` — P15 enforced).
- [x] Replay evidence: `idempotency_key`, `inputs_hash`, `authority_ref`, `correlation_id` all thread from request to receipt.
- [x] `inputs_hash` is deterministic: same plan = same hash; different plan = different hash.
- [x] Rack/HTTP substrate-only: `EnvelopeRunner` requires no Rack env, no HTTP server.
- [x] No server implementation: proof-local simulation only.

### Key Deliverables

**EnvelopeRunner (proof-local):** wraps `MockStorageCapabilityExecutor` in P1 envelope shapes.
8-gate allowlist from P1 enforced before executor dispatch (contract_id, artifact_digest,
capability_id, authority_ref, passport validity, executor registration).

**Three scenarios proved:**
1. Succeeded: `ServiceResponse{kind:"ok", receipts:[{outcome:"succeeded"}]}`
2. Denied (G1): `ServiceResponse{kind:"denied", receipts:[{outcome:"denied", query_receipt.denial_gate:"G1"}]}`
3. Unknown external state: `ServiceResponse{kind:"effect_failure", receipts:[{outcome:"unknown_external_state"}]}`

**P15 enforcement:** `unknown_external_state` receipt outcome is distinct from `"failed"`.
Response uses `kind:"effect_failure"` but consumer must branch on `receipts[0].outcome`.

**ResponseObservation** (P26 audit closure): `evidence_digest = sha256(receipts + output + outcome_kind)` — deterministic and content-addressed.
