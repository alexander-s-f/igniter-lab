# LAB-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4 — execute nested `fold` (map_reduce_aggregate) in eval_ast

Status: CLOSED
Lane: standard / VM / collection HOF / science pressure
Type: implementation recovery
Delegation code: OPUS-VM-NESTED-FOLD-MAP-REDUCE-AGGREGATE-P4
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:
- `LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3` (CLOSED) — made nested `map`/`filter`/scalar-`sum` execute inside
  HOF lambda bodies via `eval_ast` arms + qualified-name normalization. It **explicitly deferred `fold`**.
- `LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2` — `OOF-COL-NESTED` guard; currently set `{fold, filter_map, reduce}`.

P3 root-caused the remaining `fold` gap precisely: the emitter lowers `fold` (and the aggregate forms) to a
**`map_reduce_aggregate`** SIR node, NOT a plain `call`. Top-level fold runs via the bytecode path, but a
`fold` nested inside a HOF lambda body is run by `eval_ast`, which has **no `map_reduce_aggregate` arm** →

```text
EVALUATION FAILED: Unsupported AST kind in VM evaluator: map_reduce_aggregate
```

So `map(xs, x -> fold(...))` typechecks (P2 currently guards it with `OOF-COL-NESTED` to avoid the late crash)
but cannot execute. This card removes that last gap.

## Node shape (from `lang/igniter-vm/tests/stdlib_math_nbody_tests.rs` `fold_sum_node`)

```json
{ "kind": "map_reduce_aggregate",
  "source": <collection expr>,
  "pipeline": [ { "kind": "fold", "param_acc": "acc", "param_val": "theta",
                  "init": <expr>, "body": <expr over acc, theta> } ] }
```

Top-level handling lives in the bytecode path (`vm.rs` ~2937–2961, `terminal_kind == "fold"`). Mirror its
semantics in `eval_ast`.

## Goal

Add a `map_reduce_aggregate` arm to `eval_ast` (`lang/igniter-vm/src/vm.rs`) so nested `fold` executes:
evaluate `source` → for the `fold` pipeline stage, seed `acc = eval_ast(init)`, then for each item bind
`param_acc`/`param_val` into a cloned `local_env` and `acc = eval_ast(body)`; return `acc`. Support the
`map`/`sum` pipeline kinds too IF the bytecode path does and it is cheap; otherwise scope to `fold` and say so.
Capture flows through the threaded `local_env` (same as P3's map/filter arms).

Then **narrow the P2 diagnostic**: `NESTED_COLLECTION_OPS` `{fold, filter_map, reduce}` → `{filter_map, reduce}`
(drop `fold`), so `map(x -> fold(...))` now compiles + executes instead of being rejected.

## Verify first

- `lab-docs/lang/lab-vm-nested-hof-eval-ast-recovery-p3-v0.md` (root cause + the P3 eval_ast arms to mirror).
- `lang/igniter-vm/src/vm.rs` — `eval_ast` (the `kind` dispatch; the P3 `map`/`filter`/`sum` arms ~line 4335)
  + the bytecode `map_reduce_aggregate`/fold handling (~2937–2961) to mirror semantics.
- `lang/igniter-vm/tests/stdlib_math_nbody_tests.rs` (`map_reduce_aggregate` node shape, `fold_sum_node`).
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs` (`NESTED_COLLECTION_OPS`).
- `lang/igniter-vm/tests/nested_hof_eval_execution_tests.rs` (P3 e2e harness to extend).

## Required implementation

- `eval_ast` `"map_reduce_aggregate"` arm executing the `fold` pipeline (and `map`/`sum` stages if the
  bytecode path does), capture via `local_env`.
- Narrow `NESTED_COLLECTION_OPS` to `{filter_map, reduce}`.
- No new syntax; no emitter change; no closure-conversion redesign; no bytecode-path change.

## Required tests

1. **executes**: `map(xss, row -> fold(row, 0.0, (acc, x) -> acc + x))` → per-row sums, through real
   compiler+VM (extend `nested_hof_eval_execution_tests.rs`).
2. **Kuramoto coupling via fold**: a `map(phases, p -> fold(phases, 0.0, (acc, q) -> acc + sin(q - p)))`
   all-N coupling executes (the `kuramoto_full_tick.ig` shape with fold instead of sum(map)).
3. **diagnostic narrowed**: update `collection_nested_ops_diagnostic_tests.rs::map_with_fold_is_still_rejected`
   → `map_with_fold_now_compiles` (is_ok, no `OOF-COL-NESTED`); move the message test to a still-guarded op
   (`filter_map`).
4. `stdlib_math_hof_tests` + `stdlib_math_nbody_tests` stay green.

## Acceptance

- [x] Root cause mirrored: `eval_ast` runs `map_reduce_aggregate` (`fold`) with `local_env` capture.
- [x] `map(xs, x -> fold(...))` executes through real compiler+VM (per-row + Kuramoto coupling cases).
- [x] P2 diagnostic narrowed to `{filter_map, reduce}`; `fold` no longer rejected; message test uses a still-
      guarded op.
- [x] `stdlib_math_hof_tests` + `stdlib_math_nbody_tests` + P2 + P3 e2e tests green.
- [x] No new syntax / emitter / bytecode-path change.
- [x] `git diff --check` clean.
- [x] Proof doc: `lab-docs/lang/lab-vm-nested-fold-map-reduce-aggregate-p4-v0.md`.

---

## Closing Report (2026-06-21)

**Fix:** `eval_ast` (`vm.rs`) gained a `map_reduce_aggregate` `match kind` arm running the `fold`/`reduce`
single-stage pipeline — `acc = eval(init)`, then per item bind `param_acc`/`param_val` into a cloned
`local_env` and `acc = eval(body)` — mirroring the bytecode terminal-fold semantics (~`vm.rs:3138`). Capture
flows through `local_env` (same as P3's map/filter). `NESTED_COLLECTION_OPS` narrowed `{fold, filter_map,
reduce}` → `{filter_map, reduce}` (drop `fold`); guard message + message-test moved to `filter_map`. No new
syntax / emitter / bytecode-path change. Proof: `lab-docs/lang/lab-vm-nested-fold-map-reduce-aggregate-p4-v0.md`.

**Live:** `map(xss, row -> fold(row, 0.0, (acc,x)->acc+x))` over `[[1,2,3],[10,20]]` → `[6.0, 30.0]`; Kuramoto
`map(phases, p -> fold(phases, 0.0, (acc,q)->acc+sin(q-p)))` over `[0,π/2,π]` → i=0 coupling ≈ 1.0 (real
`igc`+`igniter-vm run`).

**Tests/green:** `nested_hof_eval_execution_tests` **5** (3 P3 + 2 P4: per-row fold, Kuramoto fold coupling);
`collection_nested_ops_diagnostic_tests` **8** (fold flipped to compiles, message on filter_map);
`stdlib_math_hof` 7 / `stdlib_math_nbody` 5 / `stdlib_math_basics` 6 / compiler `stdlib_math` 6 — all green.
Full VM suite green except pre-existing unrelated `vmg13` (parallel agent's loop/temporal, ignored per card).
`git diff --check` clean.

**Scope notes:** `map`/`sum` *pipeline stages* and multi-stage nested pipelines deferred (clear error, not
wrong answer); `reduce` kept conservatively in the guard though the arm handles it. **Next:** the multi-step
Kuramoto time-integration LOOP (iteration construct — not math/collections) is the remaining blocker for the
full phase-transition sweep; `fold`-based all-pairs kernels are now writable nested directly.

## Known pre-existing (NOT yours)

`vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops` fails on a clean tree
(`OP_GET_FIELD: expected Record, got Integer(1710000000)`) — a parallel agent's in-flight loop/temporal work.
Confirmed via `git stash` in P3 to fail without P3's change. Ignore it; do not "fix" it.

## Closed scope

No new collection syntax; no comprehension changes; no parallel-HOF/dispatch optimization; no generic loops;
no broad closure-conversion redesign; no canon claim. After this, `fold`-based all-pairs kernels (the
parallel `nbody_*` authoring style) can be written nested directly; `call_contract` stays the factored option.
