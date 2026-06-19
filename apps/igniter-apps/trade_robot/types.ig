module TradeTypes

-- ============================================================
-- Trade Robot Engine: Core Types
-- ============================================================
-- All prices are in fixed-point (scale 100), e.g. $150.25 = 15025

-- ── Market Data ─────────────────────────────────────────────

type Candle {
  tick : Integer        -- sequential index (time)
  open : Integer
  high : Integer
  low : Integer
  close : Integer
  volume : Integer
}

type TimeSeries {
  instrument : String
  timeframe : String    -- "M1", "M5", "H1", "D1"
  candles : Collection[Candle]
}

-- ── Indicators ──────────────────────────────────────────────

type IndicatorValue {
  tick : Integer
  name : String         -- "SMA_20", "EMA_12", "RSI_14"
  value : Integer       -- fixed-point 100
}

type IndicatorSeries {
  name : String
  values : Collection[IndicatorValue]
}

-- ── Trading Signals & Orders ────────────────────────────────

type Signal {
  tick : Integer
  direction : String    -- "BUY", "SELL", "HOLD"
  strength : Integer    -- 0..100
  reason : String
}

type Order {
  id : Integer
  tick : Integer
  direction : String    -- "BUY", "SELL"
  instrument : String
  price : Integer
  quantity : Integer
  status : String       -- "OPEN", "FILLED", "CANCELLED"
}

type Position {
  id : Integer
  instrument : String
  direction : String
  entry_price : Integer
  entry_tick : Integer
  quantity : Integer
  pnl : Integer
}

-- ── Portfolio / Account ─────────────────────────────────────

type Portfolio {
  balance : Integer
  equity : Integer
  open_positions : Collection[Position]
  closed_positions : Collection[Position]
  orders : Collection[Order]
  total_trades : Integer
  winning_trades : Integer
  losing_trades : Integer
}

-- ── Robot Configuration ─────────────────────────────────────
-- This is WHERE we feel the pain of not having `compose`.
-- In OOP: class Robot { strategy, riskManager, portfolio, ... }
-- In Igniter: we must pass everything as a flat struct.

type RobotConfig {
  name : String
  instrument : String
  timeframe : String
  strategy_name : String      -- Contract[I→O] reference
  sma_fast_period : Integer
  sma_slow_period : Integer
  rsi_period : Integer
  rsi_overbought : Integer
  rsi_oversold : Integer
  risk_per_trade : Integer    -- percent of balance
  stop_loss : Integer         -- fixed-point distance
  take_profit : Integer       -- fixed-point distance
}

-- ── Backtest Result ─────────────────────────────────────────

type BacktestResult {
  robot_name : String
  instrument : String
  total_candles : Integer
  total_trades : Integer
  winning_trades : Integer
  losing_trades : Integer
  final_balance : Integer
  max_drawdown : Integer
  profit_factor : Integer     -- fixed-point 100
}
