# LAB-VM-EVALAST-COVERAGE-P1

**Status:** CLOSED - READINESS / GUARD  
**Date:** 2026-06-15  
**Route:** lab / VM / eval_ast coverage parity  
**Authority:** lab VM coverage audit only. No canon authority and no runtime semantic expansion.

## Verdict

The current VM surface has 32 top-level expression kinds handled by bytecode
lowering in `igniter-vm/src/compiler.rs:243-870` and 26 top-level expression
kinds handled by the tree-walked lambda/eval path in `igniter-vm/src/vm.rs:2219-3612`.

The aligned set is exactly the `eval_ast` set. The remaining six bytecode-only
kinds are now explicitly classified so future `compile_expr` expansion cannot
silently bypass the lambda/eval coverage map.

`match_expr` / `match_node` is aligned after `LAB-VM-EVALAST-MATCH-P1`.

No VM semantics changed in this card. No app source changed.

## Source Anchors

| Surface | Code anchor | Finding |
| --- | --- | --- |
| Bytecode lowering | `igniter-vm/src/compiler.rs:243-870` | `compile_expr` handles 32 top-level expression kinds and fails closed on unknown kinds. |
| Tree-walked eval | `igniter-vm/src/vm.rs:2219-3612` | `eval_ast` handles 26 top-level expression kinds and fails closed on unknown kinds. |
| Lambda path | `igniter-vm/src/vm.rs:3617-3640` | `eval_lambda` delegates the lambda body back into `eval_ast`; it does not have an independent kind table. |
| Serialized aggregate | `igniter-vm/src/vm.rs:1899-2106` | `OP_MAP_REDUCE` owns the aggregate node and calls `eval_ast` for source and pipeline expressions. |
| Variant/match emitter | `igniter-compiler/src/emitter.rs:879-893` | `variant_construct` passes through; `match_expr` is renamed to `match_node`. |
| Aggregate emitter | `igniter-compiler/src/emitter.rs:1550-1555` | multi-step/range/fold pipelines emit `map_reduce_aggregate`. |
| Loop emitters | `igniter-compiler/src/emitter.rs:1634-1737` | loop declarations emit `loop_node` / `service_loop_node` for bytecode VM control. |

## Coverage Matrix

| Kind | Bytecode lowering | eval_ast / lambda evaluator | Classification | Route / hold |
| --- | --- | --- | --- | --- |
| `apply` | yes | yes | aligned | none |
| `array` | yes | yes | aligned | none |
| `array_literal` | yes | yes | aligned | none |
| `binary_op` | yes | yes | aligned | none |
| `call` | yes | yes | aligned | none |
| `concat` | yes | yes | aligned | none |
| `emit_observation` | yes | yes | aligned | none |
| `field_access` | yes | yes | aligned | none |
| `filter` | yes | yes | aligned | none |
| `fn` | yes | yes | aligned | none |
| `fold` | yes | yes | aligned | none |
| `if_expr` | yes | yes | aligned | dual field shape and `return_expr` block unwrap are present on both paths |
| `lambda` | yes | yes | aligned | closure capture depth remains separate prior work, not reopened here |
| `let` | yes | yes | aligned | none |
| `literal` | yes | yes | aligned | none |
| `map` | yes | yes | aligned | none |
| `match_expr` | yes | yes | aligned | aligned by `LAB-VM-EVALAST-MATCH-P1` |
| `match_node` | yes | yes | aligned | aligned by `LAB-VM-EVALAST-MATCH-P1` |
| `range` | yes | yes | aligned | none |
| `record` | yes | yes | aligned | none |
| `record_literal` | yes | yes | aligned | none |
| `reduce` | yes | yes | aligned | none |
| `ref` | yes | yes | aligned | none |
| `temporal_read` | yes | yes | aligned | none |
| `unary` | yes | yes | aligned | none |
| `unary_op` | yes | yes | aligned | none |
| `map_reduce_aggregate` | yes | no direct arm | bytecode serialized eval path | hold direct `eval_ast` arm; `OP_MAP_REDUCE` evaluates source/pipeline children through `eval_ast` |
| `loop_node` | yes | no | bytecode-only hold | loop-control expression, not a lambda body expression; no P1 semantic change |
| `service_loop_node` | yes | no | bytecode-only hold | service/runtime escape control; no P1 semantic change |
| `symbol` | yes | no | bytecode-only hold | compiler literalizes symbol to string value |
| `unsupported` | yes | no | intentionally unsupported | emits `OP_UNSUPPORTED` fail-closed |
| `variant_construct` | yes | no | bytecode-only gap | route proposed: `LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2` for nested lambda/HOF constructors |

## Guard

Added proof runner:

`igniter-view-engine/proofs/verify_lab_vm_evalast_coverage_p1.rb`

The guard reads live source files and extracts top-level `match kind` arms from:

- `igniter-vm/src/compiler.rs`
- `igniter-vm/src/vm.rs`

It fails if:

- a new bytecode `compile_expr` kind appears without a classification,
- an `eval_ast` kind appears without bytecode backing,
- the known aligned set drifts,
- the bytecode-only set changes without updating the matrix,
- the card/doc/index closure artifacts are missing.

## Follow-Up

Only one real eval-path gap is small enough to name:

- `LAB-VM-EVALAST-VARIANT-CONSTRUCT-P2` - proposed follow-up for
  `variant_construct` inside nested lambda/HOF bodies. This card did not create
  runtime semantics or patch the VM.

Other bytecode-only kinds are holds:

- `symbol` is literalized by bytecode.
- `map_reduce_aggregate` is owned by `OP_MAP_REDUCE` and evals child expressions.
- `loop_node` and `service_loop_node` are VM control paths.
- `unsupported` is fail-closed by design.

## Closed Surfaces

- No VM semantics changed.
- No language semantics changed.
- No broad VM rewrite.
- No closure conversion implementation.
- No dispatch-table changes.
- No app migrations.
- No app source edits.
