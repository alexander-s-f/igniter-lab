# Card: LAB-VM-TRADE-ROBOT-LOAD-REF-P1 — diagnostic spike

**Status: DONE 2026-06-15 (spike).** Conclusion: **not a VM/compiler bug** — it folds
into closures.

## Question

Why does `trade_robot` fail with `Reference symbol 'c1' not found in inputs or
temporal context` at bytecode `OP_LOAD_REF`?

## Findings

- `c1` is an **input** of the inner contract `RunBacktest` (`backtester.ig:24
  input c1 : Candle`). The orchestrator `RunTradingBot` (`example.ig:9`) does
  `compute c1 = {…}` then `call_contract("RunBacktest", c1, …)`.
- The failure came from running `--entry RunBacktest` (an inner contract) **with
  empty inputs** — so its input `c1` genuinely wasn't supplied. OP_LOAD_REF was
  correct; the harness picked the wrong entry.
- Root cause = `tools/igniter` auto-entry matched `Run*` and chose the inner
  `RunBacktest` instead of the orchestrator `RunTradingBot`.

## Re-run with the correct entry

```text
igniter run igniter-apps/trade_robot --entry RunTradingBot
→ Symbol 'closes' not found in env
```

`'closes'` is an enclosing `compute` binding referenced inside a lambda → **the same
closure-capture gap as sim_framework**. So trade_robot is NOT a separate issue; it
merges into `LAB-VM-HOF-CLOSURE-CAPTURE-P1`.

## Follow-ups (small)

- Harness: improve `tools/igniter` auto-entry to prefer an `entrypoint` decl or an
  orchestrator (a contract whose result drives others) over any bare `Run*`.
- No compiler/VM change needed from this spike.
