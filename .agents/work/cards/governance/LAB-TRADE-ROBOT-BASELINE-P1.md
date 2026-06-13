# LAB-TRADE-ROBOT-BASELINE-P1

**Status:** CLOSED — PROVED 100/100 PASS  
**Route:** lab / app baseline / trade_robot  
**Date:** 2026-06-13  
**Authority:** evidence baseline only; no implementation

## Decision

`trade_robot` is accepted as a positive dual-toolchain baseline.

## Result

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics |
| source files | 7 |
| types | 10 |
| contracts | 14 |
| call_contract sites | 34 |
| fold sites | 5 |
| concat sites | 6 |
| source_hash | `sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a` |
| proof | 100/100 PASS |

## What This Proves

The current language can compile a non-trivial trading/backtest pipeline with:

- pure multi-module business logic,
- user-contract dispatch through PascalCase `call_contract`,
- scalar folds for indicators,
- portfolio state passed explicitly,
- fixed-point integer arithmetic,
- collection concat/array literals,
- record literal outputs.

## Pressure Captured

| ID | Status | Pressure | Route |
|---|---|---|---|
| TR-P01 | BASELINE | Dual-toolchain clean app | this card |
| TR-P02 | ACTIVE-DESIGN-PRESSURE | Entity / compose primitive | `LANG-COMPOSE-ENTITY-P1` |
| TR-P03 | ACTIVE-DESIGN-PRESSURE | Manual state threading | compose/state-machine track |
| TR-P04 | ACTIVE-DESIGN-PRESSURE | Manual backtest unroll | `LANG-FOLD-STRUCT-ACCUMULATOR-P1` |
| TR-P05 | ACTIVE-DESIGN-PRESSURE | Factory contracts for branch records | record branch ergonomics |
| TR-P06 | ACTIVE-DESIGN-PRESSURE | Dynamic strategy dispatch avoided | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` |
| TR-P07 | POSITIVE | Scalar fold works | preserve regression evidence |
| TR-P08 | ACTIVE-DESIGN-PRESSURE | Fold-to-struct / temporal history | `LANG-TEMPORAL-STATE-P1` |
| TR-P09 | WATCH | Fixed-point finance model | numeric convention track |

## Deliverables

| Artifact | Path |
|---|---|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_trade_robot_baseline_p1.rb` |
| Lab doc | `igniter-lab/lab-docs/governance/lab-trade-robot-compilation-baseline-v0.md` |
| Pressure registry | `igniter-lab/igniter-apps/trade_robot/PRESSURE_REGISTRY.md` |
| Agent card | this file |
| Portfolio index | `igniter-lab/.agents/portfolio-index.md` |

## Closed Surfaces

- No real trading authority.
- No broker/exchange/market-data integration.
- No IO, Rack, DB, SQL, ORM, network, file, or process surface.
- No financial advice semantics.
- No `compose` implementation.
- No dynamic dispatch implementation.
- No app source edits.
