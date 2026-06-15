# LAB-FUNCTION-SIR-RUNTIME-P1

**Status:** OPEN - IMPLEMENTATION PLANNING / RUNTIME SUBSTRATE
**Route:** lab / function SIR / VM runtime
**Date:** 2026-06-15
**Authority:** lab compiler/emitter + VM runtime substrate only; no canon authority

## Goal

Unblock app-local `def` function calls at runtime, starting with `spreadsheet`
`RunWorkbookDemo`:

```igniter
map(grid.cells, cell -> eval_expr(cell.ast, grid))
```

`LAB-VM-EVALAST-EVAL-EXPR-P1` proved that this is not a VM-only `eval_ast` kind gap.
The `.igapp` contains a call to `eval_expr`, but does not materialize app-local
function bodies in SIR, so the VM has no executable substrate for `eval_expr` or
`eval_ref`.

## Scope

1. Compiler/emitter: materialize app-local `def` functions into
   `semantic_ir_program.json` with name, params, return type, decreases metadata, and
   executable body SIR.
2. VM: build a static function registry from emitted SIR functions.
3. VM: allow `eval_ast` `call` / `apply` to invoke only statically emitted app-local
   function names from that registry.
4. Runtime safety: add a bounded depth/fuel guard for recursive function calls, reusing
   the existing VM fail-closed style.
5. Prove `spreadsheet` `RunWorkbookDemo` reaches RUN-OK without editing app source.

## Acceptance

- `spreadsheet` `RunWorkbookDemo` compiles and runs in the VM.
- SIR includes `eval_expr` and `eval_ref` function bodies.
- Static function calls work inside map/fold lambda bodies.
- Existing `call_contract` semantics remain unchanged.
- Regression runtime smokes remain green.

## Closed Surfaces

- No app source edits.
- No dynamic dispatch.
- No source-file runtime reads from the VM.
- No app-specific hardcoding.
- No new language syntax.
- no canon authority; this remains lab evidence until canon explicitly adopts it.
