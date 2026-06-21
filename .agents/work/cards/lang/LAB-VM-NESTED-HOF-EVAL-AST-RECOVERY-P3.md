# LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3 — eval_ast HOF parity for nested collection ops

Status: CLOSED
Lane: standard / VM / collection HOF / science pressure
Type: implementation recovery
Delegation code: OPUS-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1` — pressure + proven `call_contract` workaround.
- `LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2` — compile-time guard for the unsupported shape.
- `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — single-level HOF math parity.

This is the execution fix after the diagnostic. A fresh verify-first pass narrowed the root cause:

- single-level `map` works on the bytecode path;
- `eval_ast` already has working arms for `sum` and `filter`;
- `eval_ast` does **not** have equivalent arms for `map`, `fold`, or `reduce`;
- nested `map` inside a lambda must execute through `eval_ast`, so it fails with
  `Unsupported operator: stdlib.collection.map`.

Therefore the likely smallest fix is **eval_ast HOF parity**: add `map` and `fold/reduce` to the tree-walk
interpreter using the existing `filter` and `sum` arms as templates. Do not start with emitter rewrites unless
the failing test proves eval_ast parity is insufficient.

## Goal

Make these execute through the real compiler+VM without new syntax:

- `map(xs, x -> map(x.children, c -> ...))`
- `map(xs, x -> sum(map(x.children, c -> ...)))`
- `map(xs, x -> fold(x.children, init, (acc,c) -> ...))`

Preserve existing closure/capture semantics and do not regress the `call_contract` workaround.

## Verify first

- P1 pressure repro and proof doc.
- P2 diagnostic implementation and tests.
- `lang/igniter-vm/src/vm.rs` `eval_ast` HOF arms (`map`, `flat_map`, `filter`, `fold`, `sum`).
- `lang/igniter-compiler/src/emitter.rs` HOF lowering and lambda serialization.
- `lang/igniter-vm/src/compiler.rs` expression compiler for calls/operators.
- `lang/igniter-vm/src/instructions.rs` and bytecode-map display for `OP_CALL = 0x20`.
- Existing closure conversion/snapshot cards and tests.

Confirm the narrowed root cause before coding:

1. `eval_ast` has `sum` and `filter` arms but lacks `map` / `fold` / `reduce` arms.
2. qualified names such as `stdlib.collection.map` are normalized to the same behavior as `map`.
3. inner lambda receives both its own param and required outer lambda/env bindings.
4. bytecode-map `0x20 UNKNOWN` is either stale display or irrelevant to this eval_ast path.

## Required implementation

- Start with a failing VM test that uses the P1 nested map shape.
- Add `eval_ast` support for nested `map` by mirroring the existing `filter` implementation:
  evaluate collection + serialized lambda, parse lambda, bind param into an env cloned from `local_env`, call
  `eval_ast` on the lambda body, collect `Value::Array`.
- Add `eval_ast` support for nested `fold` / `reduce` by mirroring the existing HOF/runtime semantics:
  bind accumulator and item params, evaluate init/body in authored order.
- Normalize qualified names (`stdlib.collection.map`, `stdlib.collection.fold`, etc.) if those are what the
  compiler emits into lambda bodies.
- Preserve existing closure/capture behavior; do not invent a second capture model.
- Add tests for unqualified and qualified collection names if both are live.
- Add a Kuramoto all-N tick proof that executes without the `call_contract` workaround, unless the full tick is
  too large for this card; in that case, add the smallest all-pairs numeric equivalent.

## Acceptance

- [x] Root cause classified and documented.
- [x] `eval_ast` has explicit support for `map`.
- [x] `eval_ast` has explicit support for `fold` / `reduce`, or the proof doc justifies a narrower `map`-only fix.
- [x] `map(xs, x -> map(...))` executes through real compiler+VM.
- [x] `map(xs, x -> sum(map(...)))` executes through real compiler+VM.
- [x] `map(xs, x -> fold(...))` executes, unless `fold` is explicitly deferred with a diagnostic still in place.
- [x] Inner lambda can see the necessary outer lambda param or produces a precise diagnostic if deliberately unsupported.
- [x] Qualified and unqualified collection names are handled according to live surface.
- [x] Existing `stdlib_math_hof_tests` remain green.
- [x] Existing `stdlib_math_nbody_tests` remain green.
- [x] P2 `OOF-COL-NESTED` diagnostic is removed, narrowed, or updated so it no longer rejects newly supported shapes.
- [x] No new syntax.
- [x] Proof doc written: `lab-docs/lang/lab-vm-nested-hof-eval-ast-recovery-p3-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Root cause (classified):** the lambda body runs via `eval_ast`, whose call handler had bare collection arms
but did **not normalize** qualified `stdlib.collection.map` to those bare arm names (#1), and lacked the 1-arg
scalar `sum` form (#2). Capture was a non-issue — it flows through the threaded `local_env`.

**Fix (`vm.rs eval_ast` only):** qualified-name normalization (`strip_prefix("stdlib.collection.")`) + scalar
1-arg `sum` arm (mirroring the bytecode 1-arg sum). `map`/`filter`/`sum` now execute nested.

**fold deferral (justified):** the emitter lowers `fold` to a `map_reduce_aggregate` SIR node that `eval_ast`
can't run nested, so nested `fold` stays **guarded by `OOF-COL-NESTED`** (no compile-then-crash). P2 set
narrowed `{map,filter,filter_map,fold,reduce,sum}` → `{fold, filter_map, reduce}`.

**Proof — live:** Kuramoto all-N tick in ONE contract `map(p -> p + sum(map(q -> sin(q-p))))` →
`[0.17507684, 1.0, 1.82492316]` exact, no `call_contract`. Tests: `nested_hof_eval_execution_tests` 3 (e2e
execute), `collection_nested_ops_diagnostic_tests` 8 (updated), `stdlib_math_hof_tests` 7 + `stdlib_math_nbody_tests`
5, full `igniter-compiler` suite green (0 failed), `git diff --check` clean. The `call_contract` workaround
still compiles (factored alternative; required for `fold` coupling until P4).

**Pre-existing unrelated failure (honest):** `vm_candidate_proof_tests::test_proof_vmg13_local_loops_and_service_loops`
fails (`OP_GET_FIELD: expected Record, got Integer(1710000000)`) — **confirmed via `git stash` to fail without
this change** (a parallel agent's in-flight loop/temporal work). Not mine, not in scope.

**Proof doc:** `lab-docs/lang/lab-vm-nested-hof-eval-ast-recovery-p3-v0.md`. **Next (optional):** teach
`eval_ast` the `map_reduce_aggregate` kind so nested `fold` executes too, then drop `fold` from the diagnostic.

## Proof doc requirements

The proof doc must include:

- exact root cause (qualified-name mismatch + missing scalar-sum parity);
- before/after execution results;
- tests and counts;
- status of the P1 `call_contract` workaround after this fix;
- what remains closed: parallel HOF optimization, generic loops, collection-comprehension syntax.

## Closed scope

- No new collection syntax.
- No collection comprehension changes.
- No performance optimization or dispatch-table rewrite.
- No generic loop work.
- No broad closure-conversion redesign unless root cause proves unavoidable.
- No canon claim.

## Next

After this lands, all-pairs N-body/Kuramoto, Mat3 row operations, and richer linalg/science packages can use
nested HOFs directly. Keep the `call_contract` pattern documented as the factored/testable alternative.
