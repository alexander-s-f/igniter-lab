# Card: LAB-VM-HOF-CLOSURE-CAPTURE-P1 — closures readiness/design

> [!IMPORTANT]
> **SUPERSEDED 2026-06-15 by `LAB-VM-HOF-CLOSURE-CONVERSION-P1`.** Decision made:
> **approach B** (compile-time analysis + runtime snapshot of declared captures).
> This card is retained as the readiness evidence that surfaced the A/B tradeoff.

**Status: READINESS / DESIGN (closed → superseded).** Decision required
(architectural): how lambdas capture enclosing scope.

## Problem

Lambdas passed to HOFs (`map`/`filter`/`fold`) do **not** capture the enclosing
contract's bindings. Example (`sim_framework/engine.ig`):

```
compute new_tick = state.tick + 1
compute evolved = map(state.entities, e ->
  call_contract("ApplyRulePipeline", e, config, new_tick, rule_names))
```

`new_tick`, `config`, `rule_names` are enclosing `compute` bindings. The lambda body
is tree-walked by `eval_ast` with `local_env = {e: item}` only → `Symbol 'new_tick'
not found in env`.

Blocks: **sim_framework, trade_robot** (`'closes'`), and likely any app using free
variables inside HOF lambdas (a common pattern).

## Why it happens (code evidence)

- Bytecode VM stores compute results in `registers: HashMap<i64, Value>` — keyed by
  **register index, not name** (`vm.rs:164`).
- HOF handlers build `local_env = HashMap::new(); insert(param, item)` and pass that
  to `eval_ast`/`eval_lambda` (`vm.rs:1309+` and the `stdlib.collection.*` path).
  No enclosing scope is threaded in.
- The compiler already computes a name→register map (`compute_node_registers` in
  `igniter-compiler`) but it is not available to the VM at the HOF call point.

## Approach A — runtime name→value capture at HOF entry

When the VM enters a HOF, snapshot the current contract's named bindings and pass
them as the lambda's base env (merged under `{param: item}`).

- Needs: the name→register map available at the HOF call point, so the VM can build
  `{name: registers[reg]}`. Emit `compute_node_registers` into the igapp per
  contract (like `dispatch_table` is) OR carry it on the executing frame.
- Pros: fix stays mostly in the VM (where we've been working); small compiler change
  (emit a map it already computes); no change to lambda representation; snapshot
  semantics are correct for these apps.
- Cons: over-captures (whole contract scope, harmless); must thread the name map to
  the execution point; capture is by-snapshot (fine here, no mutable closures in v0).

## Approach B — compile-time closure conversion

The compiler does free-variable analysis per lambda and makes the lambda
self-contained: either bind free vars as extra params at the HOF call site, or embed
captured values into the serialized lambda.

- Pros: precise capture (only real free vars); self-contained lambdas; the standard,
  "proper" technique; VM stays simple.
- Cons: larger compiler change (free-var analysis + lowering + serialization format);
  touches the front-end, not the VM.

## Recommendation

**Approach A for v0** — smallest, lowest-risk path to running the apps, keeps work in
the VM with a tiny compiler emission (a map the compiler already has). Treat
**Approach B as the eventual canonical form** (precise, self-contained) once the
runtime behavior is proven and the lambda serialization is ready to evolve.

## Decision needed

- [ ] A (runtime capture) vs B (compile-time conversion) for v0
- [ ] if A: where the name→reg map lives (igapp per-contract table vs execution frame)
- [ ] capture scope: whole-contract snapshot (simplest) vs free-vars-only

## Proof target (either approach)

```text
igniter run igniter-apps/sim_framework --entry RunEcosystemSim   → success
igniter run igniter-apps/trade_robot   --entry RunTradingBot      → success
```
Fleet RUN-OK 13 → 15+ (closes the closure-capture class).
