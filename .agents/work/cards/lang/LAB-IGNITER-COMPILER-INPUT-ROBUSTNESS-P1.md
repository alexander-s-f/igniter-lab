# LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1 - parser depth and finite float literals

Status: DONE
Lane: igniter-lab / compiler / foundation-hardening
Type: implementation / panic-to-diagnostic
Date: 2026-06-27
Skill: idd-agent-protocol
Source: `/Users/alex/dev/projects/igniter/audit/igniter-foundation-hardening-next-wave-p1.md`

## Agent Onboarding Header

This is a narrow compiler robustness card. It is **not** the broad compiler
type-IR or supply-chain card. Keep it to input crash-safety:

```text
deep parser recursion -> diagnostic, not stack overflow / SIGABRT
huge float literal    -> diagnostic, not Number::from_f64(...).unwrap() panic
```

Do not edit VM arithmetic, Decimal, package lock enforcement, or compiler
type-system internals here.

## Goal

Turn two live parser crash classes into clean diagnostics:

1. Deep nested expressions such as thousands of parentheses/arrays.
2. Float literals that parse to non-finite `f64` and currently hit
   `serde_json::Number::from_f64(v).unwrap()`.

## Context

Read first:

```text
/Users/alex/dev/projects/igniter/audit/igniter-foundation-hardening-next-wave-p1.md
/Users/alex/dev/projects/igniter/audit/igniter-compiler-core-foundation-audit-p1.md
lang/igniter-compiler/IMPLEMENTED_SURFACE.md
lang/igniter-compiler/src/parser.rs
lang/igniter-compiler/src/liveness.rs
lang/igniter-compiler/tests/
```

Live anchors from audit (verify line numbers before editing):

```text
parser.rs:3293 parse_binary_or recursion
parser.rs:3661 parenthesized expression recursion
parser.rs:3630 FloatLit Number::from_f64(v).unwrap()
parser.rs:1256 assumption strength Number::from_f64(val).unwrap()
```

Existing pattern to study:

```text
liveness.rs depth/budget guard pattern
parser Illegal-token diagnostics from string escape work
```

## Current Authority

- Live compiler source/tests decide behavior.
- Audit packets are evidence, not authority.
- This card may edit only compiler source/tests and this card.

## Closed Surfaces

- Do not edit VM runtime or stdlib.
- Do not edit package lock/verify/build enforcement.
- Do not start `enum IgType` or typechecker refactors.
- Do not edit IgWeb lowering, server, machine, frame-ui, home-lab, SparkCRM, or
  canon `igniter-lang`.

## Required Design

Use the smallest parser-local mechanism that prevents native stack overflow.
Reasonable options:

- parser expression-depth counter with RAII enter/exit guard;
- parser budget object reused across recursive expression/array/record paths;
- equivalent existing local pattern if already present.

For float literals, add one helper so both sites share behavior:

```rust
fn finite_json_number_or_diagnostic(...)
```

The helper should reject `NaN`/`Infinity`/non-finite parse results with an
`OOF-*` diagnostic and a recoverable placeholder value, instead of panicking.

## Acceptance

- [x] Add tests or fixtures proving a deeply nested expression returns a
      diagnostic and the compiler process survives.
- [x] Add tests or fixtures proving a huge float literal returns a diagnostic
      and the compiler process survives.
- [x] Cover both FloatLit expression literal and assumption `strength` numeric
      literal if the existing harness can reach both cheaply.
- [x] Existing compiler tests remain green.
- [x] `cargo test -p igniter-compiler` or the narrow current compiler test
      command if workspace packaging requires it.
- [x] `git diff --check`
- [x] Only `lang/igniter-compiler` source/tests and this card changed.

## Non-Goals

- No emitter arity-index panic sweep.
- No parser grammar cleanup such as chained comparisons or missing commas.
- No liveness early-return refactor unless needed for the depth guard.
- No typechecker changes.

## Proof Doc

If implementation requires a new harness or nuanced recovery behavior, write:

```text
lab-docs/lang/lab-igniter-compiler-input-robustness-p1.md
```

Otherwise close this card with enough command/evidence detail.

## Closing Report

Closed 2026-06-27.

Chosen mechanism:

- Added a parser-local expression nesting counter on `Parser`.
- Limit: `MAX_PARSE_EXPR_DEPTH = 32`.
- On breach, parser emits `OOF-PDEPTH` and skips the current balanced delimiter
  group/token so recovery does not repeatedly re-enter the same adversarial
  nesting.
- This stayed parser-local; `liveness.rs` was read for pattern only and not
  changed.

Float-literal behavior:

- Added shared `finite_json_number_or_diagnostic(...)`.
- Both expression `FloatLit` and assumption `strength` FloatLit now reject
  non-finite parse results with `OOF-PFLOAT` and use finite JSON number `0.0` as
  a recoverable placeholder.

Diagnostics:

```text
OOF-PDEPTH: expression nesting exceeds parser limit of 32
OOF-PFLOAT: <context> must be a finite Float literal
```

Files changed:

```text
lang/igniter-compiler/src/parser.rs
lang/igniter-compiler/tests/input_robustness_tests.rs
.agents/work/cards/lang/LAB-IGNITER-COMPILER-INPUT-ROBUSTNESS-P1.md
```

Verification:

```text
cargo test --test input_robustness_tests
# passed: 4 tests

cargo test
# passed: full igniter_compiler crate test suite

git diff --check
# passed
```

Notes:

- `lang/igniter-compiler/IMPLEMENTED_SURFACE.md` was requested by the card but
  is absent in the current checkout; live source/tests were used as authority.
- VM runtime, Decimal, package lock/verify/build enforcement, frame-ui,
  home-lab, SparkCRM, and canon `igniter-lang` were not touched.
