module TradeRobot
import TradeTypes
import TradeStrategy
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- The Robot Entity
-- ============================================================
-- THIS IS THE PAIN POINT. Without `compose`, a Robot is just
-- a fat contract that threads all state manually.
--
-- WHAT WE WANT (proposed `compose`):
--
-- compose TradingRobot {
--   config : RobotConfig
--   state portfolio : Portfolio
--
--   uses strategy = SMACrossoverStrategy
--
--   action ProcessCandle(candle) {
--     signal = strategy.evaluate(candles)
--     if signal.direction == "BUY" { OpenPosition(...) }
--     if signal.direction == "SELL" { ClosePosition(...) }
--   }
--
--   action OpenPosition(price, qty) {
--     portfolio.balance -= price * qty
--     portfolio.open_positions += new Position(...)
--   }
-- }
--
-- WHAT WE HAVE TO DO INSTEAD:
-- Pass portfolio in, get portfolio out. Every. Single. Time.

contract ExecuteSignal {
  input portfolio : Portfolio
  input signal : Signal
  input current_price : Integer
  input config : RobotConfig
  input tick : Integer

  compute trade_qty = (portfolio.balance * config.risk_per_trade) / (current_price * 100)
  compute safe_qty = if trade_qty > 0 { trade_qty } else { 1 }

  compute should_buy = if signal.direction == "BUY" { true } else { false }
  compute should_sell = if signal.direction == "SELL" { true } else { false }

  -- Create order
  compute new_order = {
    id: portfolio.total_trades + 1,
    tick: tick,
    direction: signal.direction,
    instrument: config.instrument,
    price: current_price,
    quantity: safe_qty,
    status: if should_buy { "FILLED" } else { if should_sell { "FILLED" } else { "CANCELLED" } }
  }

  -- Create position if BUY
  compute new_position = {
    id: portfolio.total_trades + 1,
    instrument: config.instrument,
    direction: "LONG",
    entry_price: current_price,
    entry_tick: tick,
    quantity: safe_qty,
    pnl: 0
  }

  -- Update balance
  compute new_balance = if should_buy {
    portfolio.balance - (current_price * safe_qty)
  } else {
    if should_sell {
      portfolio.balance + (current_price * safe_qty)
    } else {
      portfolio.balance
    }
  }

  -- Update trade counters
  compute new_total = if should_buy {
    portfolio.total_trades + 1
  } else {
    if should_sell {
      portfolio.total_trades + 1
    } else {
      portfolio.total_trades
    }
  }

  -- Add position to open positions if BUY, or add to closed if SELL
  compute new_open = if should_buy {
    concat(portfolio.open_positions, [new_position])
  } else {
    portfolio.open_positions
  }

  compute new_closed = if should_sell {
    concat(portfolio.closed_positions, [new_position])
  } else {
    portfolio.closed_positions
  }

  compute updated_portfolio = {
    balance: new_balance,
    equity: new_balance,
    open_positions: new_open,
    closed_positions: new_closed,
    orders: concat(portfolio.orders, [new_order]),
    total_trades: new_total,
    winning_trades: portfolio.winning_trades,
    losing_trades: portfolio.losing_trades
  }

  output updated_portfolio : Portfolio
}

-- ── Robot Tick: process one candle ───────────────────────────
-- This is the core loop body of the robot.

contract RobotTick {
  input portfolio : Portfolio
  input candles : Collection[Candle]
  input current_candle : Candle
  input config : RobotConfig

  -- Static dispatch via dispatcher
  compute signal = call_contract("StrategyDispatcher", candles, config)

  -- Execute the signal
  compute new_portfolio = call_contract(
    "ExecuteSignal",
    portfolio, signal, current_candle.close, config, current_candle.tick
  )

  output new_portfolio : Portfolio
}

-- ── Strategy Dispatcher ─────────────────────────────────────
-- Routes to the correct strategy by name.
-- THIS is where `compose` would eliminate the manual routing.

contract StrategyDispatcher {
  input candles : Collection[Candle]
  input config : RobotConfig

  -- For now, direct static dispatch to CombinedStrategy.
  -- Dynamic routing (if-else + call_contract) produces Unknown
  -- because the typechecker cannot infer type from conditional branches
  -- where each branch is a call_contract.
  -- THIS is exactly what `compose` would solve.
  compute signal = call_contract("CombinedStrategy", candles, config)

  output signal : Signal
}
