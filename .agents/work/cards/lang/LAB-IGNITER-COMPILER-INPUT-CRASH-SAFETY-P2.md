# LAB-IGNITER-COMPILER-INPUT-CRASH-SAFETY-P2 - parser depth and float literal crash guards

Status: DONE
Lane: igniter-lab / compiler / foundation-hardening
Type: implementation / diagnostics-not-crashes
Date: 2026-06-27
Skill: idd-agent-protocol
Source:
- `lab-docs/igniter-compiler-core-foundation-audit-p1.md`
- `lab-docs/igniter-foundation-hardening-roadmap-p1.md`
- `lab-docs/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is the compiler T0 crash-safety slice. The audit reports two now-live
input hazards: deep parser recursion can abort the process, and huge/non-finite
float literals can panic through unchecked `serde_json::Number::from_f64`.
The compiler must diagnose hostile input; it must not crash.

## Goal

Malformed input should produce diagnostics, never process abort/panic:

```text
((((1)))) repeated thousands of times -> OOF diagnostic, no SIGABRT
400+ digit float literal / overflow   -> OOF diagnostic, no unwrap panic
NaN/Inf-like invalid numeric path      -> diagnostic, no JSON number panic
```

## Verify-First Anchors

Before editing, verify live line numbers. Audit anchors:

```text
lang/igniter-compiler/src/parser.rs
  recursive expression parsing around prior anchors :3293 / :3661
  from_f64().unwrap() around prior anchors :3630 / :1256
lang/igniter-compiler/src/liveness.rs
  RAII-style recursion/depth guard pattern to reuse if still present
```

Also read:

```text
lang/igniter-compiler/IMPLEMENTED_SURFACE.md
lang/igniter-compiler/tests/
```

## Current Authority

- Live compiler source/tests decide behavior.
- Audit docs are evidence only.
- This card may edit only `lang/igniter-compiler` source/tests and this card.

## Closed Surfaces

- Do not change language syntax or accepted valid programs.
- Do not edit VM, stdlib, web, server, machine, frame-ui, home-lab, SparkCRM, or
  canon `igniter-lang`.
- Do not add a new numeric semantics policy beyond refusing unrepresentable
  float literals safely.

## Required Design

- Add a parser recursion/depth guard, preferably reusing the existing
  liveness-style RAII pattern if suitable.
- Replace unchecked `from_f64().unwrap()` with one helper that returns a
  diagnostic when the float cannot be represented as a finite JSON number.
- Keep diagnostics stable enough for focused tests; exact code may be a new
  `OOF-*` or an existing parser diagnostic if there is already a convention.

## Acceptance

- [x] Test for deeply nested parentheses returns a diagnostic and the compiler
      process exits normally.
- [x] Test for an oversized float literal returns a diagnostic and does not
      panic.
- [x] Existing compiler tests pass.
- [x] Focused command and full relevant test command are recorded.
- [x] `git diff --check` passes.
- [x] Patch is limited to `lang/igniter-compiler` plus this card.

## Proof / Closing

Write a proof doc only if needed:

```text
lab-docs/lang/lab-igniter-compiler-input-crash-safety-p2.md
```

Close with exact diagnostics, exact commands/results, and a note confirming no
runtime/VM behavior was changed.

## Closing Report - 2026-06-27

Closed as already implemented in the current live compiler source, with fresh
verification in this pass. No compiler source patch was required for this card.

Live implementation shape:

- `lang/igniter-compiler/src/parser.rs` has parser-local `expr_depth` tracking
  with `MAX_PARSE_EXPR_DEPTH = 32`.
- Deep expression nesting records `OOF-PDEPTH` and returns an `Expr::Error`
  instead of recursing until process abort.
- Float JSON-number construction is centralized through
  `finite_json_number_or_diagnostic(...)`.
- Oversized/non-finite Float literals record `OOF-PFLOAT` and use a finite
  placeholder JSON number so the parser can continue reporting diagnostics.
- The prior `from_f64(...).unwrap()` crash sites for ordinary Float literals and
  assumption strength literals are no longer present.

Existing focused tests:

- `lang/igniter-compiler/tests/input_robustness_tests.rs`
  - `deeply_parenthesized_expression_is_diagnostic_not_stack_overflow`
  - `deeply_nested_array_expression_is_diagnostic_not_stack_overflow`
  - `huge_float_expression_literal_is_diagnostic_not_panic`
  - `huge_assumption_strength_literal_is_diagnostic_not_panic`

Commands and results:

```text
cargo test --test input_robustness_tests -- --nocapture
Result: passed (4 tests)

rg -n "serde_json::Number::from_f64\([^\n]+\)\.unwrap|from_f64\([^\n]+\)\.unwrap|parse::<f64>\(\)\.unwrap" src tests -S
Result: no JSON-number unwrap panic sites found; one safe `parse::<f64>().unwrap_or(0.0)`
        remains for `WindowValue::Float`, outside the JSON-number panic path.

cargo test
Result: passed (full igniter-compiler crate)

git diff --check
Result: passed
```

Existing warnings from `cargo test` are unrelated compiler warnings
(`unused_imports`, `unused_variables`, `unused_mut`, and dead-code notes).

No runtime/VM behavior was changed. VM, stdlib, web, server, machine, frame-ui,
home-lab, SparkCRM, and canon `igniter-lang` were not touched.
