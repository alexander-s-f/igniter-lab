# LAB-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2 — guided diagnostic for nested collection ops

Status: CLOSED
Lane: standard / compiler diagnostics / collection HOF
Type: implementation recovery
Delegation code: OPUS-COLLECTION-NESTED-OPS-DIAGNOSTIC-P2
Date: 2026-06-21
Skill: idd-agent-protocol

## Context

Depends on:

- `LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1` — pressure finding: nested collection ops typecheck but
  fail at VM eval.
- `LAB-STDLIB-MATH-EVAL-AST-PARITY-P10` — single-level math inside HOF works.
- `LAB-STDLIB-MATH-NBODY-SWEEP-P11` — single-level collection folds are enough for order-parameter proof.

The pressure card found the next sharp edge:

```text
map(phases, p -> p + sum(map(phases, q -> sin(q - p))))
```

This typechecks but fails at runtime:

```text
EVALUATION FAILED: Unsupported operator: stdlib.collection.map
```

The proven workaround is to extract the inner reduction to a named contract and call it from the outer map:
`map(phases, p -> call_contract("CouplingStep", phases, p, ...))`.

## Goal

Do the cheap safety slice first: reject unsupported nested collection operations at compile/typecheck/emit time
with a clear diagnostic and workaround, instead of letting the VM fail late.

This card does **not** implement nested HOF execution.

## Verify first

- `lab-docs/lang/lab-nested-collection-ops-pressure-kuramoto-p1-v0.md`
- failing repro if present: `igniter-home-lab/apps/emergence/kuramoto/tick_nested_map_REPRO.ig`
- `lang/igniter-compiler/src/typechecker/stdlib_calls.rs`
- `lang/igniter-compiler/src/emitter.rs` HOF lowering (`map_reduce_aggregate`, pipeline lowering)
- existing diagnostics for HOF/lambda errors (`LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2`)
- `lang/igniter-vm/src/instructions.rs` and bytecode-map display if the repro mentions `0x20 UNKNOWN`

Live code wins. First determine the correct compiler layer for the diagnostic: typechecker if the nested shape
is visible there; emitter if typechecker has already normalized too much.

## Diagnostic shape

Introduce or reuse a collection diagnostic. Recommendation:

- rule: `OOF-COL-NESTED` (or next numbered `OOF-COL*` if local convention demands numbering);
- severity: error;
- message should include:
  - nested collection ops inside HOF lambdas are not executable in v0;
  - extract the inner operation to a named contract and call it with `call_contract`;
  - point to `LAB-NESTED-COLLECTION-OPS-PRESSURE-KURAMOTO-P1` proof if appropriate.

The diagnostic should catch at least:

- `map(xs, x -> map(...))`
- `map(xs, x -> sum(map(...)))`
- `map(xs, x -> fold(...))`
- same through `filter` / `filter_map` / `flat_map` if live shape shows the same unsupported path.

Do not reject:

- single-level `map(xs, x -> sin(...))`;
- top-level `sum(map(xs, x -> ...))` if it currently works;
- `map(xs, x -> call_contract("Inner", ...))` workaround.

## Required implementation

- Add a minimal failing fixture/test that currently would typecheck and fail at runtime.
- Add the diagnostic in the smallest compiler layer that sees the nested HOF shape.
- Add tests proving:
  - nested HOF emits the diagnostic;
  - single-level HOF still compiles;
  - top-level `sum(map(...))` still compiles if currently supported;
  - `call_contract` workaround compiles.
- Do not change VM execution semantics.

## Acceptance

- [x] Minimal nested `map-in-map` repro is covered by a compiler test.
- [x] Nested `map(xs, x -> sum(map(...)))` emits the new diagnostic.
- [x] Single-level `map` + math remains green.
- [x] Top-level `sum(map(...))` remains green if live-supported.
- [x] `map(xs, x -> call_contract("Inner", ...))` workaround remains green.
- [x] Error message names the workaround plainly.
- [x] No VM behavior changes.
- [x] Existing `stdlib_math_hof_tests` and `stdlib_math_nbody_tests` remain green.
- [x] Proof doc written: `lab-docs/lang/lab-collection-nested-ops-diagnostic-p2-v0.md`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-21)

**Implementation (`typechecker/stdlib_calls.rs` + tests only):** a guard before `match fn_name` in
`infer_stdlib_call` — if a lambda-bearing collection HOF's lambda body contains a nested collection op, push
**`OOF-COL-NESTED`** (named code, per card; avoids numbered-OOF-COL collision). Recursive walker
`expr_has_nested_collection_op` over the body AST. Detected set deliberately CONSERVATIVE — `map/filter/
filter_map/fold/reduce/sum` only; overloaded/scalar names excluded (caught a `concat` string-concat false
positive in `collection_comprehension_tests::outer_node_capture_works`, narrowed the set, green). Typechecker
sees the nested shape directly → no emitter/VM change. Proof doc: `lab-docs/lang/lab-collection-nested-ops-diagnostic-p2-v0.md`.

**Before/after:** the nested-map repro went from `status: ok` (then late `EVALUATION FAILED: Unsupported
operator: stdlib.collection.map`) → `status: oof` `OOF-COL-NESTED` at compile, message naming the
`call_contract` workaround.

**Proof — all green:** `collection_nested_ops_diagnostic_tests` **8** (4 reject + 4 non-regression),
`collection_comprehension_tests` 10 (concat false-positive fixed), full `igniter-compiler` suite green
(0 failed), `igniter-vm` `stdlib_math_hof_tests` 7 + `stdlib_math_nbody_tests` 5 green, `git diff --check`
clean. Home-lab repros behave: `tick_nested_map_REPRO`→OOF-COL-NESTED, `kuramoto_full_tick`/`nbody_order`→clean.

**Deferred (honest):** nested `count/any/concat/…` inside a lambda still fail late at the VM (excluded to avoid
false positives); full nested HOF EXECUTION is the larger card. **Next:** `LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3`
(emitter lowering inside lambda + capture wiring + VM support).

## Proof doc requirements

The proof doc must include:

- before/after error behavior;
- exact nested shapes caught;
- explicit non-regression list;
- why implementation of nested HOF execution remains deferred;
- next card for full execution support.

## Closed scope

- No nested HOF execution support.
- No VM opcode changes.
- No collection comprehension changes.
- No new syntax.
- No closure-conversion redesign.
- No canon claim.

## Next

`LAB-VM-NESTED-HOF-EVAL-AST-RECOVERY-P3` — implement nested HOF execution in eval_ast/VM once the diagnostic
has removed the runtime sharp edge.
