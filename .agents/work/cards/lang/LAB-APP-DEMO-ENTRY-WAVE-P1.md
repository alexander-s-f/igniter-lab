# LAB-APP-DEMO-ENTRY-WAVE-P1

**Status:** OPEN - APP FIXTURE WAVE
**Route:** lab / runtime / needs-input apps / demo entrypoints
**Date:** 2026-06-15
**Authority:** app-side demo/orchestrator entries only; no compiler, VM, or language changes

## Goal

Make the remaining needs-input apps runnable end-to-end by adding zero-input demo /
orchestrator entries. These apps are not blocked by a shared VM/compiler bug; they are
libraries or handlers that require crafted inputs. The goal is to make their intended
runtime path observable without inventing external IO authority.

## Targets

| App | Handler shape | Input needed | Notes |
|---|---|---|---|
| `advanced_logistics` | planning/orchestrator | `available_transports` | likely sample fleet / route request |
| `spreadsheet` | recalculation | `grid` | sample workbook/grid fixture |
| `vector_editor` | event handler | `state` | sample canvas state + event |
| `igniter_parser` | parser | `source` | also depends on `LAB-STDLIB-STRING-CHAR-AT-VM-P1` for full VM run |

`erp_logistics` is already handled by `LAB-ERP-LOGISTICS-DEMO-ENTRY-P1` and should be
read as precedent, not repeated here.

## Gate

Start after:

- `LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1` checkpoint created.
- `LAB-ERP-LOGISTICS-DEMO-ENTRY-P1` CLOSED (as pattern for partial/blocked honesty).
- For `igniter_parser` full success: `LAB-STDLIB-STRING-CHAR-AT-VM-P1` CLOSED.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lang/LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/governance/LAB-ERP-LOGISTICS-DEMO-ENTRY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-vm/IMPLEMENTED_SURFACE.md`
- App sources and `PRESSURE_REGISTRY.md` for:
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/advanced_logistics/`
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/spreadsheet/`
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/vector_editor/`
  - `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/igniter_parser/`
- Existing companion patterns: `air_combat`, `lead_router`, `call_router`, `erp_logistics`.

## Work

For each target app:

1. Confirm current Ruby/Rust compile status and current VM runtime failure shape.
2. Identify one meaningful handler path and the minimal typed sample inputs it needs.
3. Add a zero-input `Run*Demo` / `Run*` orchestrator contract that builds sample records
   through named factory contracts where needed.
4. Add or update bare `entrypoint` only if the app has no suitable entrypoint.
5. Keep production handler contracts unchanged.
6. Run `igniter run igniter-apps/<app>` with no external inputs.
7. Update that app's `PRESSURE_REGISTRY.md` with source hash, entrypoint, and result.

## Deliverables

- Minimal app source edits for successful targets.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_app_demo_entry_wave_p1.rb`, target at least 120 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-app-demo-entry-wave-p1-v0.md`.
- Update this card, affected app pressure registries, and portfolio index.

## Acceptance

- Each migrated app has a zero-input demo entry or a documented residual blocker.
- No compiler/VM/typechecker changes are made in this card.
- Production handler logic is unchanged.
- Demo records are explicit fixtures, not hidden runtime authority.
- `advanced_logistics`, `spreadsheet`, and `vector_editor` should reach VM success if their handlers are pure and current VM surface supports them.
- `igniter_parser` may close only after `char_at` VM support lands; otherwise document as pending.

## Closed Surfaces

- No VM changes.
- No compiler or typechecker changes.
- No IO, file, queue, HTTP, scheduler, clock, or database authority.
- No dynamic dispatch relaxation.
- No broad app refactor.
- No changes to domain semantics beyond sample/demo fixture construction.

## Agent Recommendation

Give this to **Sonnet 4.6** or **Codex GPT 5.5**. It is app-by-app fixture work;
precision and not touching production logic matter more than deep compiler skill.
