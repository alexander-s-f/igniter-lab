# Trade Robot Pressure Registry

Updated: 2026-06-14 (APP-RECHECK-WAVE-P10 — DUAL-CLEAN)
Last checked: 2026-06-14
Scope: app-pressure evidence only; not canon authority and not financial/trading advice.

## Current Live Check

Ruby/canon compile:

- status: `ok`
- diagnostics: 0
- source_hash: `sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a`

Rust/lab compile:

- status: `ok`
- stages: parse/classify/typecheck/emit/assemble all `ok`
- diagnostics: 0
- warnings: 0
- source_hash: `sha256:3b279c19c641940d21ec76e455e3fa40a121d936fea3fbba4ffa9604cc32612a`
- liveness: `typechecker.infer_expr.max_depth=7`, `form_resolver.walk_expr.max_depth=7`, no breaches

Proof: `igniter-lab/igniter-view-engine/proofs/verify_lab_trade_robot_baseline_p1.rb` — 100/100 PASS.

## Source Inventory

| File | Module | Role |
|---|---|---|
| `types.ig` | TradeTypes | market data, indicators, orders, positions, portfolio, config, backtest result |
| `signals.ig` | TradeSignals | `MakeSignal` factory contract |
| `indicators.ig` | TradeIndicators | SMA/EMA/RSI/MACD indicator contracts |
| `strategy.ig` | TradeStrategy | SMA, RSI, combined strategy contracts |
| `robot.ig` | TradeRobot | portfolio state transition and strategy dispatcher |
| `backtester.ig` | TradeBacktester | manually unrolled 10-step backtest |
| `example.ig` | TradeExample | synthetic market data and run contract |

Counts:

- 7 source files
- 10 types
- 14 contracts
- 34 `call_contract` sites, all PascalCase user contracts
- 5 `fold` sites
- 6 `concat` sites
- 22+ record literal computes

## Pressures

| ID | Status | Pressure | Evidence | Suggested route |
|---|---|---|---|---|
| TR-P01 | BASELINE | Dual-toolchain clean trading/backtest app | Ruby `ok/0`; Rust `ok/0`; 14 contracts; 100/100 proof | `LAB-TRADE-ROBOT-BASELINE-P1` |
| TR-P02 | ACTIVE-DESIGN-PRESSURE | Entity / compose primitive | `report.md` proposes `compose TradingRobot`; `RobotConfig` + `Portfolio` + strategy behavior are manually threaded across contracts | `LANG-COMPOSE-ENTITY-P1` |
| TR-P03 | ACTIVE-DESIGN-PRESSURE | Manual state threading | `ExecuteSignal`, `RobotTick`, `BacktestTick`, `RunBacktest` pass `Portfolio` in and return `Portfolio` out repeatedly | compose/state-machine track |
| TR-P04 | ACTIVE-DESIGN-PRESSURE | Backtest loop manually unrolled | `RunBacktest` has `p1` through `p10`; no fold-over-state loop used for portfolio | `LANG-FOLD-STRUCT-ACCUMULATOR-P1` or compose state loop |
| TR-P05 | ACTIVE-DESIGN-PRESSURE | Factory contract anti-pattern | `MakeSignal` exists to avoid inline record literals in conditional branches | record branch inference / parser-record ergonomics |
| TR-P06 | ACTIVE-DESIGN-PRESSURE | Dynamic strategy dispatch avoided | `RobotConfig.strategy_name`; `StrategyDispatcher` hardcodes `CombinedStrategy`; report notes dynamic callee returns `Unknown` | `LAB-DYNAMIC-CONTRACT-DISPATCH-P2` (safety route, not app unblock) |
| TR-P07 | POSITIVE | Scalar fold works in indicators | SMA and EMA use `fold` over `Collection[Integer]` successfully | preserve as stdlib fold regression evidence |
| TR-P08 | ACTIVE-DESIGN-PRESSURE | Fold-to-struct / temporal history | RSI comments document desired `{sum_gain,sum_loss,prev_close,count}` fold state; MACD signal line needs history | `LANG-FOLD-STRUCT-ACCUMULATOR-P1`, `LANG-TEMPORAL-STATE-P1` |
| TR-P09 | WATCH | Fixed-point numeric finance model | prices use Integer fixed-point scale 100; no Float/Decimal needed for compile | numeric fixed-point conventions |

## Interpretation

`trade_robot` is a positive app baseline, not a blocker. It proves the current language can compile a non-trivial pure trading/backtest pipeline with user-contract dispatch, scalar folds, collection transforms, portfolio updates, and fixed-point arithmetic.

The pressure is architectural rather than diagnostic: the app compiles cleanly because it chooses safe static workarounds for dynamic strategy dispatch and manually threads state.

## Closed Surfaces

- No real trading authority.
- No exchange, broker, market data, file, network, DB, SQL, ORM, Rack, or IO runtime surface.
- No financial recommendation semantics.
- No canon `compose` decision.
- No dynamic dispatch implementation.
- No fold-to-struct implementation.
- No app source changes in the baseline proof.

## Wave P10 Recheck Summary (2026-06-14)

Rust: ok / 0 diagnostics — unchanged. Ruby: ok / 0 diagnostics — unchanged. DUAL-TOOLCHAIN CLEAN. trade_robot is officially integrated as the 13th app in the fleet. No new pressures. No regressions.
