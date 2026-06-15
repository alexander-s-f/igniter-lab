# APP-RECHECK-WAVE-P12

**Status:** OPEN  
**Route:** governance / fleet recheck / 20-app wave  
**Date:** 2026-06-15  
**Scope:** full fleet compile evidence and registry updates only

## Goal

Refresh the app fleet after the new companion intake and the current Sumtype / Result / loop planning wave.

The wave must include the existing fleet plus the four new apps:

- `audit_ledger`
- `batch_importer`
- `job_runner`
- `web_router`

Expected starting point: all apps except `rule_engine` are dual-clean unless a
fresh compile proves otherwise. `rule_engine` remains the known fail-closed dynamic
dispatch boundary.

## Gate

Start after the current focus-wave implementation/readiness cards assigned before
this recheck have reported back, or run immediately if the goal is only morning
baseline confirmation.

Recommended upstream reads:

- `APP-RECHECK-WAVE-P10`
- latest app pressure registries under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/*/PRESSURE_REGISTRY.md`
- new companion registries: `audit_ledger`, `batch_importer`, `job_runner`, `web_router`
- `LAB-RULE-ENGINE-BASELINE-P1`
- `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`

## Apps

Compile both Ruby and Rust for the active fleet:

1. `advanced_logistics`
2. `air_combat`
3. `arch_patterns`
4. `audit_ledger`
5. `batch_importer`
6. `bloom_filter`
7. `call_router`
8. `dataframes`
9. `decision_tree`
10. `dsa`
11. `igniter_parser`
12. `job_runner`
13. `lead_router`
14. `neural_net`
15. `rule_engine`
16. `sim_framework`
17. `trade_robot`
18. `vector_editor`
19. `vector_math`
20. `web_router`

If the current registry count differs, verify from the filesystem and document
the fleet membership explicitly instead of guessing.

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p12-2026-06-15-v0.md`.
- Update all app `PRESSURE_REGISTRY.md` files with Wave P12 sections.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Every app has fresh Ruby and Rust compile status.
- `rule_engine` diagnostics are refreshed exactly with codes, messages, and nodes.
- New companion apps have their dual-clean status and pressure routes reflected.
- No app source edits.
- No compiler/runtime source edits.
- Any new blocker gets a precise pressure ID, diagnostic text, and route.
- Do not treat stale cards or old docs as current blockers without checking live code first.

## Closed Surfaces

- No migrations.
- No implementation.
- No app edits.
- No canon decisions.
- No source formatting churn.

## Agent Recommendation

Give this to **Sonnet 4.6** or **Gemini**. It is broad, mechanical, and evidence-heavy;
save Opus for design-heavy cards.
