# LAB-VM-RUN-OK-RECHECK-P2

**Status:** CLOSED - RUNTIME RECHECK (2026-06-15)
**Route:** lab / VM / RUN-OK fleet recheck
**Date:** 2026-06-15
**Authority:** evidence-only runtime recheck; no source changes

## Goal

Run the next focused runtime RUN-OK recheck after the spreadsheet and numeric-parity wave.

Baseline from P1:

- RUN-OK: 23/25.
- Non-green: `spreadsheet` runtime blocker `Unsupported operator: eval_expr`; `rule_engine` compile-not-ok governance-gated dynamic dispatch.

Expected deltas if preceding cards land:

- `spreadsheet` should move to RUN-OK after `LAB-VM-EVALAST-EVAL-EXPR-P1`.
- `bookkeeping` may improve on compile/runtime status after Ruby numeric parity and sum-scalar decisions.
- `rule_engine` should remain unchanged unless a separate governance card authorizes dynamic dispatch work.

## Gate

Start after at least one of:

- `LAB-VM-EVALAST-EVAL-EXPR-P1` CLOSED.
- `LANG-RUBY-NUMERIC-OPS-PARITY-P1` CLOSED.
- `LANG-STDLIB-COLLECTION-SUM-SCALAR-P1` CLOSED or routed.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-VM-RUN-OK-RECHECK-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/vm-run-ok-recheck-p1-2026-06-15-v0.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`
- Current app pressure registries.

## Work

1. Enumerate active runtime fleet and entrypoints.
2. Run stable Open3/mktmpdir runtime invocations.
3. Capture compile status separately from runtime status.
4. Compare with P1 RUN-OK 23/25.
5. Update `IMPLEMENTED_SURFACE.md`, relevant registries, and portfolio if statuses changed.

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/vm-run-ok-recheck-p2-2026-06-15-v0.md`.
- Proof/recheck runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p2.rb`.
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

## Closure Summary — CLOSED 2026-06-15

Fresh registry-backed runtime fleet recheck completed with
`igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p2.rb`.

### Result

- Active runtime fleet: **25** apps.
- RUN-OK 23/25.
- Delta vs P1: **0** / no count change.
- No source edits.

`LAB-VM-EVALAST-EVAL-EXPR-P1` closed as a routed spike rather than a VM implementation,
so `spreadsheet` remains runtime-not-ok. Its owner class is now sharper:
function SIR/runtime substrate, routed to `LAB-FUNCTION-SIR-RUNTIME-P1`.

### Current Non-Green

| app | status | owner class | next route |
|---|---|---|---|
| `spreadsheet` | RUN-NOT-OK | function SIR/runtime substrate | `LAB-FUNCTION-SIR-RUNTIME-P1` |
| `rule_engine` | COMPILE-NOT-OK | governance-gated | `LAB-DYNAMIC-CONTRACT-DISPATCH` / ledger D-001 |

### Artifacts

- Rollup: `.agents/docs/vm-run-ok-recheck-p2-2026-06-15-v0.md`
- Proof: `igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p2.rb`
