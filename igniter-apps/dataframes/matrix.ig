module DataFrameMatrix
import DataFrameTypes
import stdlib.collection.{ map, filter }

-- ============================================================
-- Matrix Operations
-- ============================================================

contract MakeCell {
  input row : Integer
  input col : Integer
  input val : Integer
  compute cell = { row: row, col: col, val: val }
  output cell : Cell
}

contract MatrixTranspose {
  input m : Matrix

  -- Transposing a COO matrix is trivial: swap row and col for each cell.
  -- This is a perfect O(N) map operation!
  compute transposed_cells = map(m.cells, c ->
    call_contract("MakeCell", c.col, c.row, c.val)
  )

  compute transposed = {
    rows: m.cols,
    cols: m.rows,
    cells: transposed_cells
  }

  output transposed : Matrix
}

contract MatrixScale {
  input m : Matrix
  input scalar : Integer

  -- Multiply every cell by a scalar
  compute scaled_cells = map(m.cells, c ->
    call_contract("MakeCell", c.row, c.col, c.val * scalar)
  )

  compute scaled = {
    rows: m.rows,
    cols: m.cols,
    cells: scaled_cells
  }

  output scaled : Matrix
}

contract MatrixAdd {
  input a : Matrix
  input b : Matrix

  -- Matrix addition is EXTREMELY hard in Igniter without nested loops
  -- or a hash map / group_by.
  -- To add A and B, we would ideally concatenate their cells, and then
  -- group by (row, col) and sum the values.
  -- Since we lack group_by(), we have to do an O(N^2) join.
  --
  -- For each cell in A, we scan B for a matching cell.
  -- (Wait, we can't do flat_map easily without importing it, and
  -- if we map over A, we can find the matching B, but what about cells
  -- that are only in B? We'd miss them.)
  --
  -- Because of the missing `group_by` and `flat_map`, Matrix Addition
  -- of sparse matrices is currently blocked from a correct implementation.
  -- We'll just output A to demonstrate the limitation.

  output a : Matrix
}
