# APP-RECHECK-WAVE-P11

**Status:** OPEN — DISPATCH READY  
**Route:** governance / fleet recheck  
**Date:** 2026-06-14  
**Scope:** all 16 apps; evidence and registry updates only

## Goal

Refresh the app fleet after `air_combat`, `lead_router`, and `call_router` baseline integration, with Fold P3/P4 already landed.

Starting point:

- `APP-RECHECK-WAVE-P10`: 12/13 DUAL-CLEAN (`rule_engine` only blocked).
- `LAB-AIR-COMBAT-BASELINE-P1`: pre-entrypoint baseline, 99/99 PASS, superseded by entrypoint hash drift.
- `LAB-AIR-COMBAT-BASELINE-P2`: CLOSED — 115/115 PASS; `entrypoint RunDuel`; live hash `sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55`; AC-P01..AC-P10.
- `LAB-LEAD-ROUTER-BASELINE-P1`: CLOSED — 175/175 PASS; `entrypoint RunAccept`; live hash `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b`; LR-P01..LR-P11.
- `LAB-CALL-ROUTER-BASELINE-P1`: CLOSED — 178/178 PASS; `entrypoint RunConnectedMatched`; live hash `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5`; CR-P01..CR-P11.
- `LANG-FOLD-STRUCT-ACCUMULATOR-P3`: CLOSED — Rust TC implementation, 83/83 PASS.
- `LANG-FOLD-STRUCT-ACCUMULATOR-P4`: CLOSED — Ruby/Rust lowering parity, 83/83 PASS.

All three companion baselines are now closed. Expected Wave P11 result, if no new implementation changes land first: **15/16 DUAL-CLEAN**, with `rule_engine` still the only intentional blocked app.

## Gate

Start after at least:

- `LAB-AIR-COMBAT-BASELINE-P2` CLOSED — 115/115 (re-froze `entrypoint RunDuel` hash).
- `LAB-LEAD-ROUTER-BASELINE-P1` CLOSED — 175/175 PASS (includes `entrypoint RunAccept`; hash `sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b`).
- `LAB-CALL-ROUTER-BASELINE-P1` CLOSED — 178/178 PASS (includes `entrypoint RunConnectedMatched`; hash `sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5`).

Fold status to account for during execution:

- `LANG-FOLD-STRUCT-ACCUMULATOR-P3` CLOSED — capture Rust TC app-pressure impact.
- `LANG-FOLD-STRUCT-ACCUMULATOR-P4` CLOSED — capture fold SIR/lowering parity impact.

## Apps

Compile both Ruby and Rust for all current apps, including:

- `air_combat`
- `lead_router`
- `call_router`
- `trade_robot`
- the 12-app fleet from Wave P10

## Deliverables

- Rollup doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/.agents/docs/app-pressure-recheck-wave-p11-2026-06-14-v0.md`.
- Update all app `PRESSURE_REGISTRY.md` files with Wave P11 sections where appropriate.
- Update this card with closure summary.
- Portfolio index update after closure.

## Acceptance

- Treat `/Users/alex/dev/projects/igniter-workspace/igniter-lang/docs/dev-tutorial.md` as the current canon tutorial/truth snapshot for dual-toolchain readiness; lab notes are evidence, not override authority.
- Every app has fresh Ruby and Rust compile status.
- `air_combat`, `lead_router`, and `call_router` are included as the 14th, 15th, and 16th apps with their entrypoint-refactored hashes.
- `rule_engine` diagnostics are refreshed exactly.
- `call_router` Rust verification uses the proof-runner subprocess route or explicitly accounts for the known package-writer stdout/timing artifact.
- Note whether Fold P3/P4 changed any app pressure; do not edit app source.
- No source/compiler/runtime edits in this recheck card.

## Closed Surfaces

- No app migrations.
- No compiler changes.
- No IO/runtime work.
- No canon decisions.
