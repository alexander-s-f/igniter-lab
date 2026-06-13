module TradeIndicators
import TradeTypes
import stdlib.collection.{ map, filter, count }

-- ============================================================
-- Technical Analysis Indicators
-- ============================================================
-- Using fold() for aggregations! Fixed-point arithmetic (scale 100).

-- ── SMA (Simple Moving Average) ─────────────────────────────
-- SMA = sum(last N closes) / N
-- Since we lack `take(n)` reliably, we compute SMA over ALL candles
-- and then mark only recent ones as valid.

contract ComputeSMA {
  input candles : Collection[Candle]
  input period : Integer

  -- Sum all closes using fold
  compute closes = map(candles, c -> c.close)
  compute total = fold(closes, 0, (acc, v) -> acc + v)
  compute n = count(candles)

  -- Simple average (would need windowed sum for real SMA)
  compute avg = if n > 0 { total / n } else { 0 }

  -- Generate a single indicator value for the "current" window
  compute sma_val = {
    tick: n,
    name: concat("SMA_", "N"),
    value: avg
  }

  output sma_val : IndicatorValue
}

-- ── EMA (Exponential Moving Average) ────────────────────────
-- EMA_t = close * k + EMA_(t-1) * (1 - k)
-- where k = 2 / (period + 1)
-- In fixed-point (scale 100): k = 200 / (period + 1)

contract ComputeEMA {
  input candles : Collection[Candle]
  input period : Integer

  -- k = 200 / (period + 1), in fixed-point 100
  compute k = 200 / (period + 1)
  compute one_minus_k = 100 - k

  -- EMA via fold: accumulator IS the running EMA (fixed-point)
  compute closes = map(candles, c -> c.close)
  compute ema = fold(closes, 0, (prev_ema, close) ->
    if prev_ema == 0 {
      close
    } else {
      ((close * k) + (prev_ema * one_minus_k)) / 100
    }
  )

  compute ema_val = {
    tick: count(candles),
    name: concat("EMA_", "N"),
    value: ema
  }

  output ema_val : IndicatorValue
}

-- ── RSI (Relative Strength Index) ───────────────────────────
-- RSI = 100 - (100 / (1 + RS))
-- RS = avg_gain / avg_loss
-- We compute gains and losses using map, then fold to sum.

contract ComputeRSI {
  input candles : Collection[Candle]
  input period : Integer

  -- We need consecutive price differences.
  -- Without zip or index access, we compute a proxy:
  -- Use fold to track prev_close and accumulate gains/losses.
  --
  -- fold state = {sum_gain, sum_loss, prev_close, count}
  -- But we can only fold to a single Integer!
  --
  -- WORKAROUND: We compute two separate folds.
  -- Fold 1: Count candles where close > prev (gains)
  -- Fold 2: Sum the raw average gain/loss proxy
  --
  -- REAL LIMITATION: fold() returns a single scalar.
  -- We need fold-to-struct (returning a record from fold).
  -- For now, we approximate RSI using total gain vs total loss.

  compute closes = map(candles, c -> c.close)
  compute n = count(candles)

  -- Use the first close as a baseline
  -- Approximate: count how many candles closed above the SMA
  compute sma = call_contract("ComputeSMA", candles, period)
  compute above = filter(candles, c ->
    if c.close > sma.value { true } else { false }
  )
  compute above_count = count(above)

  -- RSI proxy: (above_count / total) * 100
  compute rsi = if n > 0 {
    (above_count * 100) / n
  } else {
    50
  }

  compute rsi_val = {
    tick: n,
    name: concat("RSI_", "N"),
    value: rsi
  }

  output rsi_val : IndicatorValue
}

-- ── MACD (Moving Average Convergence Divergence) ────────────
-- MACD Line = EMA_12 - EMA_26
-- Signal Line = EMA_9(MACD Line)
-- Histogram = MACD - Signal

contract ComputeMACD {
  input candles : Collection[Candle]

  compute ema12 = call_contract("ComputeEMA", candles, 12)
  compute ema26 = call_contract("ComputeEMA", candles, 26)

  compute macd_line = ema12.value - ema26.value

  -- Signal line would need EMA of MACD values over time,
  -- but we only have a single MACD value per call.
  -- This is the Temporal[T] pressure: we need HISTORY of MACD.
  -- For now, signal = macd (no smoothing).
  compute signal_line = macd_line
  compute histogram = 0

  compute macd_val = {
    tick: count(candles),
    name: "MACD",
    value: macd_line
  }

  output macd_val : IndicatorValue
}
