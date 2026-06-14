# LAB-AIR-COMBAT-COMPILATION-BASELINE-v0

**Status:** CLOSED — PROVED (99/99 PASS; AC-P09 added)  
**Route:** lab / app baseline / air_combat  
**Date:** 2026-06-14  
**Authority:** evidence baseline only; no implementation

---

## Executive Summary

`air_combat` is a multiplayer, strategy-driven swarm simulation where each player authors a `Strategy` containing doctrine parameters, and the swarm operates autonomously through target tracking (alpha-beta/Kalman filter), pursuit/evasion guidance, and ticks. 

This document establishes the compilation baseline for `air_combat` as a positive dual-toolchain baseline and registers the architectural pressures it places on the Igniter language.

---

## Baseline Verification Results

The full 8-file app compiles successfully with **0 diagnostics and 0 warnings** under both the Rust (lab) and Ruby (canon) compilers.

### Metrics & Counts

| Metric | Value |
|---|---|
| Ruby status | `ok` / 0 diagnostics |
| Rust status | `ok` / 0 diagnostics |
| source files | 8 |
| types | 9 |
| contracts | 31 |
| call_contract sites | 61 (all Tier-1 PascalCase string literals) |
| fold sites | 6 (all scalar) |
| map / filter sites | 2 / 2 |
| source_hash | `sha256:4fc0b4cb4c63a06060017b932f351d9b708db826428f3d2ad94ac9f92c2a4e04` (see Path Sensitivity below) |

### Path Sensitivity Note

The `source_hash` uses absolute file paths during multifile collection. Under the standard absolute paths of `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/air_combat/`, both compilers produce the hash above. Any change to the absolute directory layout will deterministically produce a different hash.

---

## Pressures Captured

`air_combat` creates concrete, simulation-driven pressure on several active language tracks:

| ID | Title | Description / Evidence | Route |
|---|---|---|---|
| **AC-P01** | fold-to-struct (Kalman track) | `kalman.ig` WANTS to fold a sequence of measurements into a `Track` record, but is blocked by `OOF-COL4`. Manually unrolled as `TrackFold3` over 3 steps. | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| **AC-P02** | fold-to-struct (swarm centroid) | `swarm.ig` must run two scalar folds plus `count` to compute the swarm centroid, rather than folding into a single `{sum_x, sum_y, count}` struct. | `LANG-FOLD-STRUCT-ACCUMULATOR-P3/P4` |
| **AC-P03** | manual unroll / fold-over-state | `engine.ig` unrolls `WorldTick` ×3 in `RunBattle3` instead of looping over ticks using a state-carrying fold. | `LANG-FOLD-STRUCT-ACCUMULATOR` + `LANG-COMPOSE-ENTITY` |
| **AC-P04** | factory contracts | `MakePlane` and `MakeStrategy` are user contracts created solely to work around record literal type inference limitations. | record literal/nested record tracks |
| **AC-P05** | state threading / entity | `engine.ig` threads the `Player` state (config, state, and doctrine) by hand tick-by-tick. | `LANG-COMPOSE-ENTITY` |
| **AC-P06** | dynamic dispatch avoided | Swarm strategies are hardcoded through `DoctrineDispatcher` using static string matching. Variable dispatch is avoided to respect safety boundaries. | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| **AC-P07** | missing math (sqrt) | Guidance uses gain-scaled squared-distance steering because there is no `sqrt` available in the standard library. | new `LANG-STDLIB-MATH` track |
| **AC-P08** | IO membrane | The game logic remains pure. The report details the required clock, input stream, RNG, socket, and storage capabilities as a thin outer shell. | `PROP-035` / `PROP-023` / IO-runtime |

---

### ServiceLoop Direction Note

AC-P09 is a documentation pressure, not an implementation authorization. The
canonical direction for a real game loop is already named by
[`docs/spec/ch13-managed-recursion.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/spec/ch13-managed-recursion.md): `ServiceLoop` is the alive-by-liveness loop class, and §13.5 maps timer-driven source binding through PROP-037 progression descriptors (`clock.every`, explicit `tick.time`). The Covenant repeats this boundary in
[`docs/language-covenant.md`](/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/language-covenant.md) P14. `air_combat` should therefore be treated as a future ServiceLoop fixture, not as justification for an ad hoc host loop.

## Closed Surfaces (Non-Goals)

To prevent scope creep, the following boundaries remain strictly closed in this baseline:
- No clock access or `now()` in contracts.
- No network, sockets, HTTP, or Rack server.
- No persistence, database, or SQL/ORM.
- No dynamic callee string dispatch.
- No fold-to-struct or entity compiler implementation.
