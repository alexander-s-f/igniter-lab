# Card: LAB-VM-AGGREGATE-SOURCE-REF-P1 — fold/aggregate source ref resolution

**Status: DONE 2026-06-15.** Both proof targets green; RUN-OK 13 → 15. Surfaced while
validating closures; it was a *separate* bug (not closure capture).

## Fix (reused the closures machinery)

- `compiler.rs` `map_reduce_aggregate` lowering: attach `captures:[{name,reg}]`
  (free refs of the aggregate node ∩ `compute_node_registers`) — same as the lambda arm.
- `vm.rs` `OP_MAP_REDUCE`: build `agg_env` via `collect_captures(&node, &registers)`,
  pass it as the eval scope for the **source**, **init**, and every **pipeline lambda**
  body (was `&HashMap::new()`). The source `ref` to a compute binding now resolves.

Proof: `sim_framework` (`'populations'`) and `trade_robot` (`'closes'`) now run end-to-end.
Build clean, no regression.

---

(original diagnosis retained below)

## Symptom

`Symbol 'populations' not found in env` (sim_framework), `'closes' not found`
(trade_robot). Both apps follow:

```
compute X = map(coll, e -> …)        -- X is a compute binding (register)
compute Y = fold(X, 0, (a,v) -> …)   -- X is the fold SOURCE arg, not a lambda free var
```

`X` is **not** captured-as-closure (it's not a free var inside the lambda). The error
is raised by `eval_ast` (the tree-walker), not the bytecode `OP_LOAD_REG` path — so the
`fold`/`map`-over-a-compute is being evaluated by the aggregate/tree-walk path, which
resolves the source `ref X` against `local_env / inputs / temporal` and misses the
register where `X` actually lives.

## Where to look

- `igniter-vm/src/compiler.rs`: how top-level `fold`/`map` chains lower — likely a
  `map_reduce_aggregate` node rather than a plain `OP_CALL` (see the aggregate handler
  around the `terminal_step` path in `vm.rs`).
- `igniter-vm/src/vm.rs`: the aggregate/`map_reduce_aggregate` execution path — its
  source expression is evaluated via `eval_ast` without the contract registers in scope.

## Fix direction (not yet chosen)

Either (a) the aggregate path resolves the source `ref` against `registers` (the same
way the bytecode `ref` lowering does), or (b) augment the aggregate's eval scope with
the needed compute bindings (mirror the closures chokepoint: expose compute registers
to `eval_ast` when it runs an aggregate source). Likely small once located.

## Proof targets

```text
igniter run igniter-apps/sim_framework  → success
igniter run igniter-apps/trade_robot    → success
```
Unblocks the two closure proof targets (which are otherwise closure-correct). Fleet
RUN-OK 13 → 15+.
