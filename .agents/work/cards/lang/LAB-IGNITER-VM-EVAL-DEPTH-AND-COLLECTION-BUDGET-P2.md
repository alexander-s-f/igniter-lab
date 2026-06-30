# LAB-IGNITER-VM-EVAL-DEPTH-AND-COLLECTION-BUDGET-P2 - finish VM crash-safety after checked arithmetic

Status: DONE
Lane: igniter-lab / VM / foundation-hardening
Type: implementation / crash-safety
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-vm-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`
- `.agents/work/cards/lang/LAB-IGNITER-VM-CHECKED-ARITH-P1.md`

## Agent Onboarding Header

This is the remaining VM crash-safety slice after
`LAB-IGNITER-VM-CHECKED-ARITH-P1` closed checked integer arithmetic and after
Decimal money safety landed. Do not reopen those surfaces. Focus only on
runtime non-progress / crash / allocation hazards that can still be triggered
by malformed or adversarial `.ig`/SIR input.

## Goal

Turn the remaining VM crash/OOM hazards into deterministic runtime errors:

```text
deep nested eval_ast expression  -> clean runtime error, not stack overflow/SIGABRT
large range / collection budget  -> clean runtime error, not memory blow-up
unbounded loop / recursion       -> budget error, not infinite spin
```

## Verify-First Anchors

Before editing, verify live line numbers because this file moves quickly.

Known audit anchors:

```text
lang/igniter-vm/src/vm.rs
  eval_ast native recursion via Box::pin
  MAX_CALL_DEPTH only guards contract/function calls, not expression recursion
  range construction paths around prior anchors :1878 / :4580
  loop/runtime execution budget absent or partial
```

Also read:

```text
lang/igniter-vm/IMPLEMENTED_SURFACE.md
lang/igniter-vm/tests/
.agents/work/cards/lang/LAB-IGNITER-VM-CHECKED-ARITH-P1.md
```

## Current Authority

- Live VM source/tests decide behavior.
- Audit docs are evidence, not authority.
- This card may edit only `lang/igniter-vm` source/tests and this card.

## Closed Surfaces

- Do not edit Decimal semantics or stdlib Decimal code.
- Do not edit compiler/parser.
- Do not edit frame-ui, render-html, server, machine, home-lab, SparkCRM, or
  canon `igniter-lang`.
- Do not change successful normal execution results except to add explicit
  budget errors for pathological inputs.

## Required Design

Prefer small shared guards over ad hoc checks:

- an eval recursion/depth guard with RAII-style decrement so early returns do
  not poison later evaluation;
- collection/range budget constants with explicit error strings;
- one runtime step counter if the bytecode loop still lacks a global budget.

Keep errors deterministic and grep-friendly. If existing VM budget constants or
error conventions exist, reuse them.

## Acceptance

- [x] Focused tests prove deep nested eval_ast input errors cleanly.
- [x] Focused tests prove a huge `range(...)` / collection construction errors
      before large allocation.
- [x] Focused tests prove an unbounded/non-shrinking loop or recursion stops at
      a runtime budget, if reachable without large new harness work.
- [x] Existing VM tests still pass.
- [x] `cargo test` from `lang/igniter-vm` passes.
- [x] `git diff --check` passes.
- [x] Patch is limited to `lang/igniter-vm` plus this card.

## Proof / Closing

If the harness is non-obvious, write:

```text
lab-docs/lang/lab-igniter-vm-eval-depth-and-collection-budget-p2.md
```

Close with exact guard constants, exact commands/results, and a note confirming
checked arithmetic and Decimal were not touched.

Closed 2026-06-27:

- Implemented VM crash-safety guards in `lang/igniter-vm/src/vm.rs`.
- Guard constants:
  - `MAX_EVAL_AST_DEPTH = 32`
  - `MAX_COLLECTION_ELEMENTS = 1_000_000`
  - `MAX_VM_STEPS = 1_000_000`
- Error strings:
  - `OOF-VM-EVAL-DEPTH: eval_ast depth budget (...) exceeded`
  - `OOF-VM-COLLECTION-BUDGET: ... would create ... element(s), max ...`
  - `OOF-VM-BUDGET: runtime step budget (...) exceeded`
- Design notes:
  - `eval_ast` has both an iterative top-level AST-depth scan and a per-call
    guarded temporal depth counter. The iterative scan prevents recursive async
    future construction from overflowing the native stack before the guard can
    return a clean error.
  - `range`, `PUSH_ARRAY`, array concat, `zip`, `OP_CALL` args, and record key
    count now fail before hostile eager allocation/iteration.
  - The bytecode loop now has a global step counter, so non-progress jumps stop
    deterministically.
- Tests:
  - `eval_ast_depth_budget_errors_before_native_stack_overflow`
  - `vm_collection_budget_rejects_huge_range_before_allocation`
  - `vm_runtime_step_budget_stops_nonprogress_jump`
- Commands:
  - `cd lang/igniter-vm && cargo test --test vm_tests vm_ -- --nocapture` passed.
  - `cd lang/igniter-vm && cargo test eval_ast_depth_budget_errors_before_native_stack_overflow -- --nocapture` passed.
  - `cd lang/igniter-vm && cargo test` passed.
  - `git diff --check` passed.
- Existing VM warnings remain unrelated (`has_integer`, `unused_unsafe`, and
  dead `LoopFrame.name`).
- Checked arithmetic and Decimal semantics were not changed.
- Compiler/parser, frame-ui, render-html, server, machine, home-lab, SparkCRM,
  and canon `igniter-lang` were not edited.
