# LAB-IGNITER-VM-CHECKED-ARITH-P1 - checked integer arithmetic in the VM

Status: DONE
Lane: igniter-lab / VM / foundation-hardening
Type: implementation / panic-to-runtime-error
Date: 2026-06-27
Skill: idd-agent-protocol
Source: `/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md`

## Agent Onboarding Header

This is the first non-frame Tier-0 implementation slice from the Opus audit
assimilation. Keep it narrow: **checked integer arithmetic only**. Do not widen
into Decimal exactness, range budgets, eval depth, compiler parsing, stdlib IO,
or frame-ui.

The finding is live: VM integer `+`, `-`, `*`, `/`, and unary negation still use
plain `i64` operations at multiple dispatch surfaces. In debug builds they can
panic; in release builds they can silently wrap. The language surface promises
checked arithmetic, so the VM should return a clean runtime error instead.

## Goal

Replace VM Integer arithmetic panics/wraps with deterministic runtime errors:

```text
i64::MAX + 1      -> error Value / VM error, not panic or wrap
i64::MIN - 1      -> error
i64::MAX * 2      -> error
i64::MIN / -1     -> error
-i64::MIN         -> error
division by zero  -> existing error behavior preserved
```

## Context

Read first:

```text
/Users/alex/dev/projects/igniter/audit/igniter-audit-assimilation-triage-p1.md
/Users/alex/dev/projects/igniter/audit/igniter-vm-core-foundation-audit-p1.md
lang/igniter-vm/IMPLEMENTED_SURFACE.md
lang/igniter-vm/src/vm.rs
lang/igniter-vm/tests/
```

Live anchors from triage/audit (verify line numbers before editing):

```text
bytecode:   vm.rs:411 / 449 / 485 / 527 / 2777
eval_ast:   vm.rs:4108 / 4136 / 4162 / 4194 / 4355
unified:    vm.rs:5909 / 5939 / 5967 / 6001
```

Pattern to reuse:

```text
num_abs / ipow / mod helpers already use checked_* style in vm.rs
```

## Current Authority

- Live VM source/tests decide behavior.
- Audit packets and command-center triage are evidence only.
- This card may edit only VM source/tests.

## Closed Surfaces

- Do not edit Decimal semantics or `igniter-stdlib/src/decimal.rs`.
- Do not edit compiler/parser.
- Do not edit range/collection budgets or eval-depth guards.
- Do not edit frame-ui, render-html, server, machine, home-lab, SparkCRM, or
  canon `igniter-lang`.
- Do not alter normal successful arithmetic results.

## Required Design

Introduce a tiny shared helper layer so the three VM dispatch surfaces do not
diverge again. Suggested shape:

```rust
fn checked_int_add(a: i64, b: i64) -> Result<i64, String>
fn checked_int_sub(a: i64, b: i64) -> Result<i64, String>
fn checked_int_mul(a: i64, b: i64) -> Result<i64, String>
fn checked_int_div(a: i64, b: i64) -> Result<i64, String>
fn checked_int_neg(a: i64) -> Result<i64, String>
```

Use existing VM error conventions. If there is already a canonical runtime
error representation, follow it. If not, keep the smallest local error string
and document it in the closing report.

## Acceptance

- [x] Add focused tests proving no panic/wrap for:

```text
i64::MAX + 1
i64::MIN - 1
i64::MAX * 2
i64::MIN / -1
-i64::MIN
division by zero still errors
ordinary arithmetic still succeeds
```

- [x] Cover at least bytecode/top-level execution and `eval_ast`/lambda path if
      the existing test harness can reach both cheaply. If one path is not
      reachable without new harness work, state that clearly and add a focused
      helper/unit test instead.
- [x] No successful arithmetic regression.
- [x] `cargo test -p igniter-vm` or the narrow current VM test command if the
      crate is not a workspace package from this cwd.
- [x] `git diff --check`
- [x] Only `lang/igniter-vm` source/tests and this card changed.

## Proof Doc

If the change is small, the closing report in this card is enough. Write a
separate proof doc only if test routing is non-obvious:

```text
lab-docs/lang/lab-igniter-vm-checked-arith-p1.md
```

## Closing Report

Close with:

- exact helper/error shape;
- exact files changed;
- exact commands and results;
- note confirming Decimal/range/eval-depth/compiler/frame-ui were not touched.

## Closing Report - 2026-06-27

Implemented the narrow checked-integer arithmetic slice in `igniter-vm`.

Helper/error shape:

```rust
fn checked_int_add(a: i64, b: i64) -> Result<i64, String>
fn checked_int_sub(a: i64, b: i64) -> Result<i64, String>
fn checked_int_mul(a: i64, b: i64) -> Result<i64, String>
fn checked_int_div(a: i64, b: i64) -> Result<i64, String>
fn checked_int_neg(a: i64) -> Result<i64, String>
```

- Overflow returns `Err("Integer overflow")`.
- Division by zero preserves existing `Err("Division by zero")`.
- Successful Integer arithmetic still returns the same `Value::Integer(...)`
  results.

Files changed:

- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/tests/vm_tests.rs`
- `.agents/work/cards/lang/LAB-IGNITER-VM-CHECKED-ARITH-P1.md`

Dispatch surfaces covered:

- Bytecode `OP_ADD`, `OP_SUB`, `OP_MUL`, `OP_DIV`, and `OP_NEG`.
- `eval_ast` `binary_op` / `unary` Integer paths.
- `eval_ast` call/operator table for `add` / `sub` / `mul` / `div`.

Tests added:

- `checked_integer_arithmetic_errors_in_bytecode_path` covers:
  - `i64::MAX + 1`
  - `i64::MIN - 1`
  - `i64::MAX * 2`
  - `i64::MIN / -1`
  - `-i64::MIN`
  - division by zero
  - ordinary add and ordinary unary negation success
- `test_map_reduce_aggregate_optimizations` now also covers:
  - HOF/lambda `eval_ast` `binary_op` overflow via `fold`
  - HOF/lambda `eval_ast` call/operator-table overflow via `fn: "add"`

Commands and results:

```text
cargo test --test vm_tests checked_integer_arithmetic_errors_in_bytecode_path -- --nocapture
Result: passed (1 test)

cargo test --test vm_tests -- --nocapture
Result: passed (23 tests)

cargo test
Result: passed (full igniter-vm crate)
```

Notes:

- Existing VM warnings remain unrelated (`has_integer`, `unused_unsafe`, and a
  dead `LoopFrame.name` field).
- `cargo fmt --check` was not used as an acceptance gate because it reports
  pre-existing formatting diffs across unrelated VM test files. No broad
  formatter pass was run.
- Current worktree has unrelated dirty files outside this card
  (`frame-ui/igniter-frame/Cargo.lock`, `lang/igniter-compiler/src/parser.rs`,
  `lang/igniter-compiler/tests/input_robustness_tests.rs`, imported
  `lab-docs/*`, and a sibling compiler card). This card's patch is limited to
  the VM source/test files and this card.
- Decimal semantics, range/collection budgets, eval-depth guards, compiler/parser,
  frame-ui, render-html, server, machine, home-lab, SparkCRM, and canon
  `igniter-lang` were not touched.
