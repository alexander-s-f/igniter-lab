# Card: LAB-VM-EVALAST-MATCH-P1 — match_expr in the tree-walker

**Status: DONE 2026-06-15.** batch_importer GREEN (runs real validation); RUN-OK 16→17;
no regression (lead_router, call_router, air_combat, sim_framework unchanged).

## Implemented

Added a `"match_node" | "match_expr"` arm to `eval_ast` (vm.rs), mirroring the bytecode
path: eval `subject` → read its `__arm` discriminant from the `Value::Record`; for each
arm, match `pattern.arm` (or `wildcard`) against `__arm`; bind `pattern.bindings` payload
fields into a child env; eval the arm body. Fail-closed `Err` on no match. Sealed
Option/Result + user variants share the `__arm` SIR shape, so one arm covers all.

(original diagnosis below)

---

**Was: DIAGNOSED 2026-06-15.** Surfaced by the dispatch-completeness fix
(LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1, cluster 2).

## Symptom

`Unsupported AST kind in VM evaluator: match_expr` (batch_importer). The lambda body
`r -> match r { … }` (passed to `filter_map`) is tree-walked by `eval_ast`, which
handles binary_op / let / if_expr / … but **not `match_expr`**. The bytecode path
DOES handle match (`compiler.rs` `match_node | match_expr` → `__arm` discriminant +
OP_GET_FIELD + OP_EQ + OP_JMP_UNLESS chain).

## Why it matters

Same class as the if_expr / call_contract / closures gaps: a node kind the bytecode
compiler supports but the `eval_ast` tree-walker (lambda / HOF bodies) does not. `match`
inside a lambda is a common pattern (filter_map/map with a match body), so this unblocks
batch_importer and likely others.

## Fix direction

Add a `"match_node" | "match_expr"` arm to `eval_ast` (vm.rs) mirroring the bytecode
semantics on the variant representation (`Value::Record` with an `__arm` field):
1. eval the scrutinee → expect a record with `__arm`;
2. for each arm, compare its pattern against `__arm` (wildcard `_` matches anything);
3. bind the arm's payload field bindings into a child env;
4. eval the matched arm body. Fail closed (OP_UNSUPPORTED-equivalent) on no match.

## Proof target

```text
igniter run igniter-apps/batch_importer  → success  (restores it; runs real validation)
```
Restores RUN-OK and likely lifts other match-in-lambda apps. Note: batch_importer's
prior green was hollow (its validate contract was a skipped dispatch entry); this makes
it run for real.
