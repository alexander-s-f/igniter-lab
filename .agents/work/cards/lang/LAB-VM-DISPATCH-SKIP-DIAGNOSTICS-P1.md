# LAB-VM-DISPATCH-SKIP-DIAGNOSTICS-P1

**Status:** CLOSED — IMPLEMENTED 90/90 PASS
**Route:** lab / VM / dispatch table diagnostics
**Date:** 2026-06-15
**Date closed:** 2026-06-15
**Authority:** VM diagnostic behavior; no compiler or app semantics changes

## Goal

Eliminate the silent false-green class where VM dispatch table construction compiles
contracts one by one and silently skips entries that fail bytecode compilation.

This previously hid real runtime coverage: `batch_importer` appeared green because its
`validate` contract was skipped; after dispatch completeness improved, the real path ran
and exposed `eval_ast match_expr`.

## Gate

Start after:

- `LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1` cluster 2 DONE.
- `LAB-VM-EVALAST-MATCH-P1` DONE or explicitly accounted for.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-EVALAST-MATCH-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/main.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/compiler.rs`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/batch_importer/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/lead_router/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/call_router/PRESSURE_REGISTRY.md`

## Work

1. Locate dispatch table construction in `igniter-vm/src/main.rs`.
2. Preserve successful dispatch entries.
3. For any contract that fails dispatch-entry compilation, surface structured evidence instead of silently skipping.
4. Decide exact policy:
   - preferred: fail VM load/run when any emitted contract cannot build a dispatch entry;
   - acceptable for compatibility: JSON result includes `dispatch_skipped` diagnostics and non-zero status.
5. Ensure non-json mode also prints the skipped contract names and errors.
6. Prove the previous 24/31 style partial table cannot pass as green.

## Deliverables

- VM implementation in `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/src/main.rs` and minimal helpers if needed.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_dispatch_skip_diagnostics_p1.rb`, target at least 60 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/lang/lab-vm-dispatch-skip-diagnostics-p1-v0.md`.
- Update this card and portfolio index.

## Acceptance

- A fixture with one intentionally unbuildable emitted contract no longer reports clean run/load.
- The diagnostic includes contract name and underlying compile error.
- Fully buildable apps remain green.
- `lead_router` and `call_router` remain green after the if_expr dispatch fix.
- `batch_importer` remains green if `LAB-VM-EVALAST-MATCH-P1` is closed; otherwise it fails honestly with match/eval_ast diagnostics, not by skip.

## Closure Summary

Implemented fail-closed dispatch table diagnostics in:

- `igniter-lab/igniter-vm/src/main.rs`

The VM still attempts to build every emitted contract's dispatch entry. Successful
entries are preserved in the local table, but any failed dispatch-entry compile
now stops VM load/run before inputs are read or evaluator execution begins.

JSON mode now emits a structured non-zero error with:

- `status: "error"`
- `dispatch_built`
- `dispatch_skipped[]`
- each skipped contract's `contract_name` and underlying compile `error`

Non-JSON mode prints the skipped contract names and compile errors and explicitly
refuses a partial VM load.

Proof:

```text
cd /Users/alex/dev/projects/igniter-workspace
ruby igniter-lab/igniter-view-engine/proofs/verify_lab_vm_dispatch_skip_diagnostics_p1.rb
RESULT: 90/90 PASS
```

Regression slice:

- synthetic broken `.igapp`: non-zero JSON and text diagnostics with `BadDispatch`;
- synthetic good `.igapp`: `call_contract("GoodCallee")` remains green;
- `batch_importer` / `RunImport`: green;
- `lead_router` / `RunAccept`: green;
- `call_router` / `RunConnectedMatched`: green.

Artifacts:

| Artifact | Path |
|---|---|
| VM implementation | `igniter-lab/igniter-vm/src/main.rs` |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_vm_dispatch_skip_diagnostics_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/lang/lab-vm-dispatch-skip-diagnostics-p1-v0.md` |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` |

## Closed Surfaces

- No typechecker changes.
- No app source changes.
- No dynamic dispatch relaxation.
- No Unknown permissiveness.
- No new language syntax.

## Agent Recommendation

Give this to **Codex GPT 5.5**. This is safety/diagnostic work; exact failure shape matters more than code size.
