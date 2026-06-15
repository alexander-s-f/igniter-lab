# LAB-VM-RUN-OK-RECHECK-P3

**Status:** CLOSED - RUNTIME RECHECK (2026-06-15)
**Route:** lab / VM / RUN-OK fleet recheck
**Date:** 2026-06-15
**Authority:** evidence-only runtime recheck; no source changes

## Goal

Run the next focused runtime RUN-OK recheck after function runtime substrate and scalar sum work.

Baseline from P2:

- RUN-OK: 23/25.
- Non-green: `spreadsheet` runtime blocker `function SIR/runtime substrate`; `rule_engine` compile-not-ok governance-gated dynamic dispatch.

Expected deltas if preceding cards land:

- `spreadsheet` should move to RUN-OK after `LAB-FUNCTION-SIR-RUNTIME-P1`.
- `bookkeeping` may improve after scalar sum implementation.
- `rule_engine` should remain unchanged unless explicitly authorized elsewhere.

## Gate

Start after at least one of:

- `LAB-FUNCTION-SIR-RUNTIME-P1` CLOSED.
- `LANG-STDLIB-COLLECTION-SUM-SCALAR-P2` CLOSED.
- `LAB-RUST-DECIMAL-INPUT-SCALE-P1` CLOSED.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-VM-RUN-OK-RECHECK-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/vm-run-ok-recheck-p2-2026-06-15-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`
- Current app pressure registries.

## Work

1. Enumerate active runtime fleet and entrypoints.
2. Run stable Open3/mktmpdir runtime invocations.
3. Capture compile status separately from runtime status.
4. Compare with P2 RUN-OK 23/25.
5. Update `IMPLEMENTED_SURFACE.md`, relevant registries, and portfolio if statuses changed.

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/vm-run-ok-recheck-p3-2026-06-15-v0.md`.
- Proof/recheck runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p3.rb`.
- Update this card and portfolio index.

## Acceptance

- RUN-OK count is explicit and reproducible.
- Every non-green app has one owner class and next route.
- `rule_engine` remains governance-gated unless explicitly changed.
- No source edits.

## Closed Surfaces

- No compiler changes.
- No VM changes.
- No app migrations.
- No pressure resolution without live runtime evidence.

## Agent Recommendation

Give this to **Codex GPT 5.5** after one or more implementation cards in this wave close.

---

## Closure Summary - CLOSED 2026-06-15

Fresh registry-backed runtime fleet recheck completed with
`igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p3.rb`.

### Result

- Active runtime fleet: **25** apps.
- RUN-OK 24/25.
- Delta vs P2: **+1**.
- No source edits.

`spreadsheet` moved from RUN-NOT-OK to RUN-OK after `LAB-FUNCTION-SIR-RUNTIME-P1`.
Live evidence: `RunWorkbookDemo` compiles, SIR includes static `eval_expr` / `eval_ref`
function bodies, and the VM returns a successful evaluated cell result.

### Current Non-Green

| app | status | owner class | next route |
|---|---|---|---|
| `rule_engine` | COMPILE-NOT-OK | governance-gated dynamic dispatch | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` selected safe route / ledger D-001 |

### Acceptance

- RUN-OK count explicit and reproducible: **24/25** - MET.
- Every non-green app has one owner class and route - MET.
- `rule_engine` remains governance-gated - MET.
- No source edits - MET.

### Artifacts

- Rollup: `.agents/docs/vm-run-ok-recheck-p3-2026-06-15-v0.md`
- Proof: `igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p3.rb`
