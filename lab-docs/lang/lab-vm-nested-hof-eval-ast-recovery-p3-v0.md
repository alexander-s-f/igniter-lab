# lab-vm-nested-hof-eval-ast-recovery-p3-v0 — execute nested HOFs inside lambda bodies

**Card:** `LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3` · **Delegation:** `OPUS-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3`
**Status:** CLOSED (lab implementation) — nested collection ops inside HOF lambda bodies now **execute**
through the real compiler + VM. The Kuramoto all-N tick runs in **one contract via `map(x -> sum(map(...)))`**,
no `call_contract`. **`vm.rs` `eval_ast` + narrowed P2 diagnostic + tests — no new syntax, no emitter change,
no closure-conversion redesign.**

## Exact root cause (classified against live code)

The lambda body is run by **`eval_ast`** (the VM's AST interpreter; the bytecode HOF arm at `vm.rs:2399`
serializes the lambda body to JSON and runs it via `eval_lambda`→`eval_ast`). Two concrete gaps, both inside
`eval_ast`'s call handler (`"apply"|"call"`):

1. **(#1) Qualified-name mismatch:** inner collection calls are serialized **qualified**
   (`"fn":"stdlib.collection.map"`) while `eval_ast`'s arms are **bare** (`"map"`), and `eval_ast` did **not**
   normalize. So existing bare collection arms were unreachable for qualified nested calls.
2. **(#2) Missing scalar-sum arm:** `eval_ast` had the 2-arg field form of `sum`, but not the scalar
   `sum(Collection[T])` form needed by `map(rows, row -> sum(row))`.

The P1 `captures:[]` lead was a **non-issue at `eval_ast`**: capture flows through the threaded `local_env`
(each element clones `local_env` and inserts the param), so an inner lambda sees the outer param naturally.

## The fix (`vm.rs` `eval_ast` only)

- Normalize: `let op = op.strip_prefix("stdlib.collection.").unwrap_or(op);` before `match op`, so qualified
  nested calls reach the existing bare collection arms.
- Add **scalar 1-arg `sum`** (numeric over Integer/Float/Decimal, mirroring the bytecode `sum if
  args.len()==1`).

## Before / after (live `igc compile` + `igniter-vm run`)

```text
# Kuramoto all-N tick, ONE contract, no call_contract:
map(phases, p -> p + dt*(omega + k_over_n*sum(map(phases, q -> sin(q - p)))))

BEFORE: typecheck ok → VM: EVALUATION FAILED: Unsupported operator: stdlib.collection.map
AFTER : Resulting Output: Array([0.17507684, 1.0, 1.82492316])   ✅ exact
```

Also now executing: `map(rows, row -> map(row, x -> x + 1.0))` → `[[11,21],[31]]`;
`map(rows, row -> sum(row))` → `[5.5, 1.5]`; `map(rows, row -> filter(row, x -> x > 1.0))` → `[[2,3],[1.5]]`.

## P2 diagnostic — narrowed (no longer rejects newly supported shapes)

`OOF-COL-NESTED`'s detected set went `{map,filter,filter_map,fold,reduce,sum}` → **`{fold, filter_map,
reduce}`**. `map`/`filter`/`sum` now execute nested, so they compile. **`fold` stays guarded** because the
emitter lowers it to a `map_reduce_aggregate` SIR node that `eval_ast` cannot run nested (distinct from a
`call` node); `filter_map`/`reduce` have no `eval_ast` arm. These keep the early guided diagnostic instead of
a late VM failure — a correct narrowing, not a removal.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test nested_hof_eval_execution_tests       → 3 passed (tick, map-in-map, scalar-sum EXECUTE)
$ cd lang/igniter-compiler && cargo test --test collection_nested_ops_diagnostic_tests → 8 passed (map/sum now compile; fold/filter_map still guarded)
$ cd lang/igniter-vm && cargo test --test stdlib_math_hof_tests --test stdlib_math_nbody_tests → 7 + 5 passed
$ cd lang/igniter-compiler && cargo test                                        → full suite green (0 failed)
$ git diff --check                                                              → clean
```

New: `nested_hof_eval_execution_tests.rs` (3 e2e execution tests, sibling-compiler guarded). Updated P2 tests:
`nested_map_in_map_now_compiles`, `map_with_sum_of_map_now_compiles` (was rejected → now compile),
`map_with_fold_is_still_rejected` + message test use the still-guarded fold shape.

**Pre-existing unrelated failure (honest):** `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops`
fails (`OP_GET_FIELD: expected Record, got Integer(1710000000)`) — **confirmed via `git stash` to fail
WITHOUT this change too** (a parallel agent's in-flight loop/temporal work). Not caused by, nor in scope of,
this card.

## Status of the P1 `call_contract` workaround

**Still works** (`kuramoto_full_tick.ig` compiles clean, unchanged). It remains the documented **factored /
testable** alternative — a per-element micro-rule as a named contract — and the **required** form for `fold`-
based coupling until nested `fold` is supported.

## What remains closed (deferred)

- **Nested `fold`** (the `map_reduce_aggregate` SIR kind in `eval_ast`), `filter_map`, `reduce` — still
  guarded by `OOF-COL-NESTED`; a follow-up can teach `eval_ast` the `map_reduce_aggregate` kind.
- Parallel-HOF optimization / dispatch-table rewrite; generic loops; collection-comprehension syntax — out of
  scope, unchanged.

## Files changed

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (narrowed `NESTED_COLLECTION_OPS`).
- `lang/igniter-vm/src/vm.rs` (`eval_ast`: qualified-name normalization + scalar-`sum` arm).
- `lang/igniter-vm/tests/nested_hof_eval_execution_tests.rs` (new, 3 e2e tests).
- `lang/igniter-compiler/tests/collection_nested_ops_diagnostic_tests.rs` (updated for the narrowing).

## Next

`LAB-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4` (optional) — teach `eval_ast` the `map_reduce_aggregate` kind so
nested `fold` executes too, then drop `fold` from the diagnostic. Until then `call_contract` covers `fold`.

---

*Lab implementation. 2026-06-21. Root cause: `eval_ast` lacked qualified-name normalization for nested
collection calls and lacked the scalar-`sum` arm (capture already worked via `local_env`). Nested `map`/`sum(map)` now execute — the Kuramoto
all-N tick runs in one contract, no `call_contract`. P2 diagnostic narrowed to the still-unsupported
`fold`/`filter_map`/`reduce`. 3 e2e + 8 diagnostic + 7 hof + 5 nbody green; full compiler suite green; one
pre-existing unrelated loop-test failure confirmed not mine; `git diff --check` clean.*
