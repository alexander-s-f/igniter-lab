# LAB-RUST-LOOP-BODY-ASSIGNMENT-P1

**Status:** CLOSED — IMPLEMENTED 90/90 PASS  
**Route:** lab / Rust typechecker / loop-body assignment tightening  
**Date:** 2026-06-15  
**Date closed:** 2026-06-15  
**Authority:** lab Rust implementation card; canon Ruby is the authority baseline

## Goal

Align the Rust lab compiler with canon Ruby for local loop body assignment checks.

`LANG-BUDGETED-LOCAL-LOOP-RUBY-P1` proved that Rust conditionally skips OOF-L7/OOF-L5
when a loop body has no `lead` bindings (`is_gate8_body == false`), allowing loop
body computes to reassign outer contract symbols. Ruby rejects this unconditionally.

This card tightens Rust. It does not relax Ruby, and it does not expand
`BudgetedLocalLoop`.

## Gate

Start after:

- `LANG-BUDGETED-LOCAL-LOOP-RUBY-P1` CLOSED — 62/62 PASS.
- `LAB-RUST-TYPECHECKER-DECOMP-P2` CLOSED — stdlib dispatch extraction complete,
  so typechecker source shape is current.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-BUDGETED-LOCAL-LOOP-RUBY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/proposals/LANG-BUDGETED-LOCAL-LOOP-RUBY-P1-readiness-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/experiments/budgeted_local_loop_proof/verify_budgeted_local_loop_ruby_p1.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/lib/igniter_lang/typechecker.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/job_runner/PRESSURE_REGISTRY.md`
- PROP-039 / managed recursion docs if available.

## Scope

Implement the narrow Rust tightening:

- remove the `is_gate8_body` condition as a guard for OOF-L7/OOF-L5 assignment checks;
- enforce loop body target checks for all loop bodies, whether or not `lead` is present;
- preserve valid `lead`-targeted loop body assignments;
- preserve existing OOF-L7/OOF-L5 code/message shape where possible.

## Deliverables

- Rust implementation in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/verify_rust_loop_body_assignment_p1.rb`, target at least 50 checks.
- Update `LANG-BUDGETED-LOCAL-LOOP-RUBY-P1` runner to fixed-state only if its gap assertions become stale and the update is clearly scoped.
- Proof doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-rust-loop-body-assignment-p1-proof-v0.md`.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Rust now emits OOF-L7/OOF-L5 for outer-symbol reassignment in loop bodies even
  when no `lead` binding exists.
- Rust still accepts valid loop bodies that assign only declared lead bindings.
- Ruby behavior remains unchanged.
- `job_runner` remains dual-clean because it does not use managed loop syntax.
- Full fleet recheck shows no app regressions, or any new failure is explained as
  an intended tightening with a pressure ID.
- No app source edits.

## Closure Summary

Implemented the narrow Rust tightening in:

- `igniter-lab/igniter-compiler/src/typechecker.rs`

The Rust typechecker no longer uses `is_gate8_body` as a guard for OOF-L7/OOF-L5
loop-body target checks. It now matches canon Ruby: every loop-body `compute`
must target a declared `lead` binding. Outer contract symbols, loop item
variables, and undeclared targets are rejected even when the body has no `lead`.

Proof:

```text
cd igniter-lab/igniter-compiler
ruby verify_rust_loop_body_assignment_p1.rb
Summary: 90/90 checks passed
```

Fixed-state predecessor proof:

```text
cd igniter-lang
ruby experiments/budgeted_local_loop_proof/verify_budgeted_local_loop_ruby_p1.rb
PASS 62/62
```

Fleet smoke:

- 20 apps checked.
- 19 apps remain Rust `ok / 0 diagnostics`.
- `rule_engine` remains the single expected fail-closed app.
- `job_runner` remains dual-clean because it does not use managed loop syntax.

Artifacts:

| Artifact | Path |
|---|---|
| Proof runner | `igniter-lab/igniter-compiler/verify_rust_loop_body_assignment_p1.rb` |
| Proof doc | `igniter-lab/lab-docs/lang/lab-rust-loop-body-assignment-p1-proof-v0.md` |
| Fixed-state P1 runner | `igniter-lang/experiments/budgeted_local_loop_proof/verify_budgeted_local_loop_ruby_p1.rb` |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` |

## Closed Surfaces

- No Ruby relaxation.
- No new loop syntax.
- No fold-to-struct implementation.
- No ServiceLoop / scheduler / queue / retry dispatch.
- No runtime/VM changes.
- No app migration.

## Agent Recommendation

Give this to **Codex GPT 5.5**. It is a narrow implementation/tightening task in
Rust with a clear proof bar. No Opus slot needed unless the source shape has drifted.
