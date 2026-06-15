# LAB-VM-EVALAST-EVAL-EXPR-P1

**Status:** CLOSED - ROUTED SPIKE (2026-06-15)
**Route:** lab / VM / eval_ast / spreadsheet runtime
**Date:** 2026-06-15
**Authority:** VM runtime support only; no compiler, typechecker, or app source changes

## Goal

Investigate and fix the remaining runtime blocker for `spreadsheet`:

```text
Unsupported operator: eval_expr
```

`spreadsheet` now has a zero-input demo entry from `LAB-APP-DEMO-ENTRY-WAVE-P1`, compiles
cleanly, and reaches the VM. The residual is in the runtime tree-walker path, not in app
fixture construction.

## Gate

Start after:

- `LAB-APP-DEMO-ENTRY-WAVE-P1` CLOSED.
- `LAB-VM-EVALAST-COVERAGE-P1` CLOSED — coverage guard exists.
- `LAB-VM-RUN-OK-RECHECK-P1` CLOSED — spreadsheet is the only runtime-not-ok app.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-APP-DEMO-ENTRY-WAVE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-EVALAST-COVERAGE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-VM-RUN-OK-RECHECK-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/spreadsheet/`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/compiler.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`

## Work

1. Reproduce `spreadsheet` runtime failure with the current demo entry.
2. Identify whether `eval_expr` is an AST kind, an operator tag, or a wrapper emitted by the compiler.
3. Compare bytecode handling vs `eval_ast` handling for the same shape.
4. Implement the narrowest VM support needed in `eval_ast`, or write a precise follow-up if the shape represents a larger semantic surface.
5. Prove spreadsheet runtime success if the fix is in scope.
6. Update `IMPLEMENTED_SURFACE.md` coverage section.

## Deliverables

- VM implementation in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/vm.rs` if the gap is narrow.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_evalast_eval_expr_p1.rb`, target at least 70 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-vm-evalast-eval-expr-p1-v0.md`.
- Update this card, `IMPLEMENTED_SURFACE.md`, and portfolio index.

## Acceptance

- `spreadsheet` demo entry either runs successfully or has a sharper routed blocker.
- Any implementation is limited to VM runtime handling of the live `eval_expr` shape.
- `batch_importer`, `igniter_parser`, `lead_router`, `call_router`, and `vector_editor` runtime proofs remain green.
- No compiler/typechecker/app source changes.

## Closed Surfaces

- No app source edits.
- No compiler or typechecker changes.
- No new language syntax.
- No dynamic dispatch or Unknown-policy change.
- No broad eval_ast rewrite beyond the live failing shape.

## Agent Recommendation

Give this to **Codex GPT 5.5**. It is the current highest-leverage runtime tail: likely RUN-OK 23 -> 24 if narrow.

---

## Closure Summary — CLOSED 2026-06-15

This closed as a routed spike, not a VM source patch.

### Finding

`eval_expr` is **not** an AST kind and not a stdlib/runtime operator. It is an app-local
`def` function call emitted as a `call` node inside the `CalculateGrid` map lambda:

```json
{ "kind": "call", "fn": "eval_expr", "args": [...] }
```

The current `.igapp/semantic_ir_program.json` does **not** materialize app-local function
bodies: no `functions` key, no function sidecar, and no `eval_expr` / `eval_ref` body
available to the VM. Therefore a VM-only implementation would require app-specific
hardcoding or runtime source-file reads, both closed by this card.

### Result

- `spreadsheet` compile: ok.
- `RunWorkbookDemo` VM: still blocked, but now classified precisely:
  `Unsupported operator: eval_expr` = missing function SIR/runtime substrate.
- RUN-OK count remains **23/25**.
- Required runtime smokes remain green:
  `batch_importer`, `igniter_parser`, `lead_router`, `call_router`, `vector_editor`.
- No app source, compiler source, typechecker source, or VM source edits.

### Route

Opened follow-up card:

- `LAB-FUNCTION-SIR-RUNTIME-P1` — compiler/emitter function SIR materialization +
  VM static app-local function runtime.

### Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_vm_evalast_eval_expr_p1.rb`
- Lab doc: `lab-docs/lang/lab-vm-evalast-eval-expr-p1-v0.md`
- Follow-up: `.agents/work/cards/lang/LAB-FUNCTION-SIR-RUNTIME-P1.md`
