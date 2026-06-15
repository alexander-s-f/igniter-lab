# Card: LAB-VM-ENTRYPOINT-SELECTION-P1 — orchestrator auto-entry

**Status: DONE 2026-06-15.** Runtime/UX hygiene, separate from closures.

## Problem

`tools/igniter` auto-entry matched any `Run*` contract, so a multi-contract app
could run an **inner** contract (e.g. `RunBacktest`, an input-taking helper) instead
of the orchestrator (`RunTradingBot`). That produced a false `c1 not found` (the
inner contract's input wasn't supplied) — see `LAB-VM-TRADE-ROBOT-LOAD-REF-P1`.

## Fix

`tools/igniter` entry resolution now: `entrypoint` decl → **orchestrator root** →
single contract → ask. Orchestrator root = a `Run*/Main*/Demo` contract that is
**not** a `call_contract("…")` target (a root, not a helper). Used only when exactly
one such root exists; otherwise still asks for `--entry`.

## Proof

```text
igniter run igniter-apps/trade_robot   → auto-picks RunTradingBot   (then closures gap)
igniter run igniter-apps/sim_framework → auto-picks RunEcosystemSim (then closures gap)
igniter run igniter-apps/dsa           → asks --entry (4 independent example roots — correct)
```

## Closed

- No VM/compiler change. Wrapper-only. Apps with several independent entry roots
  still correctly require `--entry`.
