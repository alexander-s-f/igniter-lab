# LAB-SIDEKIQ-P1: Sidekiq Reimplementation Feasibility and Language Pressure Map

**Status:** RESEARCH COMPLETE
**Track:** lab-sidekiq-reimplementation-feasibility-and-language-pressure-map-v0
**Category:** lang / EXPERIMENTAL / LAB-ONLY / RESEARCH
**Date:** 2026-06-09
**Doc:** `lab-docs/lang/lab-sidekiq-reimplementation-feasibility-and-language-pressure-map-v0.md`

---

## Summary

Sidekiq's core anatomy maps directly onto Igniter's contract model at the data-plane level. The job-as-contract / receipt-as-output / retry-as-budgeted-loop pattern is expressible today using existing lab-proven primitives (pure contracts, PROP-039 loop classes, call_contract from LAB-RACK-P9). The analogy to the Rack track is structural and complete: every Rack track card has a direct Sidekiq equivalent, and the Rack track's progression template (data shapes → dispatch table → call_contract → pipeline design) applies without modification. All runtime surfaces — Redis queue storage, worker daemon, scheduler, and concurrency — are firmly closed for v0 and must remain closed. A minimal pure data-plane proof is achievable today using the same fixture pattern as LAB-RACK-P4/P9.

---

## Key Findings

- **Job contract maps strongly to pure contract.** Typed inputs, typed outputs, PROP-031 modifiers all apply directly. This is the strongest mapping in the entire anatomy.
- **call_contract (LAB-RACK-P9) is the correct lab-only job dispatch mechanism.** Dispatch by job class name (`call_contract("ProcessOrderJob", job_id, payload)`) is structurally identical to HTTP route dispatch by path string. The mechanism generalizes cleanly to any named-contract domain.
- **Retry policy maps to BudgetedLocalLoop (PROP-039).** The `max_steps` field = max attempts. The `decreases fuel` argument = attempt counter. Backoff delay as arithmetic is pure; actual delay enforcement is closed (scheduler/clock authority required).
- **Pure data-plane fixture is achievable today.** A static job dispatch table (JobDispatcher → call_contract → named job contract) needs no new VM, compiler, or stdlib changes. It reuses the call_contract mechanism from P9 directly.
- **The Rack ↔ Sidekiq analogy is deep and productive.** Route table ↔ job dispatch table; request/response ↔ job descriptor/receipt; HTTP middleware ↔ job pipeline; request ID ↔ job ID; retry/backoff ↔ BudgetedLocalLoop; failure taxonomy ↔ dead-letter taxonomy; capability passport ↔ job effect permissions.
- **Two new capability types emerge as pressure.** `StorageCapability` (queue read/write) and `SchedulerCapability` (time-triggered execution) do not exist today. Both follow the pattern of `IO.NetworkCapability` from LAB-STDLIB-NET-P2 but are in new territory.
- **Effect callee dispatch is the key constraint.** The pure-callee-only rule in call_contract v0 means real Sidekiq jobs (which almost always have side effects) cannot be dispatched in v0. This is honest and creates productive design pressure.

---

## Feasibility Verdict

A Sidekiq-like system is **feasible as a pure data-plane lab proof** using existing Igniter primitives. The dispatch table pattern (P2 target), retry policy shape (P3 candidate), job receipt schema, and failure taxonomy are all expressible today without any new infrastructure. The runtime layer — Redis, worker daemon, scheduler, concurrency — is not feasible at any stage of current lab work and must remain closed.

---

## Language Pressure Verdict

This track creates useful and non-redundant language pressure on: (1) effect-callee dispatch design — the pure-callee-only constraint hits immediately in job context, (2) multi-output / Result type at dispatch boundary — job success/failure requires tagged union output, (3) new StorageCapability type analogous to NetworkCapability, (4) PROP-035 idempotency enforcement in a second domain beyond HTTP, and (5) PROP-039 BudgetedLocalLoop as a retry policy primitive. The pressure is complementary to (not redundant with) the Rack track.

---

## Closed Surfaces

The following surfaces are closed for all v0 lab work on this track and must not be opened without explicit authorization:

| Surface | Closed reason |
|---|---|
| Redis / external queue storage | No StorageCapability; no queue FFI; no persistence layer |
| Runtime worker daemon / process pool | ServiceLoop (PROP-037) is proposal-only; Stage 4+ |
| Network I/O | Already closed from Rack track |
| ServiceLoop / alive-by-liveness loop | No compiler/runtime support; Stage 4 deferred |
| Clock / time authority (real scheduling) | temporal_context is read-only; PROP-037 required |
| Sidekiq compatibility claim | Permanently forbidden — not a governance gate |
| Production claim | Permanently forbidden for all lab cards |
| Canon grammar authority | Requires formal PROP + governance gate |
| Concurrency / thread model | No concurrency model at any current stage |

---

## P2 Recommendation

**Proceed with P2: Static job dispatch table as pure contracts.**

This is the direct analog of LAB-RACK-P4 (5-route dispatch table). The fixture defines three to five named job contracts (ProcessOrderJob, ComputeReportJob, ValidatePaymentJob) and a JobDispatcher contract that routes via `call_contract(job_class, ...)`. The proof verifies happy-path dispatch, all fail-closed cases (unknown job class, arity mismatch, cycle detection, effect callee rejection), and emits a gap packet documenting what is NOT proved (async, queue, retry).

**Files to create for P2:**
- `igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig`
- `igniter-view-engine/proofs/verify_sidekiq_p2_job_dispatch.rb`
- `lab-docs/lang/lab-sidekiq-job-dispatch-table-proof-v0.md`

**No compiler, VM, or canon changes are required for P2.**

---

## Next Card

**LAB-SIDEKIQ-P2** — Static job dispatch table proof (implement P2 as described above)

P3 candidates after P2 closes:
- P3a: JobReceipt schema — structured output record replacing raw integer stub
- P3b: BudgetedLocalLoop retry policy proof — attempt counter + max_attempts
- P3c: Effect callee design preflight — how capability grants thread through dispatch
