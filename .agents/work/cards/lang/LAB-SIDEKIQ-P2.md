# LAB-SIDEKIQ-P2: Static Job Dispatch Table — Pure Contracts, VM-Backed via call_contract

**Status:** CLOSED / PROVED
**Track:** lab-sidekiq-static-job-dispatch-table-proof-v0
**Category:** lang / EXPERIMENTAL / LAB-ONLY
**Date:** 2026-06-09
**Result:** 54/54 PASS

---

## Scope

Static job dispatch table with pure job contracts, VM-backed via lab-only `call_contract`.
No external queue, no runtime worker, no scheduler.

Three named job contracts (`ProcessOrderJob`, `ComputeReportJob`, `ValidatePaymentJob`) compiled
into a single igapp alongside a `JobDispatcher` contract that routes by `job_class: String` using
`call_contract`. All fail-closed policies from LAB-RACK-P9 hold without modification.

---

## Artifacts

| File | Description |
|---|---|
| `igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig` | 5-contract fixture: 3 job contracts + JobDispatcher + SelfDispatch |
| `igniter-view-engine/proofs/verify_sidekiq_p2_job_dispatch.rb` | 54-check proof |
| `lab-docs/lang/lab-sidekiq-job-dispatch-table-proof-v0.md` | Full proof documentation |

---

## Result: 54/54 PASS

| Section | Checks | Status |
|---|---|---|
| SJOB-COMPILE | 6 | ✅ |
| SJOB-SOURCE | 6 | ✅ |
| SJOB-HAPPY | 7 | ✅ |
| SJOB-FC | 18 | ✅ |
| SJOB-REG | 5 | ✅ |
| SJOB-CLOSED | 6 | ✅ |
| SJOB-GAP | 6 | ✅ |

---

## Key Findings

- `call_contract` (LAB-RACK-P9) generalizes to job dispatch without any VM/compiler changes.
- Uniform arity `(job_id: String, arg1: Integer, arg2: Integer) → Integer` enables positional routing.
- All 6 fail-closed cases pass: unknown class, arity mismatch, non-string callee, effect callee, self-cycle, depth > 8.
- P9 regression green: `CallerDoubler(10)→21`, `CallerSmall(50)→true`, `CallerGate(GET,/)→200`.
- Two bugs found and fixed during proof run: `compile_fixture` encoding issue (`×` in liveness strings); SJOB-CLOSED-04 false positive for `ServiceLoop` in gap packet docs.

---

## Bugs Fixed During Proof Run

1. **`compile_fixture` encoding** — compiler liveness output contains `×` (U+00D7); fixed with `.force_encoding('UTF-8')` in `compile_fixture` helper.
2. **SJOB-CLOSED-04 false positive** — gap packet docs legitimately contain "ServiceLoop" as a closed-surface string; fixed to scan only for actual invocation/require patterns.

---

## Consistency Fix Applied to P9 Proof

Added `.force_encoding('UTF-8')` to `compile_fixture` in `verify_p9_user_contract_dispatch.rb`
for defensive consistency. P9 passed 60/60 without it (P9 fixtures don't trigger `×` in liveness
output), but the fix is correct practice and prevents future breakage.

---

## Closed Surfaces

Redis, worker daemon, ServiceLoop, network I/O, scheduler, clock authority, Sidekiq compatibility
claim, `call_contract` canon claim, production claim. All permanently closed in v0.

---

## P3 Candidates (per user guidance)

- **P3a:** JobReceipt schema — structured output record replacing raw Integer stub
- **P3b:** BudgetedLocalLoop retry policy — attempt counter + max_attempts proof

Effect-callee dispatch deferred until P10/P11 clarify `call_contract` output typing boundaries.

---

## Predecessor

LAB-SIDEKIQ-P1 (feasibility research, RESEARCH COMPLETE)
LAB-RACK-P9 (call_contract mechanism, PROVED 60/60)
