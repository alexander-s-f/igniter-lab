# Lab: Trade Robot Compilation Baseline

**Track:** LAB-TRADE-ROBOT-BASELINE-P1  
**Date:** 2026-06-13  
**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_trade_robot_baseline_p1.rb`  
**Result:** 100/100 PASS

---

## Purpose

Freeze `trade_robot` as a positive dual-toolchain app baseline and record the pressure it creates around entity modeling, manual state threading, fold-to-struct, and temporal history.

This is evidence only. It does not authorize `compose`, dynamic dispatch, real trading IO, broker integration, or financial semantics.

## Baseline Numbers

| Metric | Value |
|---|---|
| Ruby status | ok / 0 diagnostics |
| Rust status | ok / 0 diagnostics |
| source files | 7 |
| types | 10 |
| contracts | 14 |
| call_contract sites | 34, all PascalCase user contracts |
| fold sites | 5 |
| concat sites | 6 |
| record literal computes | 22+ |
| source_hash | `sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a` |
| Rust liveness | `tc_infer=7`, `fr_walk=7`, no breaches |

## App Structure

| File | Module | Role |
|---|---|---|
| `types.ig` | TradeTypes | market, signal, order, position, portfolio, robot config, backtest result types |
| `signals.ig` | TradeSignals | typed `MakeSignal` helper |
| `indicators.ig` | TradeIndicators | SMA, EMA, RSI proxy, MACD proxy |
| `strategy.ig` | TradeStrategy | SMA crossover, RSI mean reversion, combined strategy |
| `robot.ig` | TradeRobot | execute signal, robot tick, static strategy dispatcher |
| `backtester.ig` | TradeBacktester | backtest tick and manually unrolled 10-step run |
| `example.ig` | TradeExample | synthetic market data and `RunTradingBot` |

## Proof Matrix

| Section | Topic | Checks |
|---|---|---:|
| A | Preconditions | 10 |
| B | Source shape | 9 |
| C | Type and contract inventory | 26 |
| D | Rust compile | 14 |
| E | Ruby compile | 6 |
| F | Positive app patterns | 10 |
| G | Closed runtime/IO surfaces | 7 |
| H | Liveness and complexity | 6 |
| I | Baseline pressure routes | 8 |
| J | Regression baseline summary | 4 |
| **Total** | | **100** |

## Key Findings

### Dual-Toolchain Clean

Both compilers accept the full app with zero diagnostics. This makes `trade_robot` a strong positive baseline for pure multi-contract business logic with state passed explicitly.

### Compose / Entity Pressure

The app models a robot as separate `RobotConfig`, `Portfolio`, strategy contracts, and transition contracts. This compiles, but the source and report show that a real-world entity wants a declarative grouping of config, state, behavior, invariants, and temporal history.

Route: `LANG-COMPOSE-ENTITY-P1`.

### Manual State Threading

Portfolio state is passed into and returned from each transition. `RunBacktest` manually threads `p0 -> p1 -> ... -> p10`. This is clean today but verbose and brittle.

Route: compose/state-machine track.

### Fold-To-Struct / Temporal History

Scalar folds work: SMA and EMA compile cleanly. The app documents why RSI and MACD need more: record accumulator state and historical indicator series.

Routes: `LANG-FOLD-STRUCT-ACCUMULATOR-P1`, `LANG-TEMPORAL-STATE-P1`.

### Dynamic Dispatch Avoided Safely

`RobotConfig.strategy_name` exists, but `StrategyDispatcher` uses static `call_contract("CombinedStrategy", ...)`. This is a safe workaround; no current unblock is needed.

Related route: `LAB-DYNAMIC-CONTRACT-DISPATCH-P2`, but only as safety-boundary research.

## Closed Surfaces

- No broker/exchange integration.
- No real market data IO.
- No file/network/database/SQL/ORM/Rack.
- No financial advice semantics.
- No dynamic dispatch implementation.
- No `compose` implementation.
- No fold-to-struct implementation.
- No source edits to the app.
