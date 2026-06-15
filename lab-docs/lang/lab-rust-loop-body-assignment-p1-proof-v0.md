# LAB-RUST-LOOP-BODY-ASSIGNMENT-P1 Proof

**Date:** 2026-06-15  
**Card:** `LAB-RUST-LOOP-BODY-ASSIGNMENT-P1`  
**Runner:** `igniter-lab/igniter-compiler/verify_rust_loop_body_assignment_p1.rb`  
**Result:** CLOSED — 90/90 PASS  
**Authority:** lab Rust implementation proof only; canon Ruby remains the baseline

## Verdict

Rust loop-body assignment checks now match canon Ruby for PROP-039 loop bodies:
every `compute` inside a loop body must target a declared `lead` binding.

The previous Rust-only escape was removed. Loop bodies with no `lead` bindings
can no longer reassign outer contract symbols, loop item variables, or undeclared
body-local targets.

## Implementation

Changed:

```text
igniter-lab/igniter-compiler/src/typechecker.rs
```

The Rust typechecker no longer computes or branches on `is_gate8_body`. The
existing OOF-L7/OOF-L5 target checks now run for every loop-body `compute`.

Preserved:

- OOF-L7 message for loop item targets.
- OOF-L7 message for outer contract symbol targets.
- OOF-L5 message for non-declared lead targets.
- Valid assignments to declared `lead` bindings.
- Lead static-literal validation.
- Ruby canon behavior.

## Proof Matrix

| Section | Topic | Checks |
|---|---|---:|
| A | Source shape and boundaries | 12 |
| B | Rust fixture diagnostics | 18 |
| C | Ruby baseline and fixed-state P1 runner | 6 |
| D | job_runner route checks | 5 |
| E | 20-app fleet smoke | 44 |
| F | Closed surfaces | 5 |
| **Total** | | **90** |

## Fixture Results

| Fixture | Expected | Result |
|---|---|---|
| `outer_no_lead` | OOF-L7, outer contract symbol read-only | PASS |
| `item_no_lead` | OOF-L7, loop item read-only | PASS |
| `undeclared_no_lead` | OOF-L5, target not declared lead | PASS |
| `valid_lead` | ok / 0 diagnostics | PASS |
| `outer_with_lead` | OOF-L7 still fires | PASS |
| `non_literal_lead` | OOF-L5 still fires | PASS |

## Ruby Baseline

The Ruby typechecker was not relaxed. Its `check_loop_body` logic still rejects:

- loop item mutation,
- outer contract symbol mutation,
- undeclared lead targets.

The predecessor runner was updated to fixed-state source checks and still passes:

```text
ruby experiments/budgeted_local_loop_proof/verify_budgeted_local_loop_ruby_p1.rb
PASS 62/62
```

## Fleet Result

The 20-app Rust smoke stayed stable:

| Result | Count |
|---|---:|
| ok | 19 |
| expected fail-closed | 1 (`rule_engine`) |

`job_runner` remains clean because the app source does not use managed loop
syntax; it still models retries by pure manual unrolling.

## Closed Surfaces

- No Ruby relaxation.
- No new loop syntax.
- No fold-to-struct implementation.
- No ServiceLoop, scheduler, queue, worker, or retry dispatch.
- No runtime/VM changes.
- No app source edits or migration.

## Command

```text
cd igniter-lab/igniter-compiler
ruby verify_rust_loop_body_assignment_p1.rb
Summary: 90/90 checks passed
```
