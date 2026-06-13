# APP-RECHECK-WAVE-P8

**Status:** OPEN — DISPATCH READY / GATED  
**Route:** GOVERNANCE / APP PRESSURE RECHECK  
**Date:** 2026-06-13

## Goal

Recheck the full app fleet after the latest non-IO wave settles.

## Gate

Run only after these are closed or explicitly skipped:

- `LANG-STDLIB-STRING-SUBSTRING-P2` — CLOSED 75/75
- `LAB-BLOOM-FILTER-RANGE-MIGRATION-P1` — CLOSED 50/50
- `LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2` — pending
- `LAB-IGNITER-PARSER-STRING-SURFACE-MIGRATION-P1` — pending
- `LANG-STRING-TEXT-ALIAS-P2` — CLOSED 52/52
- `LANG-RUBY-RECORD-LITERAL-INFERENCE-P5` — CLOSED 29/29

Do not include IO Runtime wave results unless the user explicitly says to fold them into P8.

## Apps

Recheck all known app-pressure apps:

- advanced_logistics
- arch_patterns
- bloom_filter
- dataframes
- decision_tree
- dsa
- igniter_parser
- neural_net
- rule_engine
- sim_framework
- vector_editor
- vector_math

## Deliverables

- Update all `PRESSURE_REGISTRY.md` files with Wave P8 sections.
- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p8-2026-06-13-v0.md`.
- Card update.
- Portfolio update.

## Acceptance

- Rust and Ruby compile status recorded for every app.
- Resolved pressures from substring/range/string alias/record P5 are reflected.
- Newly exposed blockers get new IDs.
- Clean-app count is updated.
- No compiler or app source changes.
