# LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2

**Status:** CLOSED — PROVED 40/40 — PARITY IMPLEMENTED  
**Route:** LAB SAFETY / RUST DIAGNOSTIC PARITY IMPLEMENTATION  
**Date:** 2026-06-13  
**Authority:** narrow Rust implementation + proof

## Goal

Implement the recommendation from `LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1`: propagate Rust HOF lambda body errors for `filter` and `map`, matching Ruby behavior.

P1 proved that Rust uses discarded `temp_errors` for `filter` and `map` lambda body typechecking, silencing OOF-P1 and other body-site errors. Ruby passes the main `type_errors` reference and propagates them. Safety is currently maintained by later OOF-TY1, but diagnostic fidelity is impaired.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-hof-lambda-error-propagation-p1-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_hof_lambda_error_propagation_p1.rb`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/typechecker.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/rule_engine/engine.ig`

## Scope

- Rust only: `igniter-compiler/src/typechecker.rs`.
- Change only `filter` and `map` lambda body inference from local `temp_errors` to propagated `type_errors`.
- Preserve `flat_map` / `and_then` behavior.
- Preserve standalone `Expr::Lambda` behavior.
- No Ruby changes, no new OOF codes, no app changes.

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Rust implementation | `igniter-lab/igniter-compiler/src/typechecker.rs` | Written (filter line 3054, map line 3146) |
| Proof runner | `igniter-lab/igniter-compiler/verify_hof_lambda_error_propagation_p2.rb` | 40/40 PASS |
| P1 runner updated | `igniter-lab/igniter-view-engine/proofs/verify_lab_hof_lambda_error_propagation_p1.rb` | 35/35 PASS (post-P2) |
| Proof doc | `igniter-lab/lab-docs/lang/lab-hof-lambda-error-propagation-p2-proof-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/lab/LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

## Implementation

**Filter** (`typechecker.rs:3054`): removed `let mut temp_errors = Vec::new();`,
replaced all `&mut temp_errors` references in lambda body match block with `type_errors`.

**Map** (`typechecker.rs:3146`): same change.

Both changes route lambda body `infer_expr` calls to the caller's `type_errors`
accumulator, matching Ruby TC `infer_lambda_body` behaviour (line 2547).

**Unchanged**: `flat_map`/`and_then` (line 3213), `Expr::Lambda` arm (line 4095).

## Acceptance Verified

- `filter(xs, x -> x.missing)` → OOF-P1 at body site: PASS (A-01, A-02)
- `map(xs, x -> x.missing)` → OOF-P1 at body site: PASS (B-01, B-02)
- OOF-COL3 still fires for non-Bool predicates: PASS (C-01, C-04)
- `flat_map` / standalone lambda unchanged: PASS (D-04, E-01, E-02)
- Rust build passes: PASS (H-04)

## Side Effect: OOF-TY1 Suppression for map

Post-P2: `map(xs, x -> x.missing)` → only OOF-P1 (no OOF-TY1). OOF-P1 at body
site is the primary diagnostic; OOF-TY1 at output boundary is suppressed. Matches
Ruby TC `blocking_rule_present?` behaviour.

## Rule Engine Impact

Rule engine Rust now emits OOF-P1 for `d.action` (filter lambda body, d:Unknown).
Diagnostic set now matches Ruby: OOF-P1 + OOF-TY1.

## Proof Matrix (40 checks / 8 sections)

| Section | Checks | Result |
|---------|--------|--------|
| A — Filter parity | 7 | 7/7 PASS |
| B — Map parity | 7 | 7/7 PASS |
| C — OOF-COL3 preserved | 4 | 4/4 PASS |
| D — flat_map preserved | 4 | 4/4 PASS |
| E — Expr::Lambda preserved | 4 | 4/4 PASS |
| F — Rule engine regression | 4 | 4/4 PASS |
| G — Ruby-Rust parity | 6 | 6/6 PASS |
| H — Source evidence | 4 | 4/4 PASS |

## Open Routes (successors)

| Card | Scope |
|------|-------|
| LAB-RULE-ENGINE-BASELINE-P1 | Re-freeze rule_engine baseline (now has OOF-P1 in Rust too) |
| LAB-HOF-LAMBDA-ERROR-PROPAGATION-P3 | flat_map parity (deferred — Integer placeholder params) |
