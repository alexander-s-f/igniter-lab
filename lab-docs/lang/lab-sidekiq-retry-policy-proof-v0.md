# LAB-SIDEKIQ-P3: BudgetedLocalLoop Retry Policy Proof — v0

**Track:** `lab-sidekiq-budgeted-local-loop-retry-policy-proof-v0`
**Status:** CLOSED / PROVED — 43/43 PASS
**Date:** 2026-06-09
**Depends on:** LAB-SIDEKIQ-P2, LAB-RACK-P9, PROP-039

---

## 1. Goal

Prove that a Sidekiq-like retry policy can be modeled as a pure BudgetedLocalLoop
(PROP-039) over an explicit attempt counter with a static `max_steps` budget — with
no Redis, no worker daemon, no scheduler, no real clock access, no effect-callee
dispatch, and no Sidekiq compatibility claim.

---

## 2. Fixture Design

**File:** `igniter-view-engine/fixtures/sidekiq_core/retry_policy.ig`
**Module:** `Sidekiq.Lab.RetryPolicy`

Four contracts:

| Contract | Role | Proves |
|---|---|---|
| `StubJob` | Minimal dispatchable pure job | P9 dispatch target in retry context |
| `RetryPolicy` | `budget_remaining = max_attempts - attempt` | Retry budget is pure Integer arithmetic |
| `RetrySimulator` | BudgetedLocalLoop, `max_steps: 5`, accumulates `total_attempts` | Loop terminates at budget; fuel exhaustion verifiable |
| `RetryWithDispatch` | `call_contract(job_class, ...)` + budget arithmetic | Dispatch and budget arithmetic are composable |

### RetryPolicy contract

```igniter
pure contract RetryPolicy {
  input  attempt       : Integer
  input  max_attempts  : Integer
  compute budget_remaining = max_attempts - attempt
  output budget_remaining  : Integer
}
```

### RetrySimulator contract (BudgetedLocalLoop)

```igniter
pure contract RetrySimulator {
  input  outcomes      : Collection[Integer]
  compute total_attempts = 0

  loop RetryLoop outcome in outcomes max_steps: 5 {
    compute total_attempts = total_attempts + 1
  }

  output total_attempts : Integer
}
```

Pre-gate-8 loop form (no `lead`): outer compute symbol `total_attempts` mutated from body.
`max_steps: 5` is a static literal (Postulate 14: VM enforces OP_LOOP_STEP budget).

### RetryWithDispatch contract (dispatch + budget composability)

```igniter
pure contract RetryWithDispatch {
  input  job_class    : String
  input  job_id       : String
  input  arg1         : Integer
  input  arg2         : Integer
  input  attempt      : Integer
  input  max_attempts : Integer
  compute job_result       = call_contract(job_class, job_id, arg1, arg2)
  compute budget_remaining = max_attempts - attempt
  output budget_remaining  : Integer
}
```

`job_class` is a **variable** input, not a literal string — P10 TypeChecker does not
resolve variable callees at compile time; the dispatch happens at VM runtime.

---

## 3. Check Inventory (43/43 PASS)

### SJOB3-COMPILE — 6 checks
Fixture compiles with status=ok; all 4 contracts present; no diagnostics; all stages pass;
`RetrySimulator` semantic IR shows `loop_class=budgeted`, `max_steps=5`.

### SJOB3-SOURCE — 5 checks
VM source (`vm.rs`) contains `OOF-L-FUEL` error string, `OP_LOOP_START`, `MAX_CALL_DEPTH`;
fixture source contains `max_steps: 5` literal; `call_contract` appears in `RetryWithDispatch`.

### SJOB3-HAPPY — 8 checks

| Check | Input | Expected output |
|---|---|---|
| HAPPY-01 | `attempt=1, max_attempts=5` | `budget_remaining=4` |
| HAPPY-02 | `attempt=4, max_attempts=5` | `budget_remaining=1` |
| HAPPY-03 | `attempt=5, max_attempts=5` | `budget_remaining=0` (budget exhausted) |
| HAPPY-04 | `attempt=0, max_attempts=3` | `budget_remaining=3` |
| HAPPY-05 | `outcomes=[1]` | `total_attempts=1` |
| HAPPY-06 | `outcomes=[0,0,1]` | `total_attempts=3` |
| HAPPY-07 | `outcomes=[0,0,0,0,0]` | `total_attempts=5` (at budget; no error) |
| HAPPY-08 | `RetryWithDispatch(StubJob, attempt=1, max_attempts=5)` | `budget_remaining=4` |

### SJOB3-FC — 9 checks

| Check | Scenario | Expected |
|---|---|---|
| FC-01a | `RetrySimulator` with 6 outcomes (> max_steps=5) | `status=error` |
| FC-01b | 6-outcome error message | contains "fuel exhausted" |
| FC-01c | `RetrySimulator` with 5 outcomes | `status=success` (within budget) |
| FC-02a | `RetryPolicy(attempt=5, max_attempts=5)` | `budget_remaining=0` |
| FC-02b | `budget_remaining=0` is not an error | observable signal only |
| FC-02c | `RetryPolicy(attempt=6, max_attempts=5)` | `budget_remaining=-1` (over-budget; deterministic) |
| FC-03a | `RetryWithDispatch` with unknown `job_class` | `status=error` |
| FC-03b | unknown `job_class` error | mentions "no contract named" |
| FC-03c | `RetrySimulator` with empty `outcomes` | `total_attempts=0` (empty loop; no error) |

### SJOB3-REG — 5 checks
P2 regression: `job_dispatch_table.ig` still compiles; `JobDispatcher(ProcessOrderJob)→42`;
`JobDispatcher(ComputeReportJob)→50`; unknown job → "no contract named" error; 4 core P2
contracts still present.

### SJOB3-CLOSED — 5 checks
No TCP/UDP socket use; no Redis connection; no ServiceLoop invocation; no clock/time access
in proof or fixture source (OOF-L6 boundary); no Sidekiq compatibility claim and no
production claim.

### SJOB3-GAP — 5 checks
Gap packet: `retry_budget_arithmetic` in `closed_by_p3`; `max_steps_must_be_static_literal`
enforced; `job_receipt_schema` in `still_open`; `effect_dispatch` in `still_open`;
`sidekiq_compatibility` is `permanently_closed`.

---

## 4. Mechanism Reuse

| Mechanism | Source | Used in P3 |
|---|---|---|
| `call_contract` dispatch | LAB-RACK-P9 | `RetryWithDispatch` variable-callee dispatch |
| `OP_LOOP_STEP` fuel enforcement | PROP-039 VM | `RetrySimulator` budget enforcement |
| Literal callee static resolution | P10 TypeChecker | NOT triggered (variable callee) |
| `build_contract_registry` pre-scan | P10 TypeChecker | Validates `StubJob` is pure |
| `MAX_CALL_DEPTH` | P9 VM | Guards `RetryWithDispatch` from recursive dispatch |

---

## 5. BudgetedLocalLoop Semantics

### Fuel enforcement (OP_LOOP_STEP)

- VM enforces `max_steps` as a **hard ceiling** on loop iterations
- When `frame.fuel == 0` and items remain: runtime error `OOF-L-FUEL: loop fuel exhausted`
- With `max_steps=5`, a 5-element collection: **natural exhaustion** (success, no error)
- With `max_steps=5`, a 6-element collection: **fuel error** on the 6th OP_LOOP_STEP

### Pre-gate-8 body form

`RetrySimulator` uses the pre-gate-8 loop body form (no `lead` keyword). This allows
mutation of the outer `compute total_attempts` from inside the loop body. The VM compiles
the loop body so that `OP_STORE_REG(item_reg)` pushes each `outcome` item, and the body
node reuses the existing outer compute register for `total_attempts`.

### RetryPolicy vs RetrySimulator

Two distinct models tested:

| Model | What it proves |
|---|---|
| `RetryPolicy` | Budget is pure arithmetic — no loop needed |
| `RetrySimulator` | Budget is enforced by loop fuel — loop terminates |

These are complementary: `RetryPolicy` proves the arithmetic is correct; `RetrySimulator`
proves the structural bound is enforced by the VM.

---

## 6. P10 TypeChecker Interaction

`RetryWithDispatch` uses `call_contract(job_class, ...)` where `job_class` is an **input**
(variable), not a literal string. P10 TypeChecker only resolves **literal** callees
statically. Variable callee → TypeChecker skips compile-time check → dispatch happens at
VM runtime from the dispatch table.

This is the correct production-equivalent pattern: the dispatcher receives the job class
name as an input, not hardcoded.

Contrast with P2's `JobDispatcher` which also uses a variable callee (`job_class` input)
for the same reason.

---

## 7. Sidekiq Analogy (Lab Only)

| Sidekiq concept | Lab analog | Notes |
|---|---|---|
| `max_retries` config | `max_attempts` input to `RetryPolicy` | Static; not runtime-configurable |
| Retry counter | `attempt` input | Caller supplies; no VM clock |
| Retry decision | `budget_remaining > 0` | Pure arithmetic output |
| Retry loop bound | `max_steps: 5` | VM-enforced fuel; structurally bounded |
| Job dispatch | `call_contract(job_class, ...)` | Lab-only; pure callee only |
| Retry scheduling | **PERMANENTLY CLOSED** | No scheduler, no queue, no async |
| Retry backoff | **PERMANENTLY CLOSED** | No clock; OOF-L6 boundary |

---

## 8. Gap Packet

```ruby
GAP_PACKET = {
  proof:       'lab-sidekiq-p3-retry-policy',
  version:     'v0',
  closed_by_p3: %w[
    retry_budget_arithmetic
    budgeted_local_loop_bounded_retry
    fuel_exhaustion_at_max_steps
    dispatch_plus_budget_composability
  ],
  v0_policy: {
    max_steps_must_be_static_literal: 'enforced',
    pure_callee_only: 'enforced',
    no_clock_access: 'enforced'
  },
  still_open: %w[
    async_retry queue_storage job_receipt_schema
    effect_dispatch retry_backoff_schedule non_uniform_arity_dispatch
  ],
  sidekiq_compatibility: 'permanently_closed',
  p4_recommendation: 'JobReceipt schema — structured output record to replace raw Integer stub'
}
```

### P4 Recommendation

**JobReceipt schema** — a structured output record (instead of raw `Integer`) encoding:
- `job_class`: String
- `attempt`: Integer
- `budget_remaining`: Integer
- `status`: String (`"ok"` | `"exhausted"` | `"failed"`)

Blocked on: P11 `call_contract` output typing clarification (return type shape).

---

## 9. Artifacts

| File | Role |
|---|---|
| `igniter-view-engine/fixtures/sidekiq_core/retry_policy.ig` | Fixture — 4 contracts |
| `igniter-view-engine/proofs/verify_sidekiq_p3_retry_policy.rb` | Proof — 43/43 |
| `lab-docs/lang/lab-sidekiq-retry-policy-proof-v0.md` | This document |
| `.agents/work/cards/lang/LAB-SIDEKIQ-P3.md` | Card — CLOSED/PROVED |

---

## 10. Bugs Fixed

### P2 regression (P10 TypeChecker literal callee resolution)

During P3 development, P10 TypeChecker improvements caused a P2 regression (54→49). Root
cause: P10 added `build_contract_registry` pre-scan of all module contracts before
typechecking. When `call_contract("SelfDispatch", ...)` appears inside `SelfDispatch`,
OOF-TY0 fires at **compile time** (not VM runtime). Similarly for
`call_contract("EffectWorker", ...)` referencing an effect-modifier contract.

**Fixes applied:**
- Removed `SelfDispatch` from `job_dispatch_table.ig` (replaced with explanatory comment)
- Added inline `SELF_DISPATCH_SRC` to `verify_sidekiq_p2_job_dispatch.rb`
- FC-04 and FC-05 checks now verify compile-time OOF-TY0 (not VM runtime error)
- SJOB-COMPILE-05 updated to expect OOF-TY0

**Result:** P2 restored to 54/54. P2 regression checks (SJOB3-REG-01..05) confirm P2 stays
green with P3 proof running on the same codebase.

---

**Boundary:** Lab-only. No Sidekiq compatibility claim. No canon grammar change. No
production runtime. BudgetedLocalLoop is PROP-039 experiment-pass compiler surface.
`call_contract` is lab-only with no public API stability.
