# LAB-AIR-COMBAT-BASELINE-P1

**Status:** OPEN — DISPATCH READY  
**Route:** lab / app baseline / air_combat  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

## Goal

Freeze `air_combat` as a positive dual-toolchain baseline and pressure source.

`air_combat` is a multiplayer, strategy-driven swarm simulation: each player owns a fleet of aircraft and authors a `Strategy`; the swarm acts autonomously through pure target tracking, pursuit/evasion guidance, and per-tick world updates.

This card should prove the app is clean today and capture the pressure it creates for fold-to-struct, entity composition, static strategy dispatch, stdlib math, and the future IO membrane.

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
| source_hash | `sha256:b52ffef0e10c866ded1f8f0dc06c3f593bb72dee309382c46a8b7ea114b2eaed` |

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

## Proof Questions

1. Does the full 8-file app compile cleanly in Ruby and Rust using fresh `--out` paths?
2. Are the claimed counts stable: 8 files, 9 types, 31 contracts, 61 `call_contract`, 6 folds?
3. Are all `call_contract` sites Tier-1 string literals rather than dynamic callees?
4. Are all current folds scalar, with record folds represented as documented pressure only?
5. Does the Kalman/alpha-beta tracking pressure directly route to `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4`?
6. Does `Player = Strategy + Swarm + score + behavior` route cleanly to `LANG-COMPOSE-ENTITY` without reopening dynamic dispatch?
7. Does the report keep IO as a membrane around the pure core, not inside `WorldTick` / guidance / Kalman?
8. Is the SIGPIPE/head-truncation caveat documented so future proof runners avoid false compiler errors?

## Pressure IDs To Preserve

| ID | Pressure | Route |
|---|---|---|
| AC-P01 | fold-to-struct Kalman track | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| AC-P02 | fold-to-struct swarm centroid | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| AC-P03 | manual unroll / fold-over-state | fold-struct + `LANG-COMPOSE-ENTITY` |
| AC-P04 | factory contracts for typed records | record literal inference / nested record tracks |
| AC-P05 | state threading / entity | `LANG-COMPOSE-ENTITY` |
| AC-P06 | dynamic strategy dispatch avoided | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| AC-P07 | missing sqrt / normalize | new `LANG-STDLIB-MATH` readiness |
| AC-P08 | IO surface for real game | IO runtime / effect surface tracks |

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
- Pressure table AC-P01..AC-P08 is preserved and routed.
- The app is classified as positive baseline + pressure source, not blocker.
- No app source edits unless correcting documentation-only metadata.

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
