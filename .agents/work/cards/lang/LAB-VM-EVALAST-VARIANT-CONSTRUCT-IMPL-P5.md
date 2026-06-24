# LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5 - implement variant_construct in eval_ast

Status: CLOSED (2026-06-24)
Lane: VM / fleet recovery
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

Hygiene Gemini P5 and a live recheck found the current machine fleet is **HOLD 11/13**. One blocker is
`batch_importer`:

`VMExecutionError("Unsupported AST kind in VM evaluator: variant_construct")`

The bytecode path knows how to lower variant construction, but `eval_ast` (used for HOF/lambda bodies)
does not evaluate `variant_construct`. This is the known eval_ast parity class resurfacing.

## Goal

Add `variant_construct` support to `lang/igniter-vm/src/vm.rs::eval_ast` so variants constructed inside
lambda/HOF bodies evaluate to the same record shape as the bytecode path (`__arm` discriminant plus
fields), then recover `batch_importer` in the machine fleet sweep.

## Verify First

- Reproduce: `cd runtime/igniter-machine && cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture`.
- Locate the existing bytecode/normal evaluation behavior for variant construction.
- Inspect `batch_importer` fixture to understand the failing lambda/HOF shape.
- Check neighboring `eval_ast` cases for record literals, match, sum/filter/map/fold/reduce.

## Acceptance

- [x] New focused VM test proves `variant_construct` inside a lambda/HOF body evaluates correctly.
      `lang/igniter-vm/tests/variant_construct_in_lambda_tests.rs` (2 tests, both green):
      `variant_constructed_in_map_lambda_has_arm_shape` (asserts `__arm` + payload shape) and
      `variant_constructed_in_lambda_matches_to_abs` (construct + `match` in the same lambda → abs values).
- [x] `batch_importer` no longer fails with `Unsupported AST kind in VM evaluator: variant_construct`.
- [x] `cargo test --test machine_tests test_machine_fleet_sweep` improved **11/13 → 13/13**.
      NOTE (honest attribution): this card's eval_ast fix recovers **batch_importer** (11→12). The
      **web_router** recovery (12→13) is NOT from this card — it was a *load/parse* blocker (OOF-P0 colon
      on match-arm record literals at web_router:97), and `igniter-machine` parses via
      `igniter_compiler::parser::Parser`. It is fixed by concurrent uncommitted work in
      `lang/igniter-compiler/src/parser.rs` under card `LAB-COMPILER-MATCH-ARM-RECORD-LITERAL-FIX-P1`.
      My change is runtime-only (`eval_ast`) and cannot affect parsing — closed-surface respected.
- [x] No dynamic dispatch authority change (no dispatch/routing code touched).
- [x] `git diff --check` clean. Full `igniter-vm` suite green (0 failures); my diff = +36 lines in
      `lang/igniter-vm/src/vm.rs` plus the new test file.

## Closed Surfaces

Do not change language syntax. Do not fix `web_router` parser ambiguity in this card. Do not broaden
variant semantics beyond matching current bytecode/record shape.

All respected: no syntax change; `web_router`'s parser blocker was NOT touched by this card (recovered
out-of-band by the compiler card above); the new arm reproduces the exact bytecode record shape
(`__arm` + `__variant` + payload), no `Value::Variant`, no new semantics.
