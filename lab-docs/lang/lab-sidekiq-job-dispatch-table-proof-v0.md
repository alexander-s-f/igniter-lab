# LAB-SIDEKIQ-P2: Static Job Dispatch Table — Proof v0

**Track:** lab-sidekiq-static-job-dispatch-table-proof-v0
**Status:** PROVED — 54/54 PASS
**Date:** 2026-06-09
**Authority:** lab-only — no production claim, no Sidekiq compatibility claim, no stable API

---

## Summary

Proves that Igniter's `call_contract` dispatch mechanism (LAB-RACK-P9) generalizes cleanly to a
static job dispatch table pattern structurally analogous to Sidekiq's job router. Five pure
contracts compile in a single igapp; JobDispatcher routes to named job contracts by `job_class`
string at VM runtime. All fail-closed policies (unknown class, arity mismatch, effect callee,
cycle detection, depth limit) hold without modification from P9. No new compiler, VM, or stdlib
changes were required.

---

## Fixture

`igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig`

Module: `Sidekiq.Lab.JobDispatch`

Five contracts:

| Contract | Inputs | Compute | Output |
|---|---|---|---|
| `ProcessOrderJob` | job_id:String, order_id:Integer, attempt:Integer | order_id + order_id | result:Integer |
| `ComputeReportJob` | job_id:String, period:Integer, code:Integer | period * 10 | result:Integer |
| `ValidatePaymentJob` | job_id:String, amount:Integer, attempt:Integer | amount + attempt | result:Integer |
| `JobDispatcher` | job_class:String, job_id:String, arg1:Integer, arg2:Integer | call_contract(job_class, job_id, arg1, arg2) | result:Integer |
| `SelfDispatch` | job_id:String, arg1:Integer, arg2:Integer | call_contract("SelfDispatch", job_id, arg1, arg2) | result:Integer |

**Uniform arity design:** All job contracts share arity `(job_id: String, arg1: Integer, arg2: Integer) → Integer`
so that `JobDispatcher` can route uniformly via positional mapping. This is a deliberate simplification
for v0; non-uniform arity requires a type-verified dispatch layer (P10/P11 territory).

---

## Proof File

`igniter-view-engine/proofs/verify_sidekiq_p2_job_dispatch.rb`

### Result: 54/54 PASS

| Section | Checks | Result |
|---|---|---|
| SJOB-COMPILE | 6 | ✅ 6/6 |
| SJOB-SOURCE | 6 | ✅ 6/6 |
| SJOB-HAPPY | 7 | ✅ 7/7 |
| SJOB-FC | 18 | ✅ 18/18 |
| SJOB-REG | 5 | ✅ 5/5 |
| SJOB-CLOSED | 6 | ✅ 6/6 |
| SJOB-GAP | 6 | ✅ 6/6 |

---

## Check Inventory

### SJOB-COMPILE (6)

- SJOB-COMPILE-01: fixture compiles with `status=ok`
- SJOB-COMPILE-02: all 5 contracts present in igapp
- SJOB-COMPILE-03: no diagnostics in job dispatch fixture
- SJOB-COMPILE-04: all stages ok (parse, classify, typecheck, emit, assemble)
- SJOB-COMPILE-05: `effect_job` auxiliary fixture compiles ok (effect callee accepted by compiler)
- SJOB-COMPILE-06: `depth_chain` auxiliary fixture compiles ok (depth caught at VM, not compile time)

### SJOB-SOURCE (6)

- SJOB-SOURCE-01: `vm.rs` contains `DispatchEntry` struct
- SJOB-SOURCE-02: `vm.rs` contains `call_contract` dispatch arm
- SJOB-SOURCE-03: `vm.rs` contains `__call_chain__` cycle detection
- SJOB-SOURCE-04: `vm.rs` contains `MAX_CALL_DEPTH`
- SJOB-SOURCE-05: `compiler.rs` contains `build_dispatch_entry`
- SJOB-SOURCE-06: `vm.rs` contains `LAB-RACK-P9` annotation (P9 mechanism reused unchanged)

### SJOB-HAPPY (7)

- SJOB-HAPPY-01: `ProcessOrderJob` via `JobDispatcher(order_id=21)` → 42
- SJOB-HAPPY-02: `ComputeReportJob` via `JobDispatcher(period=5)` → 50
- SJOB-HAPPY-03: `ComputeReportJob` via `JobDispatcher(period=3)` → 30
- SJOB-HAPPY-04: `ValidatePaymentJob` via `JobDispatcher(amount=100, attempt=1)` → 101
- SJOB-HAPPY-05: `ValidatePaymentJob` via `JobDispatcher(amount=0, attempt=0)` → 0
- SJOB-HAPPY-06: `ProcessOrderJob` executed directly (bypassing dispatcher) → 14
- SJOB-HAPPY-07: all 3 job classes dispatch without error

### SJOB-FC (18 — 6 groups × 3 sub-checks)

**FC-01: unknown job class (3)**
- FC-01a: `status=error`
- FC-01b: error mentions `"no contract named"`
- FC-01c: error lists available job contracts

**FC-02: arity mismatch (3)**
- FC-02a: `status=error`
- FC-02b: error mentions `"expects"` and `"got"`
- FC-02c: error names the callee contract

**FC-03: non-string `job_class` → compile-time rejection (3)**
- FC-03a: compiler `status=oof`
- FC-03b: `OOF-TY0` diagnostic present
- FC-03c: diagnostic mentions `"String"`

**FC-04: effect callee (3)**
- FC-04a: `status=error`
- FC-04b: error mentions `"not pure"`
- FC-04c: error names the job contract and modifier

**FC-05: self-dispatch cycle (3)**
- FC-05a: `status=error`
- FC-05b: error mentions `"cycle detected"`
- FC-05c: error mentions `SelfDispatch` twice (`SelfDispatch -> SelfDispatch`)

**FC-06: depth > 8 (3)**
- FC-06a: `status=error`
- FC-06b: error mentions `"max call depth"`
- FC-06c: error states the limit (8)

### SJOB-REG (5)

Regression against LAB-RACK-P9 fixture (`multi_contract_caller.ig`):

- SJOB-REG-01: `multi_contract_caller.ig` compiles ok
- SJOB-REG-02: `CallerDoubler`/`CallerSmall`/`CallerGate` all present
- SJOB-REG-03: P9 `CallerDoubler(n=10)` → 21 (P9 unchanged)
- SJOB-REG-04: P9 `CallerSmall(n=50)` → true
- SJOB-REG-05: P9 `CallerGate(GET, /)` → 200

### SJOB-CLOSED (6)

- SJOB-CLOSED-01: no TCP/UDP socket use in proof source
- SJOB-CLOSED-02: no network I/O calls in proof source
- SJOB-CLOSED-03: no Redis connection in proof source
- SJOB-CLOSED-04: no `ServiceLoop` require or live invocation in proof source
- SJOB-CLOSED-05: no production API or Sidekiq compatibility claims
- SJOB-CLOSED-06: `call_contract` is lab-only — proof makes no canon claim

### SJOB-GAP (6)

Gap packet (machine-readable JSON in proof source):

- SJOB-GAP-01: `closed_by_p2` includes `job_dispatch_table`
- SJOB-GAP-02: `v0_policy.pure_callee_only` is `enforced`
- SJOB-GAP-03: `still_open` contains `async_execution`
- SJOB-GAP-04: `still_open` contains `queue_storage`
- SJOB-GAP-05: `still_open` contains `retry_policy`
- SJOB-GAP-06: `sidekiq_compatibility` is `permanently_closed`

---

## Mechanism Reuse

LAB-SIDEKIQ-P2 reuses the LAB-RACK-P9 `call_contract` mechanism without modification:

| Component | Source | Reused by P2 |
|---|---|---|
| `DispatchEntry` struct | `igniter-vm/src/vm.rs` | ✅ unchanged |
| `call_contract` VM dispatch arm | `igniter-vm/src/vm.rs` | ✅ unchanged |
| `__call_chain__` cycle detection | `igniter-vm/src/vm.rs` | ✅ unchanged |
| `MAX_CALL_DEPTH = 8` | `igniter-vm/src/vm.rs` | ✅ unchanged |
| `build_dispatch_entry` | `igniter-compiler/src/compiler.rs` | ✅ unchanged |
| OOF-P1 narrowing fix | `igniter-compiler/src/typechecker.rs` | ✅ unchanged |
| Unknown output compatibility | `igniter-compiler/src/typechecker.rs` | ✅ unchanged |

The only new artifact is the fixture and proof. Zero compiler/VM churn.

---

## Bugs Found and Fixed During Proof Run

### Bug 1 — `compile_fixture` encoding failure

**Symptom:** SJOB-COMPILE-* and SJOB-REG-01 failed with `JSON::ParserError` or
`Encoding::InvalidByteSequenceError`.

**Cause:** Compiler liveness calibration output contains `×` (U+00D7, multiplication sign),
e.g. `"limit=1000 is 5× headroom"`. Ruby's backtick operator returns `ASCII-8BIT`; `JSON.parse`
raises on the invalid byte sequence.

**Fix:** Added `.force_encoding('UTF-8')` to `compile_fixture` helper in
`verify_sidekiq_p2_job_dispatch.rb`.

### Bug 2 — SJOB-CLOSED-04 false positive

**Symptom:** `SJOB-CLOSED-04` failed because the gap packet JSON in the proof source legitimately
contains `"ServiceLoop"` as a closed-surface documentation string.

**Cause:** The check used `SOURCE.include?('ServiceLoop')` which matched the documentation.

**Fix:** Changed to scan only for actual invocation/require patterns:
`require 'service_loop'`, `.new`, `.start`, `.run`.

---

## TypeChecker Constraints (inherited from P9)

The P2 fixture relies on two TypeChecker fixes made in LAB-RACK-P9:

**OOF-P1 narrowing** (`typechecker.rs`):
OOF-P1 fires only when a symbol is absent from both `symbol_types` and `olap_env`.
A symbol declared with `Unknown` type (as `call_contract` result) does not trigger OOF-P1.

**Unknown output compatibility** (`typechecker.rs`):
When `call_contract` returns a value, its output type is `Unknown` at compile time (callee output
is not verifiable in v0). The type checker allows `Unknown` actual type to pass any declared
output type check, suppressing a spurious OOF-TY0.

---

## Sidekiq Analogy

| Sidekiq concept | Igniter equivalent (P2) | Status |
|---|---|---|
| Job class | Pure contract | ✅ proved |
| Job router / dispatch table | `JobDispatcher` + `call_contract` | ✅ proved |
| Job class string | `job_class: String` input | ✅ proved |
| Unknown job class → dead letter | fail-closed: no contract error | ✅ proved |
| Wrong argument count | fail-closed: arity mismatch error | ✅ proved |
| Effect job dispatch | fail-closed: not-pure error | ✅ proved |
| Retry policy | BudgetedLocalLoop | ❌ P3 candidate |
| Job receipt / result schema | Structured output record | ❌ P3 candidate |
| Queue storage | StorageCapability | ❌ permanently closed in v0 |
| Worker daemon | ServiceLoop (PROP-037) | ❌ Stage 4+ only |
| Scheduler / cron | Clock authority | ❌ permanently closed in v0 |
| Sidekiq compatibility | — | ❌ permanently forbidden |

---

## Closed Surfaces

The following surfaces are closed for this track and must not be opened without explicit
authorization:

| Surface | Reason |
|---|---|
| Redis / external queue storage | No StorageCapability; no queue FFI |
| Runtime worker daemon | ServiceLoop is Stage 4 proposal-only |
| Network I/O | Closed from Rack track |
| ServiceLoop invocation | No compiler/runtime support |
| Clock / real scheduling | temporal_context read-only; PROP-037 required |
| Sidekiq compatibility claim | Permanently forbidden — not a governance gate |
| Production claim | Permanently forbidden for all lab cards |
| Canon grammar authority | Requires formal PROP + governance gate |
| `call_contract` canon claim | lab-only; no stable API surface |

---

## Still Open (Gap Packet Summary)

- **async_execution**: no async/background execution in v0 — all dispatch is synchronous
- **queue_storage**: no persistent job queue — `call_contract` is in-process only
- **retry_policy**: no retry loop — P3 candidate via BudgetedLocalLoop
- **effect_dispatch**: effect callees blocked in v0 — requires P10/P11 output typing work
- **job_receipt_schema**: output is raw Integer stub — P3 candidate for structured receipt
- **non_uniform_arity**: all jobs share same arity in v0 — type-verified dispatch is P10/P11 territory
- **sidekiq_compatibility**: permanently closed — not a governance gate

---

## P3 Candidates

Per user guidance after P2 acceptance:

**P3a — JobReceipt schema:** Replace raw Integer output with a structured result record
(e.g. `{ status: String, value: Integer, job_id: String }`). Tests multi-field output from
`call_contract` callee contracts.

**P3b — BudgetedLocalLoop retry policy:** Prove that a PROP-039 BudgetedLocalLoop with
`decreases attempt` functions as a retry counter for a job contract. Pure; no scheduler/clock
authority required.

Effect-callee dispatch deferred until P10/P11 clarify `call_contract` output typing boundaries.

---

## Rack / Sidekiq Analogy Table (Track Structure)

| Rack card | Sidekiq card | Proves |
|---|---|---|
| LAB-RACK-P4 (5-route dispatch) | LAB-SIDEKIQ-P2 (3-job dispatch) | Named dispatch by string |
| LAB-RACK-P9 (call_contract mechanism) | LAB-SIDEKIQ-P2 (reuse) | P9 generalizes to any domain |
| LAB-RACK-P7 (named entrypoint) | LAB-SIDEKIQ-P2 (JobDispatcher entry) | Entrypoint selection |
| LAB-RACK-P8 (design preflight) | LAB-SIDEKIQ-P1 (feasibility) | Feasibility before proof |
