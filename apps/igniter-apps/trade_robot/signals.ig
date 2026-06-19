module TradeSignals
import TradeTypes

-- ============================================================
-- Signal Factory
-- ============================================================
-- Helper to construct typed Signal values, avoiding the
-- inline-record-in-if/else → Unknown issue.

contract MakeSignal {
  input tick : Integer
  input direction : String
  input strength : Integer
  input reason : String

  compute sig = {
    tick: tick,
    direction: direction,
    strength: strength,
    reason: reason
  }

  output sig : Signal
}
