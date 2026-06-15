# Card: LAB-VM-RUNTIME-AIR-COMBAT-P1 — field access + call depth

**Status: DONE 2026-06-15** (implementation/proof milestone).

## What was done

Two contained runtime fixes in `igniter-vm/src/vm.rs`:

1. **Generalized `field_access`** in the `eval_ast` tree-walker. It previously only
   resolved `object.kind == "ref"` (`name.field`); any other object expression
   (nested `a.b.x`, call result, indexed element) fell through to
   `Field access not resolvable`. Now: after the ref-specific fast paths, evaluate
   the object expression and extract `field` from the resulting `Value::Record`.

2. **`MAX_CALL_DEPTH` 8 → 64.** air_combat's `RunDuel` makes legitimate deep
   cross-contract call chains (> 8, not cyclic). True cycles are caught separately
   by `__call_chain__` detection, so the depth guard is only a finite-chain
   backstop; 8 was too shallow for real apps.

## Proof

```text
igniter run igniter-apps/air_combat --entry RunDuel
→ {"status":"success","result":{"player_a":{...full duel...}}}  (latency ~1.6ms)
```

Fleet RUN-OK 12 → 13. No regression on the other 12.

## Closes

- field_access general case + call-depth backstop. Crystallized in
  `igniter-vm/IMPLEMENTED_SURFACE.md` (gap #3 → RESOLVED).
- Next runtime blockers tracked in `LAB-VM-HOF-CLOSURE-CAPTURE-P1`.
