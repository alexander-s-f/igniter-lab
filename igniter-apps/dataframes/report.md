# DataFrames & Matrices Pressure Report

This application stresses Igniter's ability to handle relational, multi-dimensional, and grouped data. By attempting to build a DataFrame engine, we hit the current limits of flat map/filter operations while preserving a positive Rust baseline.

**Current baseline:** Rust compilation succeeds for the four-source app (`types.ig`, `matrix.ig`, `dataframe.ig`, `example.ig`) with 8 contracts emitted and zero diagnostics. Fresh source hash: `sha256:61e705b88646fab28cee835a69a92bc9c0bb2f57e32e9bc554e750862e6aa6a4`. This is evidence that COO matrices and long-format dataframes are viable app-level representations in Igniter.

## 1. The Death of 2D Space

Igniter has no native multidimensional arrays. We successfully bypassed this using the **Sparse Coordinate Format (COO)** for matrices (`Cell {row, col, val}`).
- **Success**: Unary operations (Transpose, Scale) map perfectly and elegantly to this model. They are pure $O(N)$ map transformations.
- **Failure**: Binary operations (Matrix Addition, Matrix Multiplication) are practically blocked. Adding two sparse matrices requires finding overlapping `(row, col)` pairs and summing their values. This is a `JOIN` operation. Without `group_by`, `flat_map`, or native HashMaps accessible inside iterative closures, performing a relational join degrades into unmanageable $O(N^2)$ cross-filtering that cannot be correctly aggregated.

## 2. DataFrame Relational Algebra Blocks

We modeled a DataFrame using the **Melted / Long Format** (`DataPoint {row_id, col_name, val}`) because Igniter lacks heterogeneous arrays and dynamic struct keys.
- **Success**: Column selection (`SelectColumn`) is a trivial `filter(p.col_name == target)`.
- **Failure**: Cross-row relational algebra (e.g., `FilterByThreshold`) is blocked.
  To filter a DataFrame by age > 35, you must:
  1. Find the `row_id`s where `col_name == "age"` and `val > 35`.
  2. Retain ALL DataPoints (including "salary", "name", etc.) that share those `row_id`s.

This is a classic relational algebra problem. Igniter's `filter` is purely localized to a single element. We cannot perform a nested lookup such as `if contains(valid_row_ids, p.row_id)` because membership helpers are not yet stabilized as Bool-producing collection operations. The current workaround would require filtering to a candidate collection and then testing whether that collection is empty, which depends on `is_empty` / `non_empty` support.

## 3. Inline Record Literal Ambiguity (OOF-P0 / OOF-G1 Expanded)

We confirmed a parser limitation: **You cannot use an inline record literal `{ row: ..., col: ... }` directly as the body of a lambda.**
```igniter
-- This fails to parse (Unexpected token in expression: Colon)
compute cells = map(m.cells, c -> { row: c.col, col: c.row, val: c.val })
```
The parser seemingly interprets the `{` as the start of a `BlockBody` rather than a `RecordLiteral`.
**Workaround**: We must extract the record creation into a separate contract `MakeCell` and invoke it via `call_contract`.

## Pressure Register

| ID | Pressure | Status | Route |
|---|---|---|---|
| DF-P01 | Rust dataframe/matrix baseline | Positive | `LAB-DATAFRAMES-BASELINE-P1` |
| DF-P02 | COO matrix unary transforms | Positive | Keep as proof fixture for collection HOFs |
| DF-P03 | Relational membership / `contains` / `any` | Active | `LAB-STDLIB-COLLECTION-CONTAINS-P1` |
| DF-P04 | `is_empty` / `non_empty` guard helpers | Active, already aligned with stdlib route | `LANG-STDLIB-IS-EMPTY-PROP-P2/P3` |
| DF-P05 | `group_by` / `join` / `flat_map` relational algebra | Active, larger design track | `LAB-STDLIB-RELATIONAL-COLLECTIONS-P1` |
| DF-P06 | Inline record literals inside lambdas | Active parser pressure | `LAB-LAMBDA-RECORD-LITERAL-P1` |
| DF-P07 | `call_contract` as lambda record-construction workaround | Active bridge pressure | Typed invocation / forms track |

## Summary Table

| Feature / Need | Status | Implication |
|---|---|---|
| `group_by` / `join` | ❌ Missing | Blocks binary matrix operations and DataFrame aggregations |
| `is_empty` / `any` | ❌ Missing | Blocks cross-row lookups (e.g., WHERE id IN (SELECT...)) |
| Inline Records in Lambdas | ❌ Blocked | Forces creation of wrapper contracts like `MakeCell` |
| 2D Operations | ⚠️ Limited | COO Format allows unary ops, blocks binary ops |
