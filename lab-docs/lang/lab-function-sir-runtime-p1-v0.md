# Lab Doc — LAB-FUNCTION-SIR-RUNTIME-P1 (v0)

**Date:** 2026-06-15
**Route:** lab / function SIR / VM runtime
**Authority:** lab compiler/emitter + VM runtime substrate only. No canon authority — this
remains lab evidence until canon explicitly adopts app-local `def` functions.

## Goal

Unblock app-local `def` function calls at runtime, starting with `spreadsheet`
`RunWorkbookDemo`. The `.igapp` contained a call to `eval_expr` (via
`map(grid.cells, cell -> eval_expr(cell.ast, grid))`), but app-local `def` function bodies
were **not materialized** into the SIR, so the VM had no registry entry — `eval_expr`
trapped at runtime as `Unsupported operator: eval_expr`.

## Root cause

`def` functions were parsed (`parser::FunctionDecl`) and typechecked
(`typecheck(&classified, &parsed.functions)`), but the typed program dropped them — the
emitter never wrote a `functions` array into `semantic_ir_program.json`. The VM therefore
had no function substrate.

## What was implemented (dual: compiler-emitter + VM)

### Compiler — carry functions to the emitter
- `TypedProgram` gained a `functions: Vec<serde_json::Value>` field
  (`typechecker.rs`); the typechecker populates it with the parser `FunctionDecl`s it
  already validates (recursion/`decreases fuel`/`now()` gates unchanged).

### Emitter — materialize functions as executable SIR (`emitter.rs`)
- `typed_semantic_ir_program` now emits a `functions` array. Each entry is a `function_ir`
  with `name`, `params` (`[{name, type}]`), `return_type`, `decreases`, and a runnable
  `body`.
- `emit_function_body` lowers a parser `BlockBody {stmts, return_expr}` to a **right-nested
  chain of `let` nodes** ending in the return expression. The VM `eval_ast` `let` handler
  already threads a continuation `body`, so **no new node kind was needed**. Expr nodes go
  through the same `semantic_expr` lowering contracts receive (so `if_expr` becomes
  `condition/then_branch/else_branch`, `none()` etc. are consistent).

### VM — static function registry + eval_ast dispatch (`vm.rs`, `main.rs`)
- New `FunctionEntry { params, body }` and `VM.functions: HashMap<String, FunctionEntry>`.
- `main.rs` builds the registry from the igapp `functions` array at load (alongside the
  `call_contract` dispatch table).
- `eval_ast`'s `call`/`apply` path: after evaluating operands, if `op` names a registered
  function, bind params to a **fresh inputs map** (functions are pure over their params),
  increment `__call_depth__`, and run the body via `eval_ast`. Bounded by `MAX_CALL_DEPTH`
  (shared with `call_contract`) — the fail-closed backstop for `decreases fuel` recursion
  (`eval_expr` ↔ `eval_ref`). **No cycle-rejection** is applied (unlike `call_contract`),
  because `decreases fuel` recursion is legitimate; depth is the bound.

## Evidence

**Compile (Rust lab):** spreadsheet ok/0, source_hash
`sha256:5802728da8d4eda2ff055057f92d55ca292a61f6ecea136695659e2e7683bd05`. SIR `functions`:
`eval_expr(expr, grid) -> CellValue decreases=fuel` and
`eval_ref(ref_id, grid) -> CellValue decreases=fuel`.

**VM run `RunWorkbookDemo`:**
```json
{"status":"success","result":[{"kind":"Number","num_val":7.0,"str_val":null}]}
```
The map over the single Number cell calls `eval_expr` (a static function call **inside a
lambda body**) → the `expr.kind == "Number"` branch → builds
`{kind:"Number", num_val: 7.0, str_val: none()}`. `none()` executes to `null`.

**Regression smokes (VM RUN-OK, unchanged):** air_combat `RunDuel`, lead_router `RunAccept`,
call_router `RunConnectedMatched`, erp_logistics `RunBestRoute` (2437.5), batch_importer
`RunImport` — all success. eval_ast coverage guard 174/174, dispatch-skip 90/90, string
char_at VM 96/96 — green (no new bytecode kind; `call_contract` semantics unchanged).

**No dynamic dispatch:** an unknown function name (`ghost_fn`) is rejected at **compile**
(`OOF-TY0: Unknown function`), so it never reaches the VM; only statically-emitted registry
names are invocable.

## Acceptance

- `spreadsheet` `RunWorkbookDemo` compiles and runs in the VM — **MET**.
- SIR includes `eval_expr` and `eval_ref` function bodies — **MET**.
- Static function calls work inside map/fold lambda bodies — **MET** (the map lambda calls
  `eval_expr`).
- Existing `call_contract` semantics remain unchanged — **MET** (dispatch table + tests).
- Dynamic function dispatch is not introduced — **MET** (registry-only; compile-time gate).
- Regression runtime smokes remain green — **MET**.

## Known limitation (not demo-exercised)

`eval_ast`'s `if_expr` handler unwraps a block branch to its `return_expr` and ignores the
branch's `let` stmts. The `eval_expr` `Add` branch (`let left_val = …; let right_val = …`)
therefore would not bind its lets if reached. The `RunWorkbookDemo` fixture is a single
`Number` cell, so the `Add`/`Ref` recursion is not exercised; full block-branch `let`
support is a follow-up (a one-spot `eval_ast` if-branch block evaluation).

## Closed surfaces (held)

No app source edits. No dynamic dispatch. No source-file runtime reads from the VM. No
app-specific hardcoding (the registry is generic over emitted functions). No new language
syntax (`def` already parsed). No canon authority — lab evidence until canon adopts.

## Canon boundary

Ruby canon does **not** adopt app-local `def` functions here (Ruby compile of spreadsheet
is `oof`: `Unknown function: eval_expr`). This card is lab compiler/emitter + VM substrate
only; canon adoption is a separate, explicit decision.

## Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_function_sir_runtime_p1.rb`
- Compiler: `igniter-compiler/src/typechecker.rs` (TypedProgram.functions),
  `igniter-compiler/src/emitter.rs` (emit_function_ir / emit_function_body)
- VM: `igniter-vm/src/vm.rs` (FunctionEntry, registry, eval_ast dispatch),
  `igniter-vm/src/main.rs` (registry build)
- Surface: `igniter-vm/IMPLEMENTED_SURFACE.md`
- App registry: `igniter-apps/spreadsheet/PRESSURE_REGISTRY.md`
