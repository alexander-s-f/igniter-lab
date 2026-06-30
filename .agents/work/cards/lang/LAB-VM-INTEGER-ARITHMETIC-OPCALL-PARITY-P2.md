# LAB-VM-INTEGER-ARITHMETIC-OPCALL-PARITY-P2

Status: DONE
Route: standard / igniter-lab / VM / OP_CALL parity / frame-ui blocker
Skill: idd-agent-protocol
Depends-On: `LAB-IGNITER-VM-CHECKED-ARITH-P1`
Blocks: frame-ui `.ig` game reducer / `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`

## Goal

Close the VM parity gap found by the frame-ui game-logic pressure test: integer arithmetic emitted
by the compiler as `stdlib.integer.{add,sub,mul,div}` must execute through the VM `OP_CALL` path with
the same checked semantics as the already-covered bytecode / eval_ast arithmetic paths.

This is not a new language feature. It is a VM dispatch-name parity repair.

## Current Authority

Live source wins over this card if it has moved.

Read first:

- `LAB-IGNITER-VM-CHECKED-ARITH-P1`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/tests/vm_tests.rs`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-compiler/src/emitter.rs`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`

Known live facts to verify:

- compiler/typechecker/emitter lower integer `+ - * /` to
  `stdlib.integer.{add,sub,mul,div}`.
- VM `OP_CALL` currently accepts `stdlib.numeric.add | add` for add, but not
  `stdlib.integer.add`.
- VM `OP_CALL` does not currently expose matching `stdlib.integer.sub`,
  `stdlib.integer.mul`, and `stdlib.integer.div`.
- VM comparison names like `stdlib.integer.lt/gt/lte/gte` already work.
- checked helpers from P1 already exist:
  `checked_int_add/sub/mul/div`.

## Failure Reproducer

The tiny case should fail before the fix and pass after:

```ig
module Vm.Arith

contract IncDirect {
  input n : Integer
  compute r = n + 1
  output r : Integer
}
```

Expected current failure:

```text
OP_CALL: Unknown/unimplemented function 'stdlib.integer.add'
```

The frame pressure reproducer is:

```text
lab-docs/lang/specimens/dx-view-d/vm_game_app.ig
```

`StepBody` uses `+ - * /`; `Step` composes it through `map(... call_contract("StepBody", ...))`.

## Requirements

- Add VM `OP_CALL` support for:
  - `stdlib.integer.add`
  - `stdlib.integer.sub`
  - `stdlib.integer.mul`
  - `stdlib.integer.div`
- Preserve P1 checked arithmetic semantics:
  - overflow fails closed,
  - division by zero fails closed,
  - ordinary arithmetic succeeds.
- Do not implement these with raw `i64` operators.
- Prefer a shared helper / single dispatch path so bytecode, eval_ast, and OP_CALL do not drift again.
- Keep Decimal and Float behavior unchanged.
- Do not change compiler lowering unless live evidence proves that is the smaller correct fix.
- Do not edit frame-ui runtime code in this card; only use frame-ui/specimen pressure as proof.

## Acceptance

- [x] Minimal `IncDirect(n) = n + 1` runs through the VM and returns the expected integer.
- [x] `stdlib.integer.add/sub/mul/div` all execute through `OP_CALL`.
- [x] `i64::MAX + 1`, `i64::MIN - 1`, `i64::MAX * 2`, `i64::MIN / -1`, and division by zero fail
      closed through the `OP_CALL` path.
- [x] Existing checked-arith bytecode/eval_ast tests from P1 remain green.
- [x] `vm_game_app.ig` `StepBody` executes on VM.
- [x] `vm_game_app.ig` `Step` executes through `map + call_contract("StepBody", ...)` on VM.
- [x] No compiler/parser/canon changes unless explicitly justified in the proof packet.
- [x] `git diff --check` clean.

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path lang/igniter-vm/Cargo.toml checked_integer_arithmetic
cargo test --manifest-path lang/igniter-vm/Cargo.toml integer_arithmetic_opcall
cargo test --manifest-path lang/igniter-vm/Cargo.toml
git diff --check
```

If current test names differ, run the closest focused VM tests and record the exact commands.

## Required Packet

Create:

```text
lab-docs/lang/lab-vm-integer-arithmetic-opcall-parity-p2-v0.md
```

Packet must include:

- exact OP_CALL dispatch names added,
- evidence that checked helpers are used,
- before/after minimal reproducer,
- `vm_game_app.ig` `StepBody` / `Step` evidence,
- explicit note that P1 checked-arith guarantees were preserved.

## Closing Packet

Implemented and verified in:

```text
lab-docs/lang/lab-vm-integer-arithmetic-opcall-parity-p2-v0.md
```
