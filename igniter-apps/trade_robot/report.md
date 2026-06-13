# Trade Robot Engine — Pressure Report

## The Pain of Entity Modeling

Building a Trade Robot in Igniter exposed the **single most painful architectural gap** in the language: there is no convenient way to model *entities* — objects that combine state, behavior, and configuration.

In OOP (Python, Java, etc.), a trading robot is naturally expressed as:

```python
class TradingRobot:
    def __init__(self, config, strategy):
        self.config = config
        self.strategy = strategy
        self.portfolio = Portfolio(balance=1_000_000)

    def process_candle(self, candle):
        signal = self.strategy.evaluate(candle)
        if signal == "BUY":
            self.portfolio.buy(candle.close)
```

In Igniter, we have:
1. **Types** (data only, no behavior)
2. **Contracts** (behavior only, no state)

There is no construct that combines them. The result:

### Problem 1: Manual State Threading

Every contract that modifies entity state must take the ENTIRE state as input and return the ENTIRE state as output:

```igniter
-- WHAT WE WRITE (pain)
contract RobotTick {
  input portfolio : Portfolio    -- thread state IN
  input candles : Collection[Candle]
  input candle : Candle
  input config : RobotConfig

  compute signal = ...
  compute new_portfolio = call_contract("ExecuteSignal", portfolio, signal, ...)
  output new_portfolio : Portfolio  -- thread state OUT
}
```

### Problem 2: No Polymorphic Dispatch

We wanted `call_contract(config.strategy_name, candles, config)` — dynamic dispatch based on a config string. This COMPILES but produces `Unknown` type, which causes OOF-TY1 errors at the output boundary.

Even `if strategy == "A" { call_contract("A") } else { call_contract("B") }` produces `Unknown` because the typechecker cannot unify types from call_contract results inside conditional branches.

We were forced to hardcode a single strategy in `StrategyDispatcher`.

### Problem 3: Factory Contracts (MakeXxx Anti-Pattern)

Inline records inside `if/else` branches produce `Unknown` type. We MUST create factory contracts like `MakeSignal`, `MakeViolation`, `MakeCell` to construct typed values. This is a pervasive anti-pattern:

```igniter
-- WHAT WE WANT
compute signal = if bullish { { direction: "BUY", strength: 90 } }
                 else { { direction: "SELL", strength: 90 } }

-- WHAT WE MUST WRITE
compute signal = if bullish { call_contract("MakeSignal", "BUY", 90) }
                 else { call_contract("MakeSignal", "SELL", 90) }
```

### Problem 4: Manual Unrolling (No fold-over-struct)

The backtester needs to iterate over 10 candles, threading portfolio state. `fold` works for scalars (`fold(prices, 0, (acc, v) -> acc + v)`) but produces `Unknown` when the lambda calls `call_contract`. We manually unrolled 10 ticks:

```igniter
compute p1  = call_contract("BacktestTick", p0,  candles, c1,  config)
compute p2  = call_contract("BacktestTick", p1,  candles, c2,  config)
...
compute p10 = call_contract("BacktestTick", p9,  candles, c10, config)
```

---

## Proposal: `compose` — The Missing Entity Primitive

Based on ALL accumulated pain across ALL applications, here is a design for `compose`:

```igniter
compose TradingRobot {
  -- Configuration (immutable)
  config name : String
  config instrument : String
  config strategy : Contract[Collection[Candle] -> Signal]

  -- State (mutable within the compose scope)
  state portfolio : Portfolio = {
    balance: 1000000, equity: 1000000,
    open_positions: [], closed_positions: [],
    orders: [], total_trades: 0,
    winning_trades: 0, losing_trades: 0
  }

  -- Composed sub-contracts (behavior)
  uses strategy : SMACrossoverStrategy | RSIMeanReversion | CombinedStrategy

  -- Actions (contracts that can modify state)
  action ProcessCandle(candle : Candle, candles : Collection[Candle]) -> Signal {
    compute signal = strategy.evaluate(candles)
    if signal.direction == "BUY" {
      state portfolio = ExecuteSignal(portfolio, signal, candle.close)
    }
    output signal
  }

  -- Derived computed fields (Temporal[T] auto-managed)
  temporal portfolio.balance  -- compiler auto-tracks history
  temporal portfolio.equity

  -- Invariants
  invariant portfolio.balance >= 0 severity "CRITICAL"
}
```

### What `compose` gives us:

| Feature | Without `compose` | With `compose` |
|---|---|---|
| State management | Manual threading (input → output) | `state` keyword auto-threads |
| Polymorphic dispatch | Hardcoded dispatcher | `uses strategy : A \| B` |
| Temporal tracking | Manual TemporalInteger struct | `temporal field` annotation |
| Invariants | Separate CheckConstraint contract | Inline `invariant` |
| Configuration | Flat RobotConfig struct | `config` namespace |
| Composition | Nested call_contract | `uses` + dot notation |

### `compose` vs `class`

| Aspect | OOP `class` | Igniter `compose` |
|---|---|---|
| Mutation | Mutable fields | Copy-on-write (immutable under the hood) |
| Inheritance | class extends | compose extends (flat mixin) |
| Methods | Arbitrary side effects | Pure contracts only |
| State | Mutable reference | Temporal[T] with auto-history |
| Dispatch | Virtual table | Contract registry dispatch |

`compose` is NOT a class. It's a **declarative, pure, temporal state machine** with pluggable contract behaviors.

---

## Technical Indicators Validated

| Indicator | Algorithm | fold() used? | Status |
|---|---|---|---|
| SMA | sum(closes) / N | ✅ Yes | ✅ Works |
| EMA | fold with k-weighted accumulator | ✅ Yes | ✅ Works |
| RSI | Approximate via SMA proxy | ❌ | ⚠️ Proxy only |
| MACD | EMA_12 - EMA_26 | ✅ Yes (via EMA) | ⚠️ No signal line |

### RSI Limitation

True RSI requires tracking consecutive price changes (gains vs losses) which needs **either**:
- `zip` to pair consecutive candles, **or**
- fold-to-struct (accumulating {sum_gain, sum_loss, prev_close})

Since `fold` only returns a single scalar (it resolves type from the init arg), we cannot fold into a multi-field struct. This is a **new limitation discovery**.

### MACD Limitation

True MACD Signal Line requires EMA of historical MACD values. But we only have a single MACD value per call — no way to store MACD history across calls. This is the `Temporal[T]` pressure: MACD fundamentally needs history, proving that `temporal` should be a first-class concept.

---

## Summary of New Findings

| Discovery | Severity | Impact |
|---|---|---|
| `if { call_contract } else { call_contract }` → Unknown | 🔴 Critical | Blocks ALL conditional dispatch patterns |
| Inline records in if/else → Unknown | 🔴 Critical | Forces MakeXxx factory anti-pattern everywhere |
| fold-to-struct not possible | 🟡 High | fold accumulator must be scalar, not struct |
| No entity modeling primitive | 🔴 Critical | `compose` is needed to model real-world entities |
| OOF-TY1 strict on output | 🟡 High | Cannot output Unknown even if value is valid |
