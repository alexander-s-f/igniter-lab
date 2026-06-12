module DataFrameTypes

-- ============================================================
-- Matrices and DataFrames Core Types
-- ============================================================

-- ── Matrix (Sparse Coordinate Format) ───────────────────────
-- Since Igniter doesn't support 2D arrays naturally and lacks
-- indexed loops, the easiest way to represent a matrix is as a
-- Collection of Cells (Coordinate List - COO).

type Cell {
  row : Integer
  col : Integer
  val : Integer
}

type Matrix {
  rows : Integer
  cols : Integer
  cells : Collection[Cell]
}

-- ── DataFrame (Melted / Long Format) ────────────────────────
-- A traditional DataFrame is a collection of Rows, where each Row
-- has heterogeneous columns. Without Union types (Int|String|Float)
-- and native Map literals, the most Igniter-friendly way to represent
-- tabular data is the "Melted" or "Long" format (Entity-Attribute-Value).

type DataPoint {
  row_id : Integer
  col_name : String
  val : Integer
}

type DataFrame {
  data : Collection[DataPoint]
}
