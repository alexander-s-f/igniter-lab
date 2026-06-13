# LAB-IGNITER-LANG-MICROSERVICE-P2

**Status:** OPEN — DISPATCH READY / GATED BY IO RUNTIME P3  
**Route:** LAB SERVICE ENVELOPE / MOCK EXECUTION INTEGRATION  
**Date:** 2026-06-13  
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
