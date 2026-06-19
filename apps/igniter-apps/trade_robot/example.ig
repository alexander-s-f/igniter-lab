module TradeExample
import TradeTypes
import TradeBacktester

-- ============================================================
-- Example: Backtest Combined Strategy on Synthetic BTC/USD
-- ============================================================

contract RunTradingBot {

  compute config = {
    name: "AlphaBot",
    instrument: "BTC/USD",
    timeframe: "D1",
    strategy_name: "CombinedStrategy",
    sma_fast_period: 5,
    sma_slow_period: 20,
    rsi_period: 14,
    rsi_overbought: 70,
    rsi_oversold: 30,
    risk_per_trade: 2,
    stop_loss: 500,
    take_profit: 1000
  }

  -- Synthetic Market Data: rise → consolidation → drop
  compute c1  = { tick: 1,  open: 30000, high: 30500, low: 29800, close: 30200, volume: 1000 }
  compute c2  = { tick: 2,  open: 30200, high: 31000, low: 30100, close: 30800, volume: 1200 }
  compute c3  = { tick: 3,  open: 30800, high: 31500, low: 30600, close: 31200, volume: 1100 }
  compute c4  = { tick: 4,  open: 31200, high: 32000, low: 31000, close: 31800, volume: 1300 }
  compute c5  = { tick: 5,  open: 31800, high: 32500, low: 31500, close: 32200, volume: 1500 }
  compute c6  = { tick: 6,  open: 32200, high: 32800, low: 32000, close: 32500, volume: 1100 }
  compute c7  = { tick: 7,  open: 32500, high: 32600, low: 31800, close: 32000, volume: 900 }
  compute c8  = { tick: 8,  open: 32000, high: 32200, low: 31500, close: 31700, volume: 800 }
  compute c9  = { tick: 9,  open: 31700, high: 31900, low: 31000, close: 31200, volume: 1400 }
  compute c10 = { tick: 10, open: 31200, high: 31400, low: 30500, close: 30800, volume: 1600 }

  compute backtest = call_contract("RunBacktest",
    c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, config
  )

  output backtest : BacktestResult
}
