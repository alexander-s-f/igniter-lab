# LAB-IGNITER-LANG-IO-RUNTIME-P1

**Card:** LAB-IGNITER-LANG-IO-RUNTIME-P1  
**Track:** lab-igniter-lang-io-runtime-readiness-boundary-v0  
**Status:** CLOSED — PROOF COMPLETE (85/85)  
**Route:** LAB READINESS / IO RUNTIME / NO IMPLEMENTATION  
**Authority:** evidence + route decision only  
**Agent role:** language-design-agent / runtime-boundary-agent  
**Date closed:** 2026-06-13

---

## Closure

| Artifact | Path | Status |
|---|---|---|
| Readiness doc | `lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p1.rb` | ✅ DONE — 85/85 PASS |
| Card update | `.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

### Acceptance Criteria — all satisfied

- [x] Doc clearly distinguishes `igniter-lang` from the old Ruby `igniter` gem.
- [x] Doc rejects "pure HTTP wrapper only" as insufficient for microservice goals.
- [x] Doc defines an IO Runtime route centered on Effect Surface + CapabilityExecutor + receipts.
- [x] Doc keeps Rack/HTTP as substrate binding, not core architecture.
- [x] Proof runner passes 85/85; verifies key evidence anchors across 9 sections.
- [x] Next card is explicit and narrow: LANG-IO-CAPABILITY-EXECUTOR-P1.

### Route Confirmed

The expected route is confirmed:

```
effect contract
  -> capability/effect_binding (experiment-pass)
  -> SemanticIR ESCAPE fragment + escape_boundaries (accepted)
  -> RuntimeMachine load (proven) / evaluate (supported for pure nodes)
  -> CapabilityExecutor registry [GAP — not yet implemented]
  -> typed receipt / failure / unknown_external_state
  -> substrate binding: HTTP, DB, file, queue, clock, random, IPC
```

### Recommended Next Cards

1. **LANG-IO-CAPABILITY-EXECUTOR-P1** — CapabilityExecutor interface proposal,
   capability passport shape, receipt/failure shape, fail-closed behavior.
2. **LAB-IGNITER-LANG-IO-RUNTIME-P2** — first mocked IO runtime slice (Storage
   read family recommended; deepest evidence).
3. **LAB-IGNITER-LANG-MICROSERVICE-P1** — service envelope after P2.

---

## Mission

Establish the real `igniter-lang` IO Runtime route for microservice-capable Igniter.

This card must avoid the old Ruby `igniter` framework entirely. Do not use or cite
`Igniter::ContractBuilder`, `GraphCompiler`, Rack integration docs from
`/Users/alex/dev/projects/igniter`, ActiveRecord, ORM, Rails, or the legacy Ruby
gem runtime as architecture authority.

The target question is not "can a host call pure contracts over HTTP?". That is a
half-measure and will loop back into the IO wall. The target question is:

> What minimal `igniter-lang` runtime surface is required for real IO execution
> while preserving Igniter's honesty/accountability model?

---

## Background

Recent app and lab work has repeatedly pushed to the same frontier:

- Rack-shaped response contracts were proven to useful typed shapes, but real
  accept-loop / HTTP ingress stayed out of scope.
- StorageCapability proved capability gates, denial-as-data, and receipts, but
  real DB/SQL/ORM remained closed.
- Query, File/Text IO, Network, Sidekiq-like, and Rack-shaped forms reached the
  point where mocked/proof-local behavior is no longer enough to answer the
  microservice question.
- `igniter-lang` already has `IO.*` capability grammar and RuntimeMachine specs,
  but not a real capability executor bridge.

The next frontier should be an IO Runtime track, not another pure wrapper.

---

## Evidence To Read First

Read these files directly before writing conclusions:

### Canon / `igniter-lang`

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch4-fragment-classification.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch6-semanticir.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch7-runtime.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch10-contract-modifiers.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch11-profile-system.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch12-effect-surface.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/source/io_capability_basic.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/source/io_capability_oof_blocked.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/io_capability_proof/io_capability_proof.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/runtime_smoke.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/semanticir_expression_evaluator.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/temporal_access_runtime.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/examples/experimental_executable_quickstart_v0/quickstart.rb`

### Lab evidence / prior IO-shaped pressure

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-IO-BOUNDARY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-FILE-IO-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-LANG-HTTP-TYPES-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RACK-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-RACK-P14.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-SIDEKIQ-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STDLIB-NET-P6.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STDLIB-NET-P9.md`

---

## Core Boundary Assertion To Test

The expected route is:

```text
effect contract / observed contract
  -> explicit Effect Surface / IO capability declaration
  -> SemanticIR escape/capability requirements
  -> RuntimeMachine load/evaluate gate
  -> CapabilityExecutor registry
  -> typed receipt / failure / unknown_external_state
  -> optional substrate binding: HTTP, DB, file, queue, clock, random, IPC
```

Rack/HTTP is one possible substrate binding. It is not the architecture.
ORM/ActiveRecord is not the architecture. The old Ruby framework is not the
authority surface.

---

## Questions To Answer

Answer all questions with file evidence.

1. **Current status:** What is already accepted/proven in `igniter-lang` for
   RuntimeMachine load/evaluate, SemanticIR requirements, capabilities, and
   effect declarations?
2. **Effect gap:** Which parts of Ch12 Effect Surface are still proposed/pending,
   and which subset is experiment-pass today?
3. **IO capability shape:** How are `IO.*` names represented today? Confirm the
   covenant rule that `IO.*` is opaque and must not import Rack/HTTP/gem schemas.
4. **Runtime gap:** What exactly prevents a real IO effect from executing today?
   Separate parser/classifier/TC support from RuntimeMachine execution support.
5. **Capability executor:** What minimal `CapabilityExecutor` interface is needed
   for one effect family without opening ambient IO?
6. **Receipts/failures:** What common result envelope is needed for success,
   denied, failed, timed_out, unknown_external_state, compensated, cancelled?
7. **Microservice model:** What does an Igniter microservice mean if IO is native?
   Define ingress, evaluate, effect execution, response, receipt, and audit flow.
8. **Substrate separation:** Which layer owns HTTP/Rack, DB/SQL, files, queues,
   clock, random, and IPC? Which layer owns semantics?
9. **Replay/determinism:** How does the runtime preserve deterministic replay when
   real IO occurs? What must be recorded as evidence?
10. **Safety gates:** What must refuse by default: missing capability, unknown
    capability, unsupported substrate, no idempotency, no authority, no receipt,
    unknown external outcome?
11. **First executable slice:** Which one IO family should be selected for P2?
    Candidate families: Storage read, HTTP outbound, File read, Queue enqueue.
12. **Closed surfaces:** What must remain closed in P1: no implementation, no real
    DB/network/file/process, no public API claim, no production runtime claim.

---

## Expected Deliverables

Write all deliverables, but do not implement runtime code.

| Artifact | Target path | Required |
|---|---|---|
| Readiness doc | `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md` | yes |
| Proof/survey runner | `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p1.rb` | yes |
| Agent card update | `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md` | yes |
| Portfolio update | `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/portfolio-index.md` | yes, only after closure |

The proof runner may be evidence-only/static. It should verify source/docs facts
rather than execute real IO.

Suggested proof sections:

- A — `igniter-lang` source authority only; no old Ruby framework references
- B — RuntimeMachine load/evaluate/checkpoint/resume status from Ch7
- C — Effect Surface status from Ch12 and covenant
- D — `IO.*` capability normalization / opacity evidence
- E — existing IO capability fixtures parse/classify/typecheck surface
- F — experimental runtime quickstart disclaimers: not production/reference runtime
- G — prior lab IO families and closed surfaces census
- H — proposed IO Runtime route and refusal gates
- I — closed surfaces: no Rack/ORM/ActiveRecord/Rails authority

Target: at least 45 checks.

---

## Acceptance Criteria

P1 is closed only when:

- The doc clearly distinguishes `igniter-lang` from the old Ruby `igniter` gem.
- The doc rejects “pure HTTP wrapper only” as insufficient for microservice goals.
- The doc defines an IO Runtime route centered on Effect Surface + CapabilityExecutor + receipts.
- The doc keeps Rack/HTTP as substrate binding, not core architecture.
- The proof runner passes and verifies the key evidence anchors.
- The next card is explicit and narrow.

---

## Recommended Next Routes

If P1 confirms the expected route:

1. **LANG-IO-CAPABILITY-EXECUTOR-P1** — proposal for executor interface,
   capability passport, supported effect kinds, receipt/failure shape,
   fail-closed behavior.
2. **LAB-IGNITER-LANG-IO-RUNTIME-P2** — first executable mocked IO runtime slice,
   likely Storage read or HTTP outbound, with denial-as-data and receipt proof.
3. **LAB-IGNITER-LANG-MICROSERVICE-P1** — service runtime envelope only after P2:
   ingress → evaluate → execute effects → return response + receipts.

---

## Closed Surfaces For This Card

- No implementation changes.
- No Rack implementation.
- No Rails/ActiveRecord/ORM references as authority.
- No old Ruby `igniter` framework dependency.
- No real DB/network/file/queue/process/clock/random execution.
- No production runtime claim.
- No Reference Runtime claim.
- No public/stable API claim.
- No capability widening by config/env/global state.
- No generic ambient IO.

---

## Notes For Agent

The user explicitly corrected the route: do **not** settle for “external host owns
IO forever”. That is a half-measure. The goal is to find the honest next runtime
frontier where Igniter can own real IO semantics without hiding substrate reality.

The expected answer should feel like a runtime architecture readiness packet, not
a web framework proposal.
