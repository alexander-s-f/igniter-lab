# LAB-IGNITER-LANG-MICROSERVICE-P3

**Status:** OPEN — DISPATCH READY / GATED BY LAB-IGNITER-LANG-IO-RUNTIME-P4  
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
