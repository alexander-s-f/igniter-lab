module DataFrameExample
import DataFrameTypes
import DataFrameMatrix
import DataFrameOps

-- ============================================================
-- Examples
-- ============================================================

contract RunMatrixExample {
  -- Create a 2x2 matrix:
  -- [ 1  2 ]
  -- [ 3  4 ]
  compute c00 = { row: 0, col: 0, val: 1 }
  compute c01 = { row: 0, col: 1, val: 2 }
  compute c10 = { row: 1, col: 0, val: 3 }
  compute c11 = { row: 1, col: 1, val: 4 }

  compute cells = [c00, c01, c10, c11]

  compute m = {
    rows: 2,
    cols: 2,
    cells: cells
  }

  -- Transpose
  compute mt = call_contract("MatrixTranspose", m)

  -- Scale by 10
  compute ms = call_contract("MatrixScale", m, 10)

  output mt : Matrix
  output ms : Matrix
}

contract RunDataFrameExample {
  -- Create a DataFrame with 2 rows, columns: "age", "salary"
  compute p1 = { row_id: 1, col_name: "age", val: 30 }
  compute p2 = { row_id: 1, col_name: "salary", val: 50000 }
  compute p3 = { row_id: 2, col_name: "age", val: 40 }
  compute p4 = { row_id: 2, col_name: "salary", val: 80000 }

  compute df = {
    data: [p1, p2, p3, p4]
  }

  -- Select the "salary" column
  compute salaries = call_contract("SelectColumn", df, "salary")

  -- Filter where age >= 35
  compute older = call_contract("FilterByThreshold", df, "age", 35)

  output salaries : Collection[DataPoint]
  output older : DataFrame
}
