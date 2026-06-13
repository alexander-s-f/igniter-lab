# APP-RECHECK-WAVE-P9

**Status:** CLOSED — 11/12 DUAL-CLEAN — WAVE P9 COMPLETE  
**Route:** governance / fleet recheck  
**Date:** 2026-06-13  
**Scope:** all 12 apps; evidence and registry updates only

## Gate

Run after at least one of the following cards closes, preferably after all three:

- `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P4` — igniter_parser final 5-site migration
- `LAB-VE-NEW-OBJ-INFERENCE-P1` — vector_editor Ruby residual
- `LAB-VECTOR-MATH-FIELD-ALIGNMENT-P1` — vector_math Ruby residual

Also include the already-closed changes since Wave P8:

- `LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2` — Rust HOF lambda OOF-P1 propagation
- `LAB-PARSER-RECORD-IN-HOF-P1` — parser record-in-lambda classification

## Goal

Refresh the 12-app fleet after the current cleanup wave and update pressure registries with exact current diagnostics.

Wave P8 baseline:

- 8/12 DUAL-CLEAN
- `igniter_parser`: blocked by IP-P06 stringly `empty/append`
- `vector_editor`: Rust clean; Ruby VE-P09 `new_obj`
- `vector_math`: Rust clean; Ruby VM-P10 field alignment
- `rule_engine`: blocked by safety boundary / dynamic dispatch, no unblock expected

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p8-2026-06-13-v0.md`
- All 12 app `PRESSURE_REGISTRY.md` files under `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/*/PRESSURE_REGISTRY.md`
- Newly closed cards from this wave.

## Apps

Compile both Ruby and Rust for:

1. advanced_logistics
2. arch_patterns
3. bloom_filter
4. dataframes
5. decision_tree
6. dsa
7. igniter_parser
8. neural_net
9. rule_engine
10. sim_framework
11. vector_editor
12. vector_math

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p9-2026-06-13-v0.md`
- Card update: this file
- Update all 12 `PRESSURE_REGISTRY.md` files with Wave P9 sections.
- Portfolio update after closure.

## Acceptance

- Every app has fresh Ruby and Rust compile status.
- All resolved pressure IDs are marked with the closing card.
- Any newly exposed blockers get exact ID, diagnostic text, and route.
- Do not modify app/compiler source in this recheck card.

## Expected Outcomes

- If P4 succeeds: `igniter_parser` may become DUAL-CLEAN.
- If VE P1 succeeds: `vector_editor` may become DUAL-CLEAN.
- If VM P1 succeeds: `vector_math` may become DUAL-CLEAN.
- `rule_engine` is expected to remain blocked; classify diagnostic form only.

## Results

| App | Wave P8 | Wave P9 | Delta |
|---|---|---|---|
| advanced_logistics | DUAL-CLEAN | DUAL-CLEAN | — |
| arch_patterns | DUAL-CLEAN | DUAL-CLEAN | — |
| bloom_filter | DUAL-CLEAN | DUAL-CLEAN | — |
| dataframes | DUAL-CLEAN | DUAL-CLEAN | — |
| decision_tree | DUAL-CLEAN | DUAL-CLEAN | — |
| dsa | DUAL-CLEAN | DUAL-CLEAN | — |
| neural_net | DUAL-CLEAN | DUAL-CLEAN | — |
| sim_framework | DUAL-CLEAN | DUAL-CLEAN | — |
| igniter_parser | BLOCKED oof/5+7 | **DUAL-CLEAN** | IP-P06 RESOLVED |
| vector_editor | RUST-CLEAN oof/1 Ruby | **DUAL-CLEAN** | VE-P09 RESOLVED |
| vector_math | RUST-CLEAN oof/36 Ruby | **DUAL-CLEAN** | VM-P10 RESOLVED |
| rule_engine | BLOCKED oof/2+2 | BLOCKED oof/2+2 | Diagnostics unchanged |

**Fleet: 11/12 DUAL-CLEAN** (+3 vs Wave P8).

All 3 expected outcomes confirmed. rule_engine diagnostic form unchanged from Wave P8.

## Proof Matrix

| Deliverable | Status |
|---|---|
| Rollup doc written | Done — `app-pressure-recheck-wave-p9-2026-06-13-v0.md` |
| All 12 PRESSURE_REGISTRY.md updated | Done |
| Wave P9 Rust compile (all 12) | Fresh — all confirmed |
| Wave P9 Ruby compile (all 12) | Fresh — all confirmed |
| Card closed | Done |
| Portfolio updated | Done |

## Closed Surfaces

- No source edits.
- No compiler edits.
- No new canon decisions.
- No IO/Rack/microservice work in this app-pressure wave.
