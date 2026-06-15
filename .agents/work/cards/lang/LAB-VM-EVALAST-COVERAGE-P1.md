# LAB-VM-EVALAST-COVERAGE-P1

**Status:** CLOSED - READINESS / GUARD
**Route:** lab / VM / eval_ast coverage parity
**Date:** 2026-06-15
**Authority:** VM coverage audit and guard; no semantic expansion unless separately authorized

## Goal

Stop the repeating pattern where bytecode compilation supports an expression kind, but
`eval_ast` does not, causing HOF/lambda runtime failures only after dispatch becomes
more complete.

Recent examples:

- `if_expr`: bytecode path existed; `eval_ast` only accepted one field shape.
- `match_expr`: bytecode path existed; `eval_ast` lacked it until `LAB-VM-EVALAST-MATCH-P1`.
- `filter_map`: typechecker/compiler surface existed; VM HOF path needed explicit runtime support.
- Closure captures remain a separate but adjacent eval path issue.

## Gate

Start after:

- `LAB-VM-EVALAST-MATCH-P1` DONE.
- `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 2 DONE.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-EVALAST-MATCH-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/compiler.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/emitter.rs`
- Current runtime RUN-OK report if present.

## Work

1. Enumerate expression kinds handled by bytecode lowering in `compiler.rs`.
2. Enumerate expression kinds handled by tree-walking `eval_ast` / lambda evaluator in `vm.rs`.
3. Produce a coverage matrix: supported by both, bytecode-only, eval_ast-only, intentionally unsupported.
4. Add a guard proof runner that fails when a new bytecode kind is not classified for eval_ast.
5. If a gap is tiny and already semantically defined, propose a follow-up implementation card; do not patch multiple kinds inside this P1 unless explicitly reauthorized.

## Deliverables

- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-vm-evalast-coverage-p1-v0.md`.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_evalast_coverage_p1.rb`, target at least 55 checks.
- Update this card with closure summary.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/portfolio-index.md`.

## Acceptance

- Coverage matrix is code-anchored to live `compiler.rs` and `vm.rs`.
- `match_expr` is recorded as aligned after P1/P1-match work.
- Any remaining gaps have named route cards or explicit hold reason.
- Guard does not rely on stale docs.
- No app source edits.

## Closed Surfaces

- No language semantics changes.
- No broad VM rewrite.
- No closure conversion implementation.
- No dispatch-table changes.
- No app migrations.

## Agent Recommendation

Give this to **Codex GPT 5.5** or **Claude Sonnet 4.6**. It is mostly source survey plus a durable anti-drift guard.

## Closure Summary - 2026-06-15

Closed as a source-anchored guard with no VM/compiler/app semantic edits.

- Enumerated live bytecode lowering kinds from `igniter-vm/src/compiler.rs`: 32 top-level `compile_expr` arms.
- Enumerated live tree-walked eval kinds from `igniter-vm/src/vm.rs`: 26 top-level `eval_ast` arms; `eval_lambda` delegates body execution back to `eval_ast`.
- Recorded coverage matrix in `lab-docs/lang/lab-vm-evalast-coverage-p1-v0.md`.
- Confirmed `match_expr` / `match_node` is aligned after `LAB-VM-EVALAST-MATCH-P1`.
- Classified bytecode-only kinds:
  - `symbol`: compiler literalizes to string.
  - `map_reduce_aggregate`: `OP_MAP_REDUCE` owns the aggregate node and evaluates source/pipeline children through `eval_ast`.
  - `loop_node`: bytecode loop-control hold.
  - `service_loop_node`: bytecode service/runtime-control hold.
  - `unsupported`: intentional fail-closed `OP_UNSUPPORTED`.
  - `variant_construct`: named follow-up route `LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2` for nested lambda/HOF constructors.
- Added guard proof runner `igniter-view-engine/proofs/verify_lab_vm_evalast_coverage_p1.rb`; target exceeded with live source extraction and card/doc/index checks.

Closed surfaces preserved:

- No language semantics changes.
- No broad VM rewrite.
- No closure conversion implementation.
- No dispatch-table changes.
- No app migrations.
- No app source edits.
