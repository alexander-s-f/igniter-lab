# lab-vm-nested-fold-map-reduce-aggregate-p4-v0 — nested `fold` executes in eval_ast

**Card:** `LAB-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4` · **Delegation:** `OPUS-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4`
**Status:** CLOSED (implementation recovery) — a `fold` nested inside a HOF lambda body now **executes**.
`eval_ast` gained a `map_reduce_aggregate` arm running the `fold`/`reduce` pipeline stage with `local_env`
capture, mirroring the bytecode fold semantics; the P2 nested-collection guard is narrowed to drop `fold`.
**`vm.rs` + `stdlib_calls.rs` + tests only — no new syntax, no emitter change, no bytecode-path change.**

## The last gap (from P3)

P3 made nested `map`/`filter`/scalar-`sum` execute in `eval_ast` but **explicitly deferred `fold`**: the
emitter lowers `fold` to a **`map_reduce_aggregate`** SIR node (not a plain `call`), and `eval_ast`'s `kind`
dispatch had no arm for it:

```text
EVALUATION FAILED: Unsupported AST kind in VM evaluator: map_reduce_aggregate
```

So `map(xs, x -> fold(...))` typechecked (kept compiling only because P2 guarded it with `OOF-COL-NESTED` to
avoid this late crash) but could not run. This card removes the gap and the guard.

## Implementation (mirror the bytecode, no new path)

`eval_ast` (`vm.rs`) `match kind` gains:

```
"map_reduce_aggregate" =>
  source_val = eval_ast(source);  array = source_val as Array
  stage = pipeline[0]   (single stage — the nested shape the emitter produces)
  if stage.kind in {fold, reduce}:
      acc = eval_ast(init)
      for item in array:
          inner = local_env.clone(); inner[param_acc]=acc; inner[param_val]=item
          acc = eval_ast(body, inner)        // capture flows through local_env (same as P3 map/filter)
      Ok(acc)
  else: Err("stage '…' not yet supported in eval_ast (fold/reduce only)")
```

This is the exact semantics of the bytecode `map_reduce_aggregate` terminal-`fold` branch
(`vm.rs` ~3138) — `param_acc`/`param_val`/`init`/`body`, `eval_ast(body)` per item — so the nested and
top-level paths agree. **Scoped to a single `fold`/`reduce` stage** (the only nested shape the emitter
produces for `map(x -> fold(...))`); `map`/`sum` *pipeline stages* and multi-stage pipelines return a clear
error, not a silent wrong answer (deferred, said so).

## Diagnostic narrowed

`NESTED_COLLECTION_OPS` `{fold, filter_map, reduce}` → **`{filter_map, reduce}`** (drop `fold`). The message
("a still-unsupported collection op (filter_map/reduce) …") and the message-test fixture were moved to
`filter_map` (which still has no eval_ast arm). `reduce` is kept in the guard **conservatively** (the card's
instruction; its lowering is untested as a nested call), even though the eval_ast arm would also run a
`reduce` stage — a safe over-guard, never a wrong execution.

## Live end-to-end (real compiler + VM `run`)

```text
map(xss, row -> fold(row, 0.0, (acc, x) -> acc + x))   over [[1,2,3],[10,20]]   → [6.0, 30.0]
map(phases, p -> fold(phases, 0.0, (acc, q) -> acc + sin(q - p)))   over [0, π/2, π]   → i=0 coupling ≈ 1.0
```

The second is the **Kuramoto all-N coupling** in the parallel `nbody_*` fold-authoring style — now writable
nested directly, with `call_contract` remaining the optional factored form.

## Tests & commands — exact counts

```text
$ cd lang/igniter-vm && cargo test --test nested_hof_eval_execution_tests   → 5 passed (3 P3 + 2 NEW P4: per-row fold; Kuramoto fold coupling)
$ cd lang/igniter-vm && cargo test --test stdlib_math_hof_tests             → 7 passed (P10, unaffected)
$ cd lang/igniter-vm && cargo test --test stdlib_math_nbody_tests           → 5 passed (unaffected)
$ cd lang/igniter-vm && cargo test --test stdlib_math_basics_tests          → 6 passed (P7, unaffected)
$ cd lang/igniter-compiler && cargo test --test collection_nested_ops_diagnostic_tests → 8 passed (fold flipped to compiles; message on filter_map)
$ cd lang/igniter-compiler && cargo test --test stdlib_math_tests           → 6 passed
$ git diff --check                                                          → clean
```

**Pre-existing unrelated VM failure (NOT mine, per the card):** `vm_candidate_proof_tests::
test_proof_vmg13_local_loops_and_service_loops` (`OP_GET_FIELD: expected Record, got Integer(1710000000)`) —
a parallel agent's in-flight loop/temporal work; fails on a clean tree. Ignored, not "fixed".

## Acceptance — mapping

- [x] Root cause mirrored: `eval_ast` runs `map_reduce_aggregate` (`fold`) with `local_env` capture.
- [x] `map(xs, x -> fold(...))` executes through real compiler+VM (per-row + Kuramoto coupling).
- [x] P2 diagnostic narrowed to `{filter_map, reduce}`; `fold` no longer rejected; message test uses `filter_map`.
- [x] `stdlib_math_hof_tests` + `stdlib_math_nbody_tests` + P2 + P3 e2e tests green.
- [x] No new syntax / emitter / bytecode-path change.
- [x] `git diff --check` clean.

## Files changed

- `lang/igniter-vm/src/vm.rs` — `map_reduce_aggregate` arm in `eval_ast` (fold/reduce stage, local_env capture).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` — `NESTED_COLLECTION_OPS` → `{filter_map, reduce}` + message.
- `lang/igniter-vm/tests/nested_hof_eval_execution_tests.rs` (+2 P4 tests).
- `lang/igniter-compiler/tests/collection_nested_ops_diagnostic_tests.rs` (fold test flipped; message → filter_map).

## Closed scope

No new collection syntax; no comprehension changes; no parallel-HOF optimization; no generic loops; no
closure-conversion redesign; `map`/`sum` *pipeline stages* and multi-stage nested pipelines deferred (clear
error); no canon claim.

## Next

`fold`-based all-pairs / O(N²) kernels (the parallel `nbody_*` authoring style) can now be written nested
directly. Remaining for the full Kuramoto phase-transition sweep: the **multi-step time-integration loop**
(an iteration construct, not math/collections) — the standing `LAB-…-KURAMOTO-LOOP` line. `filter_map`/`reduce`
nested execution + `map`/`sum` pipeline stages in eval_ast are smaller follow-ons if pressure appears.

---

*Implementation recovery. 2026-06-21. Nested `fold` (the `map_reduce_aggregate` SIR node) now executes in
`eval_ast` by mirroring the bytecode fold semantics with `local_env` capture; the P2 guard drops `fold`.
`map(xs, x -> fold(...))` runs (per-row sums [6.0, 30.0]; Kuramoto coupling ≈1.0) through the real compiler +
VM. 5 nested-HOF e2e + 8 diagnostic + P7/P10/nbody math tests green; one pre-existing unrelated VM failure
ignored; `git diff --check` clean.*
