# LAB-APP-DEMO-ENTRY-WAVE-P1

**Status:** CLOSED - APP FIXTURE WAVE
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

## Closure Summary - 2026-06-15

Closed as an app-side fixture wave. Added zero-input companion `example.ig` entries
for all four target apps; no compiler, VM, typechecker, or production handler code
was changed.

| App | Entrypoint | Ruby | Rust | VM no-input result |
|---|---|---:|---:|---|
| `advanced_logistics` | `RunDailyRoutesDemo` | ok/0 | ok/0 | success |
| `spreadsheet` | `RunWorkbookDemo` | oof/6 | ok/0 | blocked: `Unsupported operator: eval_expr` |
| `vector_editor` | `RunCanvasClickDemo` | ok/0 | ok/0 | success |
| `igniter_parser` | `RunParseDemo` | ok/0 | ok/0 | blocked: `stdlib.string.char_at` |

Source hashes:

- `advanced_logistics`: `sha256:df623dec726a847355914892805d433c7ead695d9c70e2cf0316b3f332862102`
- `spreadsheet`: `sha256:5802728da8d4eda2ff055057f92d55ca292a61f6ecea136695659e2e7683bd05`
- `vector_editor`: `sha256:967b2b50a666b89cb64ecbd72d2d12f09ed958aec53fd92d63feaa2f2db04144`
- `igniter_parser`: `sha256:915ea3463bc49ce78f6edd2492d4bedb2111934795e7a4b23de1535b0d6dd04c`

Residuals pinned:

- `spreadsheet` now has a zero-input demo entry and Rust ok/0, but VM runtime
  stops at app-local `def eval_expr` (`Unsupported operator: eval_expr`).
  Ruby remains oof because of the existing `eval_expr` blocker plus optional
  recursive `Expr?` record construction exposed by the fixture. Routed as
  `SS-P08` / `SS-P09` in the registry.
- `igniter_parser` now has a zero-input demo entry and compiles ok/0 in both
  toolchains, but VM stops at `stdlib.string.char_at`; routed to
  `LAB-STDLIB-STRING-CHAR-AT-VM-P1` / `IP-P08`.

Artifacts:

- Proof: `igniter-view-engine/proofs/verify_lab_app_demo_entry_wave_p1.rb`
- Lab doc: `lab-docs/governance/lab-app-demo-entry-wave-p1-v0.md`
- Registries updated:
  - `igniter-apps/advanced_logistics/PRESSURE_REGISTRY.md`
  - `igniter-apps/spreadsheet/PRESSURE_REGISTRY.md`
  - `igniter-apps/vector_editor/PRESSURE_REGISTRY.md`
  - `igniter-apps/igniter_parser/PRESSURE_REGISTRY.md`

Closed surfaces preserved:

- No VM changes.
- No compiler or typechecker changes.
- No IO, file, queue, HTTP, scheduler, clock, or database authority.
- No dynamic dispatch relaxation.
- No broad app refactor.
- No production handler semantics changed.
