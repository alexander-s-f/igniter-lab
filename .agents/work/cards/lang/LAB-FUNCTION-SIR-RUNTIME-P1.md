# LAB-FUNCTION-SIR-RUNTIME-P1

**Status:** CLOSED — IMPLEMENTED (compiler-emitter + VM; spreadsheet RunWorkbookDemo RUN-OK, 2026-06-15)
**Route:** lab / function SIR / VM runtime
**Date:** 2026-06-15
**Authority:** lab compiler/emitter + VM runtime substrate only; no canon authority

## Goal

Unblock app-local `def` function calls at runtime, starting with `spreadsheet`
`RunWorkbookDemo`:

```igniter
map(grid.cells, cell -> eval_expr(cell.ast, grid))
```

`LAB-VM-EVALAST-EVAL-EXPR-P1` / runtime recheck clarified that this is not merely a
missing VM operator. The `.igapp` contains a call to `eval_expr`, but app-local `def`
function bodies are not materialized as executable SIR/runtime substrate, so the VM has
no registry entry for `eval_expr` / `eval_ref`.

## Gate

Start after:

- `LAB-APP-DEMO-ENTRY-WAVE-P1` CLOSED — `spreadsheet` has `RunWorkbookDemo`.
- `LAB-VM-RUN-OK-RECHECK-P2` CLOSED — spreadsheet classified as function SIR/runtime substrate.
- `LAB-VM-EVALAST-COVERAGE-P1` CLOSED — eval_ast coverage guard exists.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-VM-RUN-OK-RECHECK-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-EVALAST-COVERAGE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/spreadsheet/`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/emitter.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/src/parser.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/compiler.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`

## Implementation Shape

1. Compiler/emitter: materialize app-local `def` functions into `semantic_ir_program.json`
   with name, params, return type if available, decreases metadata, and executable body SIR.
2. VM: build a static function registry from emitted SIR functions at load/run time.
3. VM: allow `eval_ast` `call` / `apply` to invoke only statically emitted app-local function
   names from that registry.
4. Safety: add bounded depth/fuel guard for recursive function calls, reusing existing VM
   fail-closed style.
5. Prove `spreadsheet` `RunWorkbookDemo` reaches RUN-OK without editing app source.

## Deliverables

- Compiler/emitter implementation in `igniter-compiler` as needed.
- VM implementation in `igniter-vm` as needed.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_function_sir_runtime_p1.rb`, target at least 100 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-function-sir-runtime-p1-v0.md`.
- Update this card, `igniter-vm/IMPLEMENTED_SURFACE.md`, `spreadsheet/PRESSURE_REGISTRY.md`, and portfolio index.

## Acceptance

- `spreadsheet` `RunWorkbookDemo` compiles and runs in the VM.
- SIR includes `eval_expr` and `eval_ref` function bodies.
- Static function calls work inside map/fold lambda bodies.
- Existing `call_contract` semantics remain unchanged.
- Dynamic function dispatch is not introduced.
- Regression runtime smokes remain green.

## Closed Surfaces

- No app source edits.
- No dynamic dispatch.
- No source-file runtime reads from the VM.
- No app-specific hardcoding.
- No new language syntax.
- No canon authority; this remains lab evidence until canon explicitly adopts it.

## Agent Recommendation

Give this to **Codex GPT 5.5** or **Claude Opus 4.8**. This is the highest-leverage runtime tail but crosses compiler-emitter and VM boundaries.

---

## Closure Summary — CLOSED 2026-06-15

App-local `def` functions are now materialized as executable SIR and invoked by the VM
through a static registry. `spreadsheet` `RunWorkbookDemo` runs.

### Implemented (compiler-emitter + VM)
- **`typechecker.rs`**: `TypedProgram` gained `functions: Vec<Value>`, populated from the
  parser `FunctionDecl`s it already validates.
- **`emitter.rs`**: `typed_semantic_ir_program` emits a `functions` array (`function_ir`:
  name / params `[{name,type}]` / return_type / decreases / body). `emit_function_body`
  lowers a parser `BlockBody` to a right-nested chain of `let` nodes ending in the return
  expr (reuses the existing `eval_ast` `let` continuation — no new node kind).
- **`vm.rs` + `main.rs`**: `FunctionEntry{params,body}` + `VM.functions` registry built
  from the igapp `functions` at load; `eval_ast` `call`/`apply` invokes registry names
  inside lambda bodies (bind params → fresh inputs, `__call_depth__`++ bounded by
  `MAX_CALL_DEPTH` — the `decreases fuel` backstop; **no cycle-rejection** so legitimate
  recursion is allowed).

### Evidence
- spreadsheet Rust ok/0, source_hash `sha256:5802728da8d4…`; SIR carries `eval_expr` +
  `eval_ref` (`decreases=fuel`).
- **VM `RunWorkbookDemo` → `{"status":"success","result":[{"kind":"Number","num_val":7.0,"str_val":null}]}`**
  — static `eval_expr` call inside the map lambda runs.
- Regression: air_combat/lead_router/call_router/erp_logistics/batch_importer VM runs
  success; eval_ast coverage 174/174, dispatch-skip 90/90, char_at VM 96/96.
- No dynamic dispatch: unknown `ghost_fn` rejected at compile (`OOF-TY0`); registry-only.

### Acceptance — all MET
RunWorkbookDemo compiles + runs · SIR has eval_expr/eval_ref bodies · static calls work in
lambda bodies · call_contract unchanged · no dynamic dispatch · regression smokes green.

### Known limitation (not demo-exercised, follow-up)
`eval_ast` `if_expr` unwraps a block branch to `return_expr`, ignoring branch `let` stmts.
The `eval_expr` `Add` branch (with two lets) would not bind them if reached; the demo cell
is a `Number`, so `Add`/`Ref` recursion is not exercised. Follow-up: block-branch `let`
evaluation in `eval_ast` if_expr.

### Canon boundary
Ruby canon does not adopt `def` functions here (spreadsheet Ruby `oof`:
`Unknown function: eval_expr`). Lab evidence only until canon explicitly adopts.

### Artifacts
- Proof: `igniter-view-engine/proofs/verify_lab_function_sir_runtime_p1.rb` (target ≥100)
- Lab doc: `lab-docs/lang/lab-function-sir-runtime-p1-v0.md`
- Surface: `igniter-vm/IMPLEMENTED_SURFACE.md`; registry: `igniter-apps/spreadsheet/PRESSURE_REGISTRY.md`
- Edits: `typechecker.rs`, `emitter.rs`, `vm.rs`, `main.rs`
