# LAB-VM-EVALAST-EVAL-EXPR-P1 — Routed Spike

**Date:** 2026-06-15  
**Authority:** VM/runtime investigation only; no compiler, typechecker, app source, or canon authority  
**Proof:** `igniter-view-engine/proofs/verify_lab_vm_evalast_eval_expr_p1.rb`

## Result

`spreadsheet` still compiles cleanly and still reaches the VM through
`RunWorkbookDemo`, but the runtime failure is now sharper:

```text
VM evaluation failed: Unsupported operator: eval_expr
```

This is **not** a missing `eval_ast` AST-kind handler like `if_expr` or `match_expr`.
The live SIR shape is a `call` node inside the `CalculateGrid` map lambda:

```json
{ "kind": "call", "fn": "eval_expr", "args": [...] }
```

The current `.igapp/semantic_ir_program.json` does not materialize function bodies.
It has `contracts`, `entrypoint`, and `source_units`, but no `functions` table, no
function sidecar, and no `eval_expr` / `eval_ref` body available to the VM.

## Evidence

- Spreadsheet Rust compile: `ok`.
- `CalculateGrid` SIR contains one `stdlib.collection.map` call.
- The map lambda body contains exactly one app-local call: `fn = "eval_expr"`.
- `.igapp` contains no `functions` key and no function sidecar.
- `source_units` records `SpreadsheetEngine` contracts/types only; it does not include
  `eval_expr` or `eval_ref`.
- VM run of `RunWorkbookDemo`: error `Unsupported operator: eval_expr`.

## Decision

No VM source change was made in this card. A VM-only implementation would have to
either hardcode spreadsheet semantics or read `.ig` source paths at runtime. Both are
out of scope and would cross the artifact boundary.

The correct route is **`LAB-FUNCTION-SIR-RUNTIME-P1`**:

1. Compiler/emitter materializes app-local `def` function bodies into SIR.
2. VM builds a static function registry from emitted SIR functions.
3. `eval_ast` executes static app-local function calls from that registry.
4. Dynamic dispatch, source-file runtime reads, and app-specific hardcoding remain closed.

## Regression Smokes

The proof also reruns the required runtime smokes:

- `batch_importer` / `RunImport` — RUN-OK.
- `igniter_parser` / `RunParseDemo` — RUN-OK.
- `lead_router` / `RunAccept` — RUN-OK.
- `call_router` / `RunConnectedMatched` — RUN-OK.
- `vector_editor` / `RunCanvasClickDemo` — RUN-OK.

## Boundaries

- No app source edits.
- No compiler or typechecker edits.
- No VM source edits.
- No new language syntax.
- No dynamic dispatch or Unknown-policy change.
- No canon authority claim; this is lab runtime evidence only.
