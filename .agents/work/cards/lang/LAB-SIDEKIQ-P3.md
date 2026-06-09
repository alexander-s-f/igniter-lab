# LAB-SIDEKIQ-P3: BudgetedLocalLoop Retry Policy

**Category:** lang
**Track:** `lab-sidekiq-budgeted-local-loop-retry-policy-proof-v0`
**Status:** CLOSED / PROVED — 43/43 PASS
**Date closed:** 2026-06-09
**Agent:** Igniter-Lang Implementation Agent
**Role:** implementation-agent
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Depends on

- LAB-SIDEKIQ-P2 (static job dispatch table — 54/54)
- LAB-RACK-P9 (`call_contract` dispatch mechanism)
- PROP-039 / BudgetedLocalLoop VM and compiler evidence

---

## Goal

Prove that a Sidekiq-like retry policy can be modeled as a pure BudgetedLocalLoop
over an explicit attempt counter, using static job dispatch pressure, without:
- Redis, worker daemon, scheduler authority
- Real clock access (OOF-L6 boundary)
- Effect-callee dispatch
- Sidekiq compatibility claims

---

## Scope

### Proved in P3

- **Retry budget as pure Integer arithmetic:** `budget_remaining = max_attempts - attempt`
- **BudgetedLocalLoop (PROP-039) bounded iteration:** `max_steps: 5` enforced by VM via OP_LOOP_STEP fuel
- **Fuel exhaustion at max_steps:** 6-outcome collection → `OOF-L-FUEL: loop fuel exhausted`; 5-outcome → success
- **Dispatch + budget composability:** `call_contract(job_class, ...)` and budget arithmetic in same contract

### Deferred / Permanently closed

- **Retry scheduling:** permanently closed (no scheduler, no queue, no async)
- **Retry backoff:** permanently closed (no clock; OOF-L6)
- **Effect-callee dispatch:** deferred to P10/P11 (`call_contract` output typing)
- **Non-uniform arity dispatch:** deferred
- **JobReceipt schema:** deferred to P4 (pending P11 output typing)
- **Async retry:** permanently closed

---

## Deliverables

| File | Status |
|---|---|
| `igniter-view-engine/fixtures/sidekiq_core/retry_policy.ig` | ✅ Written |
| `igniter-view-engine/proofs/verify_sidekiq_p3_retry_policy.rb` | ✅ 43/43 |
| `lab-docs/lang/lab-sidekiq-retry-policy-proof-v0.md` | ✅ Written |
| `.agents/work/cards/lang/LAB-SIDEKIQ-P3.md` | ✅ This file |
| `.agents/portfolio-index.md` updated | ✅ P3 row added |

---

## Key Findings

1. **BudgetedLocalLoop fuel enforcement is verifiable from Ruby proof layer** — the `OOF-L-FUEL`
   error string is present in `vm.rs` and returned in VM output when fuel exhausts.

2. **Pre-gate-8 loop body form works for accumulation** — no `lead` keyword required; outer
   `compute total_attempts` mutated from loop body via register reuse.

3. **Variable callee bypasses P10 compile-time check** — `call_contract(job_class, ...)` with
   `job_class` as an input skips TypeChecker literal resolution; dispatch at VM runtime.

4. **budget_remaining=0 is a deterministic signal, not an error** — `RetryPolicy(attempt=5,
   max_attempts=5)` → `budget_remaining=0` with `status=success`; caller interprets the value.

5. **budget_remaining=-1 is over-budget; still deterministic** — arithmetic permits negative
   values; structural bound is via BudgetedLocalLoop fuel, not budget_remaining sign.

---

## P2 Regression Fixed

During P3 development, P10 TypeChecker improvements caused P2 to drop to 49/54. Root cause:
literal callee static resolution (`build_contract_registry` pre-scan) now fires OOF-TY0 at
compile time for self-recursion and effect-callee patterns that were previously caught at VM
runtime.

**Fixes:**
- Removed `SelfDispatch` from `job_dispatch_table.ig`; moved to inline fixture in P2 proof
- FC-04 / FC-05 checks updated to verify compile-time OOF-TY0
- P2 restored to 54/54
- SJOB3-REG-01..05 confirm P2 stays green under P3 codebase

---

## P4 Recommendation

**JobReceipt schema** — a structured output record replacing raw `Integer` output from
`RetryWithDispatch`. Blocked on P11 `call_contract` output typing clarification.

Expected fields:
- `job_class`: String
- `attempt`: Integer
- `budget_remaining`: Integer
- `status`: String (`"ok"` | `"exhausted"` | `"failed"`)

---

## Boundary

Lab-only. No Sidekiq compatibility claim. No canon grammar change. No production runtime.
No public API stability. BudgetedLocalLoop is PROP-039 experiment-pass compiler surface.
`call_contract` is lab-only.
