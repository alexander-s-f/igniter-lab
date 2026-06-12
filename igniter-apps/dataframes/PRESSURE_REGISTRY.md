# DataFrames Pressure Registry

This registry tracks language and stdlib pressure from the `dataframes` app. The app models matrices in COO form and dataframes in long form, then records where flat collection operations are sufficient and where relational operations are missing.

## Baseline

Rust compilation currently succeeds for:

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/dataframes/types.ig ../igniter-apps/dataframes/matrix.ig ../igniter-apps/dataframes/dataframe.ig ../igniter-apps/dataframes/example.ig --out /tmp/dataframes.igapp
```

Fresh observed result: all stages complete, 8 contracts emit, and diagnostics are empty. Current source hash: `sha256:61e705b88646fab28cee835a69a92bc9c0bb2f57e32e9bc554e750862e6aa6a4`. Liveness counters are small (`typechecker.infer_expr.max_depth=8`, `form_resolver.walk_expr.max_depth=8`). This baseline should be frozen by a dedicated proof card before being used as regression evidence.

## Pressures

| ID | Name | Evidence | Status | Next route |
|---|---|---|---|---|
| DF-P01 | Dataframes Rust baseline | Four-source app compiles through Rust with 8 contracts | Positive, needs frozen proof | `LAB-DATAFRAMES-BASELINE-P1` |
| DF-P02 | COO unary matrix operations | `MatrixTranspose` and `MatrixScale` are expressible as pure `map` transforms over `Cell` | Positive | Keep as collection-HOF fixture evidence |
| DF-P03 | Relational membership | Filtering one long-format dataframe slice and applying the resulting row IDs to another slice needs Bool membership (`contains` / `any` / `exists`) | Active | `LAB-STDLIB-COLLECTION-CONTAINS-P1` |
| DF-P04 | Empty / non-empty guards | Membership can be approximated by filter-then-empty-check only if `is_empty` / `non_empty` exists | Active, already on route | `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` |
| DF-P05 | Relational collection algebra | Matrix addition and dataframe row filtering need `join`, `group_by`, or `flat_map`; flat `map`/`filter` is not enough | Active, larger design | `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` |
| DF-P06 | Lambda record literal ambiguity | `map(cells, c -> { row: c.col, col: c.row, val: c.val })` parses `{` as a block, not a record literal | Active parser pressure | `LAB-LAMBDA-RECORD-LITERAL-P1` |
| DF-P07 | Contract invocation workaround | Record construction inside lambdas is moved into helper contracts and invoked through `call_contract` | Active bridge pressure | Typed invocation / forms route |

## Route Notes

First wave should stay focused on already-open collection primitives: append, equality, import surface, and empty guards. Dataframes belongs to the second wave because it introduces relational algebra, not just scalar collection helpers.

Recommended order:

1. `LAB-DATAFRAMES-BASELINE-P1` to freeze the Rust-positive app baseline.
2. `LAB-LAMBDA-RECORD-LITERAL-P1` to isolate parser pressure from stdlib pressure.
3. `LAB-STDLIB-COLLECTION-CONTAINS-P1` for Bool-producing membership helpers.
4. `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` for `group_by` / `join` / `flat_map` readiness.

## Non-Goals

- No dataframe package proposal is authorized by this app.
- No runtime authority, IO, or external storage claim is implied.
- No mutable HashMap or ambient indexing surface is implied.
- No walk-through artifact is tracked; durable evidence lives in this app folder only.
