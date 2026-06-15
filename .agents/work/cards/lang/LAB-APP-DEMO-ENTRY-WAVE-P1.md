# Card: LAB-APP-DEMO-ENTRY-WAVE-P1 — demo entries for needs-input apps

**Status: READY (not started).** App-side only — no VM/compiler change.

## Goal

Make the needs-input apps runnable end-to-end by adding a **zero-input demo /
orchestrator entry** per app (a contract that builds sample inputs and calls the
real handler). These apps compile and execute fine; they just lack a self-contained
entry, so `tools/igniter` (and any reviewer) can't run them without crafted inputs.

## Targets (one demo entry each)

| app | handler that needs input | input needed |
|---|---|---|
| advanced_logistics | PlanDailyRoutes | `available_transports` |
| spreadsheet | RecalculateWorkbook | `grid` |
| vector_editor | HandleCanvasClick | `state` |
| erp_logistics | (route/shipment handler) | `routes` / `shipment` |
| igniter_parser | ParseSource | `source` (also needs `LAB-STDLIB-STRING-CHAR-AT-VM-P1`) |

## Shape (per app)

Add e.g. `contract RunDemo { compute input = {…sample…}  compute out =
call_contract("Handler", input)  output out : … }` with **no inputs**, so the
orchestrator-root heuristic in `tools/igniter` auto-selects it.

## Proof / closed

- Proof: `igniter run igniter-apps/<app>` (no `--entry`) → success.
- Closed: NO VM/compiler/typechecker change; NO change to the handler contracts'
  logic; demo inputs are illustrative, not canonical fixtures.
- Expected: RUN-OK 18 → up to ~22 (igniter_parser also needs char_at).
