module TradeStrategy
import TradeTypes
import TradeSignals
import TradeIndicators

-- ============================================================
-- Trading Strategies
-- ============================================================

-- ── SMA Crossover Strategy ──────────────────────────────────

contract SMACrossoverStrategy {
  input candles : Collection[Candle]
  input config : RobotConfig

  compute fast_sma = call_contract("ComputeSMA", candles, config.sma_fast_period)
  compute slow_sma = call_contract("ComputeSMA", candles, config.sma_slow_period)

  compute signal = if fast_sma.value > slow_sma.value {
    call_contract("MakeSignal", fast_sma.tick, "BUY", 70, "Fast SMA above Slow SMA")
  } else {
    if fast_sma.value < slow_sma.value {
      call_contract("MakeSignal", fast_sma.tick, "SELL", 70, "Fast SMA below Slow SMA")
    } else {
      call_contract("MakeSignal", fast_sma.tick, "HOLD", 0, "SMAs equal")
    }
  }

  output signal : Signal
}

-- ── RSI Mean Reversion Strategy ─────────────────────────────

contract RSIMeanReversion {
  input candles : Collection[Candle]
  input config : RobotConfig

  compute rsi = call_contract("ComputeRSI", candles, config.rsi_period)

  compute signal = if rsi.value < config.rsi_oversold {
    call_contract("MakeSignal", rsi.tick, "BUY", 80, "RSI oversold")
  } else {
    if rsi.value > config.rsi_overbought {
      call_contract("MakeSignal", rsi.tick, "SELL", 80, "RSI overbought")
    } else {
      call_contract("MakeSignal", rsi.tick, "HOLD", 0, "RSI neutral")
    }
  }

  output signal : Signal
}

-- ── Combined Strategy ───────────────────────────────────────
-- THIS IS WHERE `compose` WOULD SHINE.

contract CombinedStrategy {
  input candles : Collection[Candle]
  input config : RobotConfig

  compute sma_signal = call_contract("SMACrossoverStrategy", candles, config)
  compute rsi_signal = call_contract("RSIMeanReversion", candles, config)

  compute signal = if sma_signal.direction == "BUY" {
    if rsi_signal.direction == "BUY" {
      call_contract("MakeSignal", sma_signal.tick, "BUY", 90, "SMA+RSI confirm BUY")
    } else {
      call_contract("MakeSignal", sma_signal.tick, "HOLD", 30, "SMA BUY but RSI disagrees")
    }
  } else {
    if sma_signal.direction == "SELL" {
      if rsi_signal.direction == "SELL" {
        call_contract("MakeSignal", sma_signal.tick, "SELL", 90, "SMA+RSI confirm SELL")
      } else {
        call_contract("MakeSignal", sma_signal.tick, "HOLD", 30, "SMA SELL but RSI disagrees")
      }
    } else {
      call_contract("MakeSignal", sma_signal.tick, "HOLD", 0, "No clear signal")
    }
  }

  output signal : Signal
}
