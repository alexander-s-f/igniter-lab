# LAB-VM-EVALAST-VARIANT-CONSTRUCT-IMPL-P5 - implement variant_construct in eval_ast

Status: OPEN
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

- [ ] New focused VM test proves `variant_construct` inside a lambda/HOF body evaluates correctly.
- [ ] `batch_importer` no longer fails with `Unsupported AST kind in VM evaluator: variant_construct`.
- [ ] `cargo test --test machine_tests test_machine_fleet_sweep -- --nocapture` improves from 11/13; if `web_router` still fails, report 12/13 and name the remaining parser blocker.
- [ ] No dynamic dispatch authority change.
- [ ] `git diff --check` clean.

## Closed Surfaces

Do not change language syntax. Do not fix `web_router` parser ambiguity in this card. Do not broaden
variant semantics beyond matching current bytecode/record shape.
