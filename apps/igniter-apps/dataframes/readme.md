# DataFrames and Matrices in Igniter

A proof-of-concept for implementing 2D data structures and tabular data processing in Igniter. This application explores how to model relational data without nested loops, dynamic map keys, joins, or union types. It currently achieves **full Rust compilation** with **8 contracts**.

This app is an app-pressure fixture, not a canon claim. It records which dataframe and matrix shapes are already comfortable in Igniter, and which relational operations still need language or stdlib support.

## Implementations

### 1. Matrix (`DataFrameMatrix`)
Due to the lack of 2D arrays (`col[i][j]`), matrices are represented in **Sparse Coordinate Format (COO)** using `Cell { row, col, val }`.
- `MatrixTranspose`: $O(N)$ perfect map operation over cells (swapping `row` and `col`).
- `MatrixScale`: $O(N)$ map operation multiplying values.
- `MatrixAdd`: Blocked. Adding two sparse matrices requires matching cells by `(row, col)`. Without `group_by` or `flat_map`, this forces an $O(N^2)$ cross-join that cannot be easily aggregated due to the missing `reduce`.

### 2. DataFrame (`DataFrameOps`)
Without heterogeneous typed columns (`Union[Integer, String]`) or generic `Map` literals, the DataFrame is modeled in **Melted / Long Format** using `DataPoint { row_id, col_name, val }`.
- `SelectColumn`: $O(N)$ trivial filter over `col_name`.
- `FilterByThreshold`: Blocked. Filtering rows requires evaluating a condition on one column and applying the result to other rows sharing the same `row_id`. Without `group_by`, cross-row relational operations are currently impossible.

## Compilation

```bash
cd igniter-compiler
cargo run -- compile ../igniter-apps/dataframes/types.ig ../igniter-apps/dataframes/matrix.ig ../igniter-apps/dataframes/dataframe.ig ../igniter-apps/dataframes/example.ig --out /tmp/dataframes.igapp
```

**Result**: Full compilation — 8 contracts emitted, zero diagnostics.

## Pressure Registry

See [PRESSURE_REGISTRY.md](PRESSURE_REGISTRY.md) for tracked pressure IDs, current evidence, and next routes.
