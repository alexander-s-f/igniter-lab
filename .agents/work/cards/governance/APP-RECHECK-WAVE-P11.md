# APP-RECHECK-WAVE-P11

**Status:** OPEN — DISPATCH READY  
**Route:** governance / fleet recheck  
**Date:** 2026-06-14  
**Scope:** all 15 apps; evidence and registry updates only

## Goal

Refresh the app fleet after `air_combat` and `lead_router` baseline integration and any Fold P3/P4 changes that land before execution.

Starting point:

- `APP-RECHECK-WAVE-P10`: 12/13 DUAL-CLEAN (`rule_engine` only blocked).
- `LAB-AIR-COMBAT-BASELINE-P1`: `air_combat` DUAL-CLEAN, 99/99 PASS, AC-P01..AC-P09 pressure table.
- `LAB-LEAD-ROUTER-BASELINE-P1`: `lead_router` pending baseline freeze; expected DUAL-CLEAN with LR-P01..LR-P10 pressure table.

Expected fleet after `lead_router` baseline closes, if no new implementation changes land first: **14/15 DUAL-CLEAN**, with `rule_engine` still the only intentional blocked app.

## Gate

Start after at least:

- `LAB-AIR-COMBAT-BASELINE-P1` CLOSED — 99/99.
- `LAB-LEAD-ROUTER-BASELINE-P1` CLOSED — target ≥90.

Preferred if available before execution:

- `LANG-FOLD-STRUCT-ACCUMULATOR-P3` CLOSED, to capture any Rust TC app-pressure impact.

## Apps

Compile both Ruby and Rust for all current apps, including:

- `air_combat`
- `lead_router`
- `trade_robot`
- the 12-app fleet from Wave P10

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p11-2026-06-14-v0.md`.
- Update all app `PRESSURE_REGISTRY.md` files with Wave P11 sections where appropriate.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Every app has fresh Ruby and Rust compile status.
- `air_combat` and `lead_router` are included as the 14th and 15th apps.
- `rule_engine` diagnostics are refreshed exactly.
- If Fold P3 lands first, note whether any app pressure changes; do not edit app source.
- No source/compiler/runtime edits in this recheck card.

## Closed Surfaces

- No app migrations.
- No compiler changes.
- No IO/runtime work.
- No canon decisions.
