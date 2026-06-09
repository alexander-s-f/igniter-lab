# Lab: Sidekiq Reimplementation Feasibility and Language Pressure Map (v0)

**Card:** LAB-SIDEKIQ-P1
**Track:** lab-sidekiq-reimplementation-feasibility-and-language-pressure-map-v0
**Category:** lang / EXPERIMENTAL / LAB-ONLY / RESEARCH
**Status:** RESEARCH
**Date:** 2026-06-09
**Authority:** lab-only — no canon claim, no production commitment, no Sidekiq compatibility claim

---

## Executive Summary

Sidekiq's core anatomy maps surprisingly well onto Igniter's contract model at the data-plane level: a job is a typed-input contract, a queue is an ordered collection of job descriptors, a receipt is the natural contract output, and retry/backoff policy is a finite/budgeted loop class (PROP-039). The analogy to the Rack track is direct and productive — the same pattern of beginning with a pure data-plane fixture (a static dispatch table) applies here. However, the production surfaces — Redis-backed queue storage, a runtime worker daemon, a scheduler with real clock authority, and concurrent worker pools — are all firmly closed for v0 lab work. A minimal Sidekiq-like system CAN be proved as a pure data-plane fixture today without any I/O, storage, or runtime workers, using exactly the same techniques that made LAB-RACK-P4 and LAB-RACK-P9 productive. The recommended first proof (P2) is the static job dispatch table as pure contracts — a direct Rack route-table analog — which will create meaningful language pressure on `call_contract` dispatch, the output type system, receipt shapes, and the modifier system.

---

## 1. Sidekiq Anatomy — Igniter Mapping

| Sidekiq Concept | Ruby Reality | Igniter Analog | Mapping Quality | Notes |
|---|---|---|---|---|
| **Job class** | Ruby class with `perform(*args)` method | `pure contract JobName { input ...; compute ...; output receipt: JobReceipt }` | STRONG | Job is a typed-input, typed-output contract. PROP-031 modifiers apply directly. |
| **Queue** | Redis list keyed by queue name | Ordered `Collection[JobDescriptor]` in the data-plane; Redis-backed list in production | MEDIUM (data-plane only) | Collection models a static queue snapshot; dynamic enqueue/dequeue requires storage capability (closed v0). |
| **Worker** | Ruby thread that pops a job from Redis and calls `perform` | Contract that accepts a `JobDescriptor` and dispatches via `call_contract` | MEDIUM | `call_contract` (LAB-RACK-P9) is the lab-only dispatcher; production worker loop requires ServiceLoop (PROP-037 territory). |
| **Retry policy** | `sidekiq_retry N` with exponential backoff; max attempts | `BudgetedLocalLoop` or `FuelBoundedRecursion` with `max_steps` (PROP-039) | STRONG | PROP-039 loop vocabulary maps directly: `max_steps` = max attempts; `decreases fuel` = attempt counter. |
| **Dead-letter queue (DLQ)** | Sidekiq::DeadSet in Redis; jobs exhausting retry budget | Typed failure output `DeadJobReceipt` produced when retry budget is exhausted | MEDIUM | The DLQ state itself (a persistent set) requires storage capability. The failure type and its data shape are pure data-plane. |
| **Scheduler** | Sidekiq::Scheduled::Poller; Redis sorted set with score = run_at | Time-triggered dispatch; PROP-037 progression source | WEAK | Clock authority and scheduler loop are both closed (PROP-037 / ServiceLoop). Only temporal_context (read-only) is available today. |
| **Idempotency key** | Custom `jid` (Sidekiq job ID); application-layer dedup | Named contract input `job_id: String`; idempotency declaration (PROP-035 ch12) | STRONG | Job ID is a first-class input field. Idempotency declaration makes dedup intent explicit at the contract boundary. |
| **Job receipt / execution trace** | Sidekiq server middleware collects timing, success/failure | Contract output `JobReceipt` with `job_id`, `queue`, `status`, `attempt`, `elapsed_ms` | STRONG | Receipts are natural contract outputs. Schema is fully expressible as pure contracts today. |
| **Middleware chain** | Server-side middleware wrapping `perform` in before/after hooks | `ContractRef`-threaded pipeline; static composition of `call_contract` chain | MEDIUM | Static composition via `call_contract` is lab-proven. Dynamic runtime middleware assembly is deferred (same gap as Rack middleware). |
| **Concurrency (N workers)** | `concurrency N` in `sidekiq.yml`; N threads | No analog today — ServiceLoop + thread pool = Stage 4+ / closed | WEAK | Concurrency requires runtime worker pool. Not expressible without ServiceLoop infrastructure and runtime threading model. |

---

## 2. Feasibility Matrix

Classification axes:
- **A** — Expressible TODAY as pure contracts (no VM needed)
- **B** — Expressible TODAY with lab VM (call_contract, OP_CALL, loop classes)
- **C** — Requires I/O capability / storage capability (Redis-like)
- **D** — Requires scheduler / clock / time authority
- **E** — Requires a runtime worker loop (ServiceLoop territory)
- **F** — Requires production infrastructure — must stay CLOSED

| Concept | A (Pure contracts) | B (Lab VM) | C (Storage) | D (Scheduler) | E (Worker loop) | F (Production closed) |
|---|---|---|---|---|---|---|
| Job contract (typed inputs/outputs) | YES — complete | YES | no | no | no | no |
| Job descriptor (enqueue record) | YES — pure data shape | YES | no | no | no | no |
| Queue snapshot (static Collection) | YES — Collection[JobDescriptor] | YES | PARTIAL (static only) | no | no | no |
| Queue dynamic enqueue/dequeue | no | no | YES — needs storage capability | no | no | YES |
| Worker dispatch (call_contract) | YES — dispatch table shape | YES — call_contract proven | no | no | no | no |
| Retry policy (budgeted loop) | YES — BudgetedLocalLoop shape | YES — PROP-039 VM proven | no | no | no | no |
| Dead-letter receipt (data shape) | YES — typed failure output | YES | no | no | no | no |
| Dead-letter queue (persistent) | no | no | YES — storage capability | no | no | YES |
| Scheduler (future jobs) | no | no | no | YES — clock authority | YES | YES |
| Idempotency key | YES — contract input field | YES | no | no | no | no |
| Job receipt / execution trace | YES — pure output shape | YES | no | no | no | no |
| Middleware chain (static) | YES — ContractRef shape | YES — call_contract chain | no | no | no | no |
| Middleware chain (dynamic assembly) | no | PARTIAL — no runtime assembly | no | no | no | YES |
| Concurrency (N workers) | no | no | no | no | YES | YES |
| Runtime worker daemon | no | no | no | no | YES | YES |
| Redis / queue storage | no | no | YES | no | no | YES |
| Job failure taxonomy (data shape) | YES — typed failure outputs | YES | no | no | no | no |

**Summary:** All data-plane shapes (job contracts, receipt schemas, retry policy shape, failure taxonomy, idempotency key field) are expressible today as pure contracts. Worker loop, scheduler, persistent queue storage, and concurrency are all closed for v0.

---

## 3. Language Pressure Map

For each Sidekiq concept that can be proved in lab, this section identifies the language pressure it creates — i.e., what it reveals about gaps or strengths in the current language model.

### 3.1 Modifier System (pure/effect/privileged) — PROP-031 / PROP-035

**Pressure source:** Job contracts that perform side effects (write to a database, send email) must be declared as `effect` or `privileged`. The modifier system is already experiment-pass (PROP-031). Sidekiq proves it under a new pattern:

- **Pure job:** computation-only (e.g., calculate a report, aggregate statistics) — maps to `pure contract`
- **Effect job:** writes to external system (e.g., send email, create database record) — maps to `effect contract` requiring capability declarations
- **Privileged job:** requires elevated authority (e.g., delete user data, charge credit card) — maps to `privileged contract`

**Pressure:** Call_contract v0 only dispatches pure callees. Sidekiq's common case (effect jobs) reveals that the pure-only constraint in call_contract is a real ceiling. This creates pressure to design effect-callee dispatch: how does the capability passport thread through the dispatch chain? This is the same gap LAB-RACK-P9 leaves open for non-pure callee dispatch.

### 3.2 Capability Passport (grants, scoped permissions) — PROP-035 / LAB-STDLIB-NET

**Pressure source:** A job that writes to a database or sends a network request must carry the appropriate capability grants. Sidekiq exposes this implicitly (any worker has full Ruby access). Igniter makes it explicit.

**Pressure:** A `StorageCapability` grant type (analogous to `IO.NetworkCapability` from LAB-STDLIB-NET-P2) is needed for queue read/write. This does not exist today. Proving that a job's capability grants can be scoped (read-only access to one queue, write access to one result store) would create direct pressure on the delegation algebra and the passport schema.

### 3.3 Managed Recursion / Loop Classes (PROP-039) — BudgetedLocalLoop

**Pressure source:** Sidekiq's retry policy is fundamentally a budgeted iteration: attempt the job up to N times, with exponential backoff between attempts. This maps directly to `BudgetedLocalLoop` with `max_steps: N` and a `decreases fuel` termination argument.

**Pressure:** PROP-039 loop vocabulary is experiment-pass at the compiler level and lab-proven in the VM. A retry loop fixture would:
1. Prove that `BudgetedLocalLoop` can model retry attempt count
2. Reveal whether the `lead` keyword (loop-carried binding from Gate 8) can express the attempt counter cleanly
3. Expose whether backoff delay (a time-dependent computation) requires scheduler authority or can be modeled as a pure arithmetic computation (e.g., `delay_ms = base_ms * (2 ^ attempt)`)

**Assessment:** Backoff as pure arithmetic is expressible today. The delay itself (sleeping) is closed (requires scheduler/clock authority). The distinction is important: the POLICY (how long to wait) is pure data; the ENFORCEMENT (actually waiting) is a runtime concern.

### 3.4 call_contract Dispatch (LAB-RACK-P9)

**Pressure source:** A Sidekiq-like worker dispatcher receives a `JobDescriptor` and routes to the appropriate job contract. This is exactly the `call_contract` dispatch pattern from LAB-RACK-P9.

**Pressure:**
- Proves call_contract dispatch generalizes beyond HTTP routing to any named-job dispatch pattern
- Reveals the single-output constraint: job contracts commonly return `JobReceipt` (success) OR `DeadJobReceipt` (failure) — a multi-output pattern that is currently closed in v0
- Creates pressure to design a `Result[JobReceipt, DeadJobReceipt]` return type for dispatched jobs

### 3.5 Output Type System (multi-output, receipt types)

**Pressure source:** Job execution has two fundamental outcomes: success (produces `JobReceipt`) and failure (produces typed failure + dead-letter descriptor). This is a tagged union / Result type at the dispatch boundary.

**Pressure:**
- call_contract v0 returns single output (Unknown type)
- Sidekiq reveals that the dispatch boundary needs `Result[T, E]` semantics
- `JobReceipt` schema is a concrete pressure test for the receipt/evidence output type design (PROP-034 OOF-M9)
- Multi-output callee dispatch (currently closed per LAB-RACK-P9 "still open") would need to be unblocked for a realistic job receipt model

### 3.6 Idempotency / Temporal Semantics

**Pressure source:** Sidekiq's job ID (`jid`) is its deduplication key. Jobs may be re-enqueued on failure and should not execute twice for the same logical operation. This maps to Igniter's `idempotency key job_id` declaration (ch12, PROP-035).

**Pressure:**
- Idempotency declaration is currently experiment-pass only (PROP-035 not yet enforced)
- A Sidekiq proof would be the first domain outside HTTP that explicitly needs idempotency semantics — making it a second pressure point for PROP-035 enforcement
- The `job_id` field as explicit contract input forces the idempotency key to appear at the type boundary, not buried in middleware

### 3.7 New: Storage Capability (queue read/write)

**Pressure source:** Sidekiq's queue is a Redis list. A storage capability would be needed for any realistic queue producer/consumer model.

**Pressure:**
- No `StorageCapability` type exists today (only `IO.Capability` for filesystem and `IO.NetworkCapability` for network)
- Lab work on a `StorageCapability` grant schema would follow the same pattern as LAB-STDLIB-NET-P2 (schema, delegation algebra, FFI surface)
- This is new territory — not a gap in existing capability types but a new capability class

### 3.8 New: Scheduler Capability (time-triggered execution)

**Pressure source:** Sidekiq::Scheduler runs jobs at a future time (cron-like or delay-based). This requires a time authority that can trigger contract execution.

**Pressure:**
- PROP-037 (External Progression / Service Liveness) covers `clock.every` bindings but is proposal-only
- A scheduler capability would require: (a) a clock/time authority, (b) a trigger mechanism that starts a job execution, (c) a temporal_context injection at the correct `run_at` time
- This is strongly coupled to ServiceLoop infrastructure — cannot be proved in isolation without ServiceLoop
- Verdict: scheduler capability creates PROP-037 pressure but is CLOSED for v0 lab

---

## 4. Rack ↔ Sidekiq Analogy Table

This table makes the structural analogy explicit. The Rack track's progression pattern is the direct template for the Sidekiq track.

| Rack Concept | Rack Track Card | Sidekiq Analog | Notes |
|---|---|---|---|
| HTTP Request `HttpRequest` record | LAB-RACK-P2 | `JobDescriptor` record (job_id, queue, class_name, args, attempt, enqueued_at) | Both are typed-input schemas for the dispatch boundary |
| HTTP Response `HttpResponse` record | LAB-RACK-P2 | `JobReceipt` record (job_id, status, attempt, elapsed_ms, output) | Both are typed outputs from the dispatch handler |
| 5-route dispatch table (pure data) | LAB-RACK-P4 | N-job dispatch table (JobDispatcher maps class_name → contract) | Same fixture pattern: static table, pure contracts |
| HTTP middleware chain | LAB-RACK-P2 / P9 | Job pipeline (before/after hooks) | Both use ContractRef-threaded composition; dynamic assembly deferred in both |
| HTTP status code | LAB-RACK-P4 | Job status (enqueued / running / succeeded / failed / dead) | Both are integer/enum outputs from dispatch |
| Request ID (`request_id`) | LAB-RACK-P2 / P9 | Job ID (`job_id`) / idempotency key | Both are stable string identifiers for deduplication and audit |
| Retry-After header (no direct analog) | — | Retry policy (BudgetedLocalLoop, max_steps, backoff) | Sidekiq has a richer retry model; PROP-039 maps directly |
| 404/500 failure taxonomy | LAB-RACK-P2 | Job failure taxonomy (transient, permanent, dead) | Both require typed failure outputs |
| Capability passport (HTTP network grants) | LAB-STDLIB-NET / PROP-035 | Job capability passport (storage, network, compute grants) | Same delegation algebra; new StorageCapability type needed |
| ContractRef middleware | LAB-RACK-P8 design / P9 | ContractRef job pipeline | Same mechanism; same v0 constraint (pure-callee-only) |
| `call_contract` named dispatch | LAB-RACK-P9 | `call_contract` job dispatch (JobDispatcher → JobHandler) | Identical mechanism — dispatching by job class name |
| Route table (String path → handler) | LAB-RACK-P4 | Queue dispatch table (String class_name → job contract) | Same data-plane pattern |
| HTTP auth failure (403) | LAB-RACK-P2 design | Job authority failure (insufficient grants) | Both are typed failures at the Effect Surface boundary |
| `--entry <name>` VM entrypoint | LAB-RACK-P7 | Same mechanism — select which job contract to test | Reuses P7 mechanism directly |

**Key finding:** The structural parallel is deep. Every Rack track card has a direct Sidekiq analog. The Rack track's progression from data shapes → route dispatch table → call_contract dispatch → middleware design is the exact template for Sidekiq: data shapes → job dispatch table → call_contract job dispatch → pipeline design.

---

## 5. Pure Data-Plane Feasibility Analysis

**Question:** Can a minimal Sidekiq-like system be proved as a pure data-plane fixture first — like Rack's 5-route dispatch table — without any I/O, storage, or runtime workers?

**Answer: Yes. Concretely.**

The Rack track proved that a 5-route dispatch table with pure contracts — no network, no storage, no service loop — was sufficient to:
1. Prove the dispatch mechanism works (call_contract routing by name)
2. Prove the output type contract (status code per route)
3. Prove fail-closed behavior (unknown route → 404, wrong method → 405)
4. Create language pressure on all the relevant layers

The Sidekiq analog is a static job dispatch table. Concretely:

```
-- Illustrative fixture shape (not canon syntax)
-- module Sidekiq.Lab.JobDispatch

-- Job descriptors (input shapes)
pure contract ProcessOrderJob {
  input job_id: String
  input order_id: Integer
  input retry_attempt: Integer
  compute result = order_id * 2         -- stub computation
  output receipt: ...                   -- JobReceipt shape
}

pure contract SendEmailJob {
  input job_id: String
  input recipient: String
  input retry_attempt: Integer
  compute status = 200                  -- stub: email "sent"
  output receipt: ...
}

pure contract JobDispatcher {
  input job_class: String
  input job_id: String
  input payload: Integer
  input retry_attempt: Integer
  compute result = call_contract(job_class, job_id, payload, retry_attempt)
  output result: ...
}
```

This fixture would prove:
- Dispatch by `job_class` name to a named job contract (via call_contract)
- Happy path: correct job class → job executes → receipt returned
- Fail-closed: unknown job class → "no contract named" error
- Arity enforcement: wrong argument count → arity error

What this explicitly does NOT prove:
- Redis or any real queue storage
- Async execution or queueing
- Retry loop execution (separate fixture needed)
- Middleware pipeline execution
- Any production Sidekiq behavior

The pure data-plane fixture is the correct starting point. It is achievable with exactly the existing VM and compiler without any new infrastructure.

---

## 6. call_contract Applicability

**Should `call_contract` (LAB-RACK-P9) be used as a temporary lab-only job dispatch mechanism?**

**Yes, with explicit constraints understood.**

### What call_contract proves in a Sidekiq context

1. **Job dispatch by class name** — `call_contract("ProcessOrderJob", job_id, payload)` is structurally identical to dispatching Sidekiq's `ProcessOrderJob.perform_async` — a string-named job class resolved at dispatch time. This proves the dispatch table pattern generalizes to any named-contract domain.

2. **Typed inputs at dispatch boundary** — positional argument mapping to named contract inputs enforces the job's input schema. Wrong arity → fail closed. This is stronger than Sidekiq's `perform(*args)` which accepts any arguments without checking.

3. **Pure-callee constraint creates useful pressure** — because only pure contracts may be dispatched in v0, any fixture that tries to dispatch an effect job (the common Sidekiq case) will be rejected. This is HONEST: it reveals exactly where the language boundary is. The pressure it creates on effect-callee dispatch design is valuable.

4. **Cycle detection and depth limit** — the A→B→A cycle detection and MAX_CALL_DEPTH=8 are directly relevant to job chaining (a job that enqueues another job). The lab constraint prevents infinite job chains, which is correct behavior.

### What call_contract does NOT prove

1. **Async execution** — `call_contract` is synchronous. It returns the result immediately in the same execution frame. Sidekiq's fundamental characteristic is that jobs execute asynchronously on worker threads. This gap cannot be proved with call_contract.

2. **Queue semantics** — call_contract has no queue. There is no enqueue, no dequeue, no ordering guarantee, no persistence. It is pure in-process dispatch.

3. **Retry loop** — call_contract will not retry a failed job. A retry fixture needs a separate `BudgetedLocalLoop` wrapping the dispatch, not `call_contract` alone.

4. **Effect job dispatch** — call_contract v0 enforces pure-callee-only. Real Sidekiq jobs almost always have side effects. This is a hard constraint that a v0 fixture must acknowledge explicitly.

5. **Worker concurrency** — there is no concurrency model in call_contract. Each dispatch is a single-threaded sequential call.

### Verdict

`call_contract` is the correct lab-only mechanism for the job dispatch proof. It proves the structural pattern (named dispatch, typed inputs, fail-closed errors) without claiming any of the runtime characteristics that Sidekiq actually depends on. This is the right scope for P2.

---

## 7. Closed Surface Inventory

The following surfaces MUST remain closed for all v0 lab work on the Sidekiq track:

| Surface | Why closed | Authority needed to open |
|---|---|---|
| **Redis / external queue storage** | No StorageCapability type; no queue FFI; no persistence layer | New lab track: LAB-STDLIB-STORAGE-P1; StorageCapability schema and delegation algebra |
| **Runtime worker daemon / process pool** | ServiceLoop (PROP-037) is proposal-only; no runtime scheduler; no thread pool model | PROP-037 full implementation + ServiceLoop authorization (Stage 4+) |
| **Network I/O (general)** | Already closed from Rack track; IO.NetworkCapability is lab-proven schema only | PROP-037 + runtime injection (Phase 2) |
| **ServiceLoop / alive-by-liveness loop** | No parser, TypeChecker, or runtime support; Stage 4 deferred | PROP-039+ Stage 4 + separate ServiceLoop authorization |
| **Clock / time authority (real)** | temporal_context is read-only pass-through; real clock triggers require PROP-037 progression sources | PROP-037 progression source binding for clock.every / scheduler |
| **Sidekiq compatibility claim** | Sidekiq is a specific Ruby gem with a documented API. Igniter lab proofs do not constitute compatibility with that API or any guarantee of behavioral equivalence | Explicitly forbidden — not a governance gate, a permanent constraint |
| **Production claim** | Lab fixtures are proofs of language expressibility, not production-ready implementations | Explicitly forbidden for all lab cards |
| **Canon grammar authority** | call_contract, ContractRef dispatch, StorageCapability, JobReceipt — none of these may enter canon without a PROP + governance review | Formal PROP authorship with governance gate |
| **Concurrency / thread model** | No concurrency model exists in Igniter today at any stage | New PROP required; out of scope for entire current roadmap |
| **Job scheduling (cron-like)** | Requires clock authority + ServiceLoop + scheduler infrastructure | PROP-037 + ServiceLoop + scheduler design (Stage 4+) |

---

## 8. P2 Recommendation

**Recommendation: (a) Static job dispatch table as pure contracts — the Rack route-table analog.**

### Rationale for selection over alternatives

| Option | Assessment |
|---|---|
| (a) Static job dispatch table as pure contracts | RECOMMENDED — direct Rack analog, proven pattern, achievable with existing VM |
| (b) Job receipt schema and failure taxonomy | Valuable but lower impact — pure data shapes without dispatch prove nothing new beyond existing IR evidence |
| (c) Retry/backoff policy as BudgetedLocalLoop | High value but second in priority — depends on having a job to retry; better as P3 after dispatch table is proved |
| (d) Lab-only call_contract worker invocation proof | This IS the dispatch table option — (a) and (d) converge on the same fixture |
| (e) Hold — surface too runtime-heavy | Not justified — data-plane is clearly reachable today |

### P2 fixture specification

**Fixture file:** `igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig`

**Contracts to define:**

| Contract | Role | Inputs | Output | Proves |
|---|---|---|---|---|
| `ProcessOrderJob` | pure callee | `job_id: String`, `order_id: Integer`, `attempt: Integer` | `result: Integer` | Simple pure job with integer output |
| `ComputeReportJob` | pure callee | `job_id: String`, `report_type: String`, `period: Integer` | `result: Integer` | String-input job, proves dispatch with text input |
| `ValidatePaymentJob` | pure callee | `job_id: String`, `amount: Integer`, `currency: String` | `result: Integer` | Two non-id inputs, proves arity with multiple args |
| `JobDispatcher` | dispatcher | `job_class: String`, `job_id: String`, `arg1: Integer` | `result: Integer` | Dispatches to named job contract via call_contract |
| `BadJobAttempt` | fail-closed | `job_id: String` | `result: Integer` | Self-invocation attempt — cycle detection |

**VM smoke tests to prove:**

| Test ID | Description | Expected |
|---|---|---|
| SJOB-HAPPY-1 | JobDispatcher("ProcessOrderJob", "jid-1", 42) → 84 | result = 84 |
| SJOB-HAPPY-2 | JobDispatcher("ComputeReportJob", "jid-2", ...) via --entry with String input | correct result |
| SJOB-HAPPY-3 | JobDispatcher("ValidatePaymentJob", "jid-3", 100) | correct result |
| SJOB-FC-1 | Unknown job class → "no contract named 'UnknownJob' in igapp" | error |
| SJOB-FC-2 | Arity mismatch → "contract 'ProcessOrderJob' expects N inputs, got M" | error |
| SJOB-FC-3 | Self-dispatch cycle → "dispatch cycle detected" | error |
| SJOB-FC-4 | Effect callee dispatch → "not pure (modifier: effect)" | error (separate fixture) |
| SJOB-GAP-1 | No Redis, no queue, no async execution confirmed absent | gap packet field |
| SJOB-GAP-2 | No retry loop in this fixture (P3 candidate) | gap packet field |

**Language pressure created by P2:**

1. **call_contract generalizes to non-HTTP domains** — proves the dispatch table pattern is domain-independent
2. **Pure-callee constraint exposed in job context** — effect job dispatch becomes the explicit P3 design question
3. **Output type Unknown flows through job result** — same TypeChecker gap as P9; creates pressure for compile-time output type verification
4. **Job receipt shape** — even a stub Integer output in P2 will reveal the gap between "integer result" and "structured receipt" — creating pressure for a `JobReceipt` record type in P3
5. **gap packet pattern** — documents what is NOT proved (async, queue, retry) explicitly in machine-readable form

**What P2 explicitly does NOT prove or claim:**

- Redis or any queue storage
- Asynchronous job execution
- Retry logic (P3 candidate)
- Middleware pipeline (P4 candidate)
- Effect job dispatch (P3 design question)
- Any production Sidekiq behavior or API compatibility
- Canon grammar for job contracts
- Stable API surface for call_contract

### P3 candidates (not in P2 scope)

After P2 closes the dispatch table:

- **P3a:** Job receipt schema — define `JobReceipt` as a typed output record; prove the dispatcher returns a structured receipt not a raw integer
- **P3b:** Retry policy as BudgetedLocalLoop — prove that attempt counter + max_attempts maps to `max_steps` in a BudgetedLocalLoop; backoff delta as pure arithmetic
- **P3c:** Effect callee design — design (not implement) how capability grants would thread through call_contract for effect job dispatch

---

## 9. Authority Boundary

**This document is research evidence only. It does not:**
- Authorize implementation of any Sidekiq-like runtime
- Constitute a PROP for canon grammar changes
- Claim Sidekiq compatibility or behavioral equivalence
- Authorize StorageCapability, ServiceLoop, or scheduler infrastructure
- Grant any lab card the authority to modify compiler, VM, or canon files beyond what is already authorized by existing lab tracks

**Two-track model:**
- `igniter-lang` (canon): all grammar changes require a formal PROP + governance gate
- `igniter-lab` (lab): fixture proofs, research docs, and handoff cards only

**call_contract is lab-only.** It must not be cited as a canon Igniter language feature, a stable stdlib function, or a production dispatch mechanism.

**Sidekiq is a registered trademark of Contributed Systems, LLC.** This research uses Sidekiq as a reference architecture for language pressure analysis only. No claim of compatibility, endorsement, or API equivalence is made.
