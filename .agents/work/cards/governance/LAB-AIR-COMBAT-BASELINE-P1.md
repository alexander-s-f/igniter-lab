# LAB-AIR-COMBAT-BASELINE-P1

**Status:** CLOSED — PROVED 99/99 PASS — AC-P09 ADDED  
**Route:** lab / app baseline / air_combat  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `air_combat` as a positive dual-toolchain baseline and pressure source.

`air_combat` is a multiplayer, strategy-driven swarm simulation: each player owns a fleet of aircraft and authors a `Strategy`; the swarm acts autonomously through pure target tracking, pursuit/evasion guidance, and per-tick world updates.

This card should prove the app is clean today and capture the pressure it creates for fold-to-struct, entity composition, static strategy dispatch, stdlib math, the future IO membrane, and ServiceLoop/Progression readiness.

## Current Claimed Baseline

From `air_combat/PRESSURE_REGISTRY.md` and `report.md`:

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 8 |
| types | 9 |
| contracts | 31 |
| call_contract sites | 61, all Tier-1 literals |
| fold sites | 6, all scalar |
| map / filter sites | 2 / 2 |
| source_hash | `sha256:4fc0b4cb4c63a06060017b932f351d9b708db826428f3d2ad94ac9f92c2a4e04` (see Path Sensitivity below) |

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/report.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/types.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/vec.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/kalman.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/guidance.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/strategy.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/swarm.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/engine.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/example.ig`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-FOLD-STRUCT-ACCUMULATOR-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-COMPOSE-ENTITY-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/work/cards/lab/LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md`

## Deliverables

- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_air_combat_baseline_p1.rb`, target at least 90 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-air-combat-compilation-baseline-v0.md`.
- Update `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/PRESSURE_REGISTRY.md` with closure summary if needed.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Ruby compile is `ok` / 0 diagnostics.
- Rust compile is `ok` / 0 diagnostics.
- Full app source hash is stable across two fresh runs or explicitly documented if path-sensitive.
- Proof runner does not pipe compiler stdout through `head` or another truncating consumer.
- Pressure table AC-P01..AC-P09 is preserved and routed.
- The app is classified as positive baseline + pressure source, not blocker.
- No app source edits unless correcting documentation-only metadata.

## Results

- **Compiler Status**: `ok` (0 diagnostics, 0 warnings) in both Ruby and Rust.
- **Source Hash**: Deterministic and stable at `sha256:4fc0b4cb4c63a06060017b932f351d9b708db826428f3d2ad94ac9f92c2a4e04` under absolute workspace paths.
- **Complexity**: 8 files, 9 types, 31 contracts, 61 `call_contract`, 6 fold, 2 map, 2 filter.
- **Pressure**: All 9 pressures AC-P01..AC-P09 registered and routed.

## Proof Matrix

| Deliverable | Status |
|---|---|
| Proof runner written | Done — `verify_lab_air_combat_baseline_p1.rb` (99/99 PASS) |
| Lab doc written | Done — `lab-air-combat-compilation-baseline-v0.md` |
| PRESSURE_REGISTRY.md updated | Done |
| Card closed | Done |
| Portfolio updated | Done |

## Closed Surfaces

- No real-time scheduling, clock, or `now()`.
- No RNG / sampled noise.
- No networking, sockets, Rack, HTTP, or authoritative server loop.
- No rendering, telemetry broadcast, persistence, replay store, DB, SQL, ORM, file, process, or network IO.
- No dynamic doctrine dispatch.
- No fold-to-struct implementation.
- No entity implementation.
- No stdlib math implementation.
- No app source migration.

## Runner Notes

Use fresh `--out` paths for every Rust compile. Do not pipe compiler stdout into `head -c` or any consumer that can close the pipe early; that can create a false SIGPIPE/internal-error trail unrelated to source correctness.

## Post-Closure Documentation Update — AC-P09

Added AC-P09 (`ServiceLoop / Progression readiness`) after Opus follow-up research.
This does not authorize a runtime loop. It records that `air_combat` should route
future authoritative tick work through the existing language concept of
ServiceLoop / PROP-037 Progression (`clock.every`, explicit `tick.time`) and
PROP-023 stream input, rather than an ad hoc host loop.

Updated artifacts:

- `air_combat/PRESSURE_REGISTRY.md`
- `air_combat/report.md`
- `lab-air-combat-compilation-baseline-v0.md`
- `verify_lab_air_combat_baseline_p1.rb` — updated to 99/99 PASS
