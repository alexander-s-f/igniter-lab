# lab-collection-nested-ops-diagnostic-p2-v0 — guided diagnostic for nested collection ops

**Card:** `LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2` · **Delegation:** `OPUS-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2`
**Status:** CLOSED (lab implementation) — a collection op nested inside a higher-order collection lambda now
fails at **typecheck** with `OOF-COL-NESTED` and names the `call_contract` workaround, instead of
typechecking and dying late at VM eval. **Typechecker only (`stdlib_calls.rs`) + tests — no VM/emit change, no
nested-execution support, no new syntax.**

## Before / after

Repro `igniter-home-lab/apps/emergence/kuramoto/tick_nested_map_REPRO.ig`
(`map(phases, p -> p + sum(map(phases, q -> sin(q - p))))`):

| | Before | After |
|---|---|---|
| `igc compile` | `status: ok` (typecheck passes) | `status: oof`, diagnostic `OOF-COL-NESTED` |
| `igniter-vm run` | `EVALUATION FAILED: Unsupported operator: stdlib.collection.map` (late) | n/a — caught at compile |
| guidance | none (opaque VM error) | message names the `call_contract` workaround + the P1 pressure card |

## Where + how

The nested shape is visible in the **typechecker** (the lambda body is raw AST at `infer_stdlib_call`'s
`args`), so the diagnostic lives there — no need to descend to the emitter. A single guard runs before the
`match fn_name`: if the call's base name is a lambda-bearing collection HOF and its lambda body contains a
nested collection op, push `OOF-COL-NESTED`.

- `LAMBDA_HOF_NAMES` (outer, scanned): `map, filter, filter_map, fold, reduce`.
- `NESTED_COLLECTION_OPS` (inner, detected): `map, filter, filter_map, fold, reduce, sum`.
- `expr_has_nested_collection_op` recursively walks the lambda body (Call/BinaryOp/UnaryOp/FieldAccess/
  IndexAccess/Lambda/If/Match/Block/ArrayLiteral/RecordLiteral/RecordSpread/VariantConstruct/Try), returning
  on the first nested collection op.

## Exact shapes CAUGHT

- `map(xs, x -> map(...))`
- `map(xs, x -> sum(map(...)))`
- `map(xs, x -> fold(...))`
- same through `filter` / `filter_map` / `fold` / `reduce` as the outer HOF.

## Explicit NON-regression (NOT caught)

- single-level `map(xs, x -> sin(x))` (math in lambda) — green;
- top-level `sum(map(xs, x -> ...))` (the inner map's lambda is simple) — green;
- top-level `fold(xs, 0.0, (acc, t) -> acc + det_cos(t))` (parallel N-body authoring) — green;
- `map(xs, x -> call_contract("Inner", ...))` workaround — green;
- comprehension `[ concat(prefix, t.title) for t in todos ]` → `map(todos, t -> concat(...))` — green.
  **`concat` is overloaded (string concat), so it is deliberately excluded** from the detected set (the
  initial broad set false-positived this; the set was narrowed to unambiguous higher-order/reduction ops).

**Conservative scope (honest):** overloaded / scalar-also collection names (`concat`, `count`, `is_empty`,
`min`/`max`, `range`, `take`, `first`, `last`, `zip`, `any`, `all`, `find`) are **excluded** to avoid false
positives. A nested `count`/`any`/etc. inside a lambda therefore still fails late at the VM (unchanged) — that
residue is covered by the full nested-execution card, not here.

## Why nested HOF execution stays deferred

This card is the **cheap safety slice**: turn a late, opaque runtime failure into an early, guided compile
error. Actually *executing* nested collection ops requires emitter HOF lowering inside lambda bodies + wiring
free-variable capture for the nesting lambda (the `captures:[]` bug from P1) + VM support for the `0x20`
path — a much larger change with its own card (`LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3`). Splitting removes
the sharp edge now without blocking on the big lift.

## Tests & commands — exact counts

```text
$ cd lang/igniter-compiler && cargo test --test collection_nested_ops_diagnostic_tests  → 8 passed (4 reject + 4 non-regression)
$ cd lang/igniter-compiler && cargo test --test collection_comprehension_tests          → 10 passed (concat-capture green)
$ cd lang/igniter-compiler && cargo test                                                → full suite green (0 failed)
$ cd lang/igniter-vm && cargo test --test stdlib_math_hof_tests --test stdlib_math_nbody_tests → 7 + 5 passed
$ git diff --check                                                                       → clean
```

New tests (8): `nested_map_in_map_is_rejected`, `map_with_sum_of_map_is_rejected`, `map_with_fold_is_rejected`,
`nested_diag_message_names_the_call_contract_workaround`, `single_level_map_with_math_is_clean`,
`top_level_sum_of_map_is_clean`, `top_level_fold_with_det_is_clean`, `call_contract_workaround_is_clean`.

## Acceptance — mapping

- [x] Minimal nested `map-in-map` repro covered by a compiler test.
- [x] `map(xs, x -> sum(map(...)))` emits `OOF-COL-NESTED`.
- [x] Single-level `map` + math remains green.
- [x] Top-level `sum(map(...))` remains green.
- [x] `call_contract` workaround remains green.
- [x] Error message names the workaround plainly.
- [x] No VM behavior changes (typechecker-only).
- [x] `stdlib_math_hof_tests` + `stdlib_math_nbody_tests` remain green.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (helpers + the `OOF-COL-NESTED` guard).
- `lang/igniter-compiler/tests/collection_nested_ops_diagnostic_tests.rs` (new, 8 tests).

## Next

`LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3` — implement nested HOF execution (emitter lowering inside lambda +
free-variable capture + VM support), removing the v0 restriction the diagnostic now guards.

---

*Lab implementation. 2026-06-21. Nested collection ops inside HOF lambdas now fail early with `OOF-COL-NESTED`
+ the `call_contract` workaround instead of a late VM `Unsupported operator`. Typechecker-only; conservative
detected set (no `concat` false positive); full suite + vm hof/nbody green; `git diff --check` clean.*
