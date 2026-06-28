# LAB-VM-INTEGER-ARITHMETIC-OPCALL-PARITY-P2 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` VM only. No compiler, parser, SIR schema, canon
`igniter-lang`, frame-ui runtime, Decimal, Float, or collection-stdlib semantic
change.
Depends-On: `.agents/work/cards/lang/LAB-IGNITER-VM-CHECKED-ARITH-P1.md`

## What This Slice Did

Closed the VM `OP_CALL` dispatch-name parity gap for integer arithmetic names:

- `stdlib.integer.add`
- `stdlib.integer.sub`
- `stdlib.integer.mul`
- `stdlib.integer.div`

The implementation adds a shared VM helper:

```rust
fn eval_arithmetic_call(fn_name: &str, args: &[Value]) -> Option<Result<Value, String>>
```

That helper is used by:

- bytecode `OP_CALL` dispatch for the names above;
- legacy `stdlib.numeric.add` / `add` aliases, now checked for Integer too;
- eval_ast binary-operator entry (`+`, `-`, `*`, `/`);
- eval_ast call/operator table (`add`, `sub`, `mul`, `div`, and the
  `stdlib.integer.*` names).

Integer branches call the P1 helpers:

- `checked_int_add`
- `checked_int_sub`
- `checked_int_mul`
- `checked_int_div`

No raw `i64` `+ - * /` is used for Integer values in this new call path.

## Live Before-State Correction

The card's tiny source reproducer:

```ig
module Vm.Arith

contract IncDirect {
  input n : Integer
  compute r = n + 1
  output r : Integer
}
```

did **not** fail on the live checkout before this patch. The compiler emitted a
`binary_op` shape for this source, and the VM compiler lowered it to bytecode
`OP_ADD`, so the run already returned:

```json
{"result":42,"status":"success"}
```

The remaining live gap was narrower and still real: direct `OP_CALL` dispatch
did not have `stdlib.integer.add/sub/mul/div` names, and legacy
`stdlib.numeric.add` still used unchecked Integer `av + bv` inside `OP_CALL`.
This slice fixes that VM dispatch surface without changing compiler lowering.

The frame pressure specimen also compiled and ran on the current checkout before
the patch because its arithmetic arrived as `binary_op`/bytecode. It is kept as
after-proof to guard the frame-ui reducer path.

## Code Paths Changed

- `lang/igniter-vm/src/vm.rs`
  - `OP_CALL` dispatch now routes `stdlib.integer.add/sub/mul/div` through
    `eval_arithmetic_call`.
  - `stdlib.numeric.add` and `add` route through the same helper, so Integer add
    is checked there too.
  - eval_ast binary-op and call/operator-table entry points consult the same
    helper before falling through to other dispatch.
- `lang/igniter-vm/tests/vm_tests.rs`
  - Added `integer_arithmetic_opcall_names_use_checked_helpers`.

No `lang/igniter-compiler`, parser, canon, frame-ui, or specimen source was
edited.

## Regression Matrix

| Case | Result |
| --- | --- |
| `OP_CALL stdlib.integer.add(40, 2)` | `Value::Integer(42)` |
| `OP_CALL stdlib.integer.sub(45, 3)` | `Value::Integer(42)` |
| `OP_CALL stdlib.integer.mul(6, 7)` | `Value::Integer(42)` |
| `OP_CALL stdlib.integer.div(84, 2)` | `Value::Integer(42)` |
| `OP_CALL stdlib.integer.add(i64::MAX, 1)` | `Integer overflow` |
| `OP_CALL stdlib.integer.sub(i64::MIN, 1)` | `Integer overflow` |
| `OP_CALL stdlib.integer.mul(i64::MAX, 2)` | `Integer overflow` |
| `OP_CALL stdlib.integer.div(i64::MIN, -1)` | `Integer overflow` |
| `OP_CALL stdlib.integer.div(1, 0)` | `Division by zero` |
| `OP_CALL stdlib.numeric.add(i64::MAX, 1)` | `Integer overflow` |

P1 bytecode/eval_ast checked-arithmetic guard remains green.

## Source-Level Evidence

Minimal `IncDirect`, compiled through `igniter_compiler` and run through
`igniter-vm`:

```json
{"latency_us":114,"observations":[],"result":42,"status":"success"}
```

`lab-docs/lang/specimens/dx-view-d/vm_game_app.ig` `StepBody` with:

```json
{"b":{"px":1,"py":2,"pz":3,"vx":4,"vy":5,"vz":6},"boom":1}
```

returned:

```json
{"px":297,"py":574,"pz":301,"vx":296,"vy":572,"vz":298}
```

`vm_game_app.ig` `Step` through `map + call_contract("StepBody", ...)` with
one body returned:

```json
{"bodies":[{"px":297,"py":574,"pz":301,"vx":296,"vy":572,"vz":298}]}
```

## Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path lang/igniter-vm/Cargo.toml integer_arithmetic_opcall -- --nocapture
cargo test --manifest-path lang/igniter-vm/Cargo.toml checked_integer_arithmetic -- --nocapture
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test vm_tests -- --nocapture
cargo test --manifest-path lang/igniter-vm/Cargo.toml
git diff --check
```

Results:

- `integer_arithmetic_opcall`: 1 passed.
- `checked_integer_arithmetic`: 1 passed.
- `vm_tests`: 31 passed.
- full `igniter-vm` crate: 164 passed, 0 failed.
- `git diff --check`: clean.

`cargo fmt --check` is not used as this card's gate because the VM crate has
pre-existing rustfmt diffs in unrelated files (`linalg_mat3_tests.rs`,
`record_construction_in_lambda_tests.rs`, `stdlib_collection_zip_tests.rs`,
`stdlib_float_to_text_tests.rs`, `stdlib_math_det_tests.rs`, and existing
sections of `vm.rs`). No broad formatter pass was run.

## Preserved Guarantees

- P1 checked arithmetic guarantees are preserved for bytecode and eval_ast, and
  now apply to the `OP_CALL` integer arithmetic names too.
- Decimal and Float behavior remains unchanged: the helper keeps the existing
  Decimal exact operations and Float arithmetic/division-by-zero behavior.
- No compiler lowering was changed; live evidence showed VM dispatch was the
  correct surface.
- The frame-ui reducer specimen was used only as proof pressure; frame-ui code
  was not edited.
