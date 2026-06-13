# LAB-IGNITER-LANG-IO-RUNTIME-P2

**Status:** CLOSED — PROOF COMPLETE (69/69)  
**Route:** LAB RUNTIME / MOCKED IO EXECUTION / STORAGE READ  
**Date:** 2026-06-13  
**Authority:** mocked executable proof only; no real DB/SQL/ORM

## Goal

Prepare the first executable IO Runtime slice using the Storage read family.

P1 recommended Storage read because it has the deepest evidence: Query v0,
StorageCapability gates, denial-as-data, `QueryExecutionReceipt`, and mocked
execution proofs. This card should become implementation-ready only after
`LANG-IO-CAPABILITY-EXECUTOR-P1` fixes the executor interface.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch7-runtime.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch12-effect-surface.md`

## Scope

P2 should prove a mocked runtime path, not real storage:

```text
effect contract with IO.StorageCapability
  -> compiled/assembled evidence
  -> RuntimeMachine-like evaluator sees effect boundary
  -> mocked CapabilityExecutor denies/allows
  -> QueryExecutionReceipt returned as typed data
```

## Questions

1. What minimal fixture expresses storage read as an effect contract?
2. Can existing `QueryExecutionReceipt` be reused unchanged?
3. Which six gates from StorageCapability P2 become executor gates?
4. What is runtime refusal vs denial-as-data?
5. What evidence must be written for replay?
6. What remains closed before real DB: SQL execution, ORM, migrations, transactions, persistence?

## Deliverables

- Planning/proof doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md`
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p2.rb`, target at least 55 checks.
- Card update and portfolio update after closure.

## Closure

| Artifact | Path | Status |
|---|---|---|
| Planning doc | `lab-docs/lang/lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md` | ✅ DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_igniter_lang_io_runtime_p2.rb` | ✅ DONE — 69/69 PASS |
| Card update | `.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P2.md` | ✅ DONE |
| Portfolio update | `.agents/portfolio-index.md` | ✅ DONE |

### Acceptance Criteria — all satisfied

- [x] P2 has an executor-ready mocked storage read slice (MockStorageCapabilityExecutor Layer C).
- [x] All 6 questions answered with file evidence.
- [x] Real DB/SQL/ORM remains closed.
- [x] QueryExecutionReceipt 15-field shape reused unchanged.
- [x] Runtime refusal vs denial-as-data distinction proved.
- [x] Replay evidence requirements documented.
- [x] The next implementation card is precise and bounded.

### Recommended Next Card

**Implementation card** (after LANG-IO-CAPABILITY-EXECUTOR-P1 closed ✅):
- Implement `StorageCapabilityExecutor < CapabilityExecutor` (7-arg interface from P1)
- Implement `CapabilityExecutorRegistry.register("IO.StorageCapability", executor)`
- Wire into RuntimeMachine evaluate path for ESCAPE effect contracts
- Return `QueryResult` + `QueryExecutionReceipt` as paired typed outputs
- Scope: one executor, one capability class, one effect family (storage read)
- No write ops, no transactions, no SQL, no real DB
