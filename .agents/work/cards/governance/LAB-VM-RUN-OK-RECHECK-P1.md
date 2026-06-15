# LAB-VM-RUN-OK-RECHECK-P1

**Status:** CLOSED - RUNTIME RECHECK (2026-06-15)
**Route:** lab / VM / RUN-OK fleet recheck
**Date:** 2026-06-15
**Authority:** evidence-only runtime recheck; no source changes

## Goal

Run a focused runtime RUN-OK recheck after the current VM/app wave. This is separate
from compile-only `APP-RECHECK-WAVE-*` because the runtime wave now tracks whether an
app can actually execute through a selected entrypoint.

Expected starting point from the checkpoint: RUN-OK 18, with remaining apps classified
as needs-inputs, Decimal construction, string char_at, or governance-gated dynamic dispatch.

## Gate

Start after any meaningful subset of:

- `LAB-APP-DEMO-ENTRY-WAVE-P1` CLOSED.
- `LAB-STDLIB-STRING-CHAR-AT-VM-P1` CLOSED.
- `LAB-NUMERIC-DECIMAL-CONSTRUCT-P1` CLOSED.
- `LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1` CLOSED.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`
- Current app `PRESSURE_REGISTRY.md` files.
- `tools/igniter` wrapper if runtime invocation behavior changed.

## Work

1. Enumerate active runtime fleet and selected entrypoints.
2. Run `igniter run` or equivalent stable Open3 invocation for every runnable app.
3. Classify every non-RUN-OK app by owner class: needs-inputs, stdlib VM gap, numeric policy, governance-gated, real runtime bug.
4. Compare against checkpoint RUN-OK 18.
5. Update `igniter-vm/IMPLEMENTED_SURFACE.md` and relevant registries if statuses changed.
6. Write rollup and close this card.

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/vm-run-ok-recheck-p1-2026-06-15-v0.md`.
- Proof/recheck runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p1.rb`, target all active runtime apps.
- Update this card and portfolio index.
- Update app registries only where runtime status changed.

## Acceptance

- RUN-OK count is explicit and reproducible.
- Every non-green app has exactly one owner class and next route.
- No source files are modified.
- `rule_engine` remains governance-gated unless explicitly changed by another card.
- The recheck distinguishes compile-clean from runtime-run-clean.

## Closed Surfaces

- No compiler changes.
- No VM changes.
- No app migrations.
- No pressure resolution without live runtime evidence.

## Agent Recommendation

Give this to **Codex GPT 5.5** after at least one implementation/app card in the wave lands.

---

## Closure Summary — CLOSED 2026-06-15

Fresh registry-backed runtime fleet recheck completed with
`igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p1.rb`.

### Result

- Active runtime fleet: **25** apps, defined by `PRESSURE_REGISTRY.md` presence.
- RUN-OK 23/25.
- Checkpoint delta: **18/25 -> 23/25** (**+5 RUN-OK**).
- No source files modified.

New green apps after the checkpoint:

- `advanced_logistics` — `RunDailyRoutesDemo`
- `vector_editor` — `RunCanvasClickDemo`
- `erp_logistics` — `RunBestRoute`
- `igniter_parser` — `RunParseDemo`
- `bookkeeping` — `ComputeAccountBalance`

### Current Non-Green

| app | status | owner class | next route |
|---|---|---|---|
| `spreadsheet` | RUN-NOT-OK | real runtime bug | VM app-local function-call / `eval_expr` support |
| `rule_engine` | COMPILE-NOT-OK | governance-gated | `LAB-DYNAMIC-CONTRACT-DISPATCH` / ledger D-001 |

No app remains in the old needs-inputs/demo-entry owner bucket. `rule_engine` remains
governance-gated; no dynamic dispatch relaxation was made.

### Artifacts

- Rollup: `.agents/docs/vm-run-ok-recheck-p1-2026-06-15-v0.md`
- Proof: `igniter-view-engine/proofs/verify_lab_vm_run_ok_recheck_p1.rb`
- Surface index: `igniter-vm/IMPLEMENTED_SURFACE.md`
- Registry update: `igniter-apps/igniter_parser/PRESSURE_REGISTRY.md`
