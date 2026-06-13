module TradeBacktester
import TradeTypes
import TradeRobot
import stdlib.collection.{ count, filter }

-- ============================================================
-- Backtester / Simulator
-- ============================================================
-- fold(candles, portfolio, tick_fn) SHOULD work, but the typechecker
-- resolves the fold accumulator from the init arg, which is a record
-- literal (Unknown for now). We manually unroll 10 ticks instead.

contract BacktestTick {
  input portfolio : Portfolio
  input candles : Collection[Candle]
  input candle : Candle
  input config : RobotConfig

  compute result = call_contract("RobotTick", portfolio, candles, candle, config)
  output result : Portfolio
}

contract RunBacktest {
  input c1 : Candle
  input c2 : Candle
  input c3 : Candle
  input c4 : Candle
  input c5 : Candle
  input c6 : Candle
  input c7 : Candle
  input c8 : Candle
  input c9 : Candle
  input c10 : Candle
  input config : RobotConfig

  compute candles = [c1, c2, c3, c4, c5, c6, c7, c8, c9, c10]

  compute p0 = {
    balance: 1000000,
    equity: 1000000,
    open_positions: [],
    closed_positions: [],
    orders: [],
    total_trades: 0,
    winning_trades: 0,
    losing_trades: 0
  }

  -- Manually unrolled tick loop (the PAIN without fold-over-struct)
  compute p1  = call_contract("BacktestTick", p0,  candles, c1,  config)
  compute p2  = call_contract("BacktestTick", p1,  candles, c2,  config)
  compute p3  = call_contract("BacktestTick", p2,  candles, c3,  config)
  compute p4  = call_contract("BacktestTick", p3,  candles, c4,  config)
  compute p5  = call_contract("BacktestTick", p4,  candles, c5,  config)
  compute p6  = call_contract("BacktestTick", p5,  candles, c6,  config)
  compute p7  = call_contract("BacktestTick", p6,  candles, c7,  config)
  compute p8  = call_contract("BacktestTick", p7,  candles, c8,  config)
  compute p9  = call_contract("BacktestTick", p8,  candles, c9,  config)
  compute p10 = call_contract("BacktestTick", p9,  candles, c10, config)

  compute result = {
    robot_name: config.name,
    instrument: config.instrument,
    total_candles: 10,
    total_trades: p10.total_trades,
    winning_trades: p10.winning_trades,
    losing_trades: p10.losing_trades,
    final_balance: p10.balance,
    max_drawdown: 0,
    profit_factor: 0
  }

  output result : BacktestResult
}
