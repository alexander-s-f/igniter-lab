module SpreadsheetExample
import SpreadsheetTypes
import SpreadsheetApi

-- Program entry point - zero-input workbook recalculation demo.
-- The fixture uses a single numeric cell so it exercises the recalculation
-- path without opening a broader spreadsheet formula/runtime surface.
entrypoint RunWorkbookDemo

pure contract MakeNumberExpr {
  input kind : Text
  input value : Float

  compute expr = {
    kind: kind,
    num_val: value,
    ref_id: none(),
    left: none(),
    right: none()
  }
  output expr : Expr
}

pure contract MakeCell {
  input id : Text
  input ast : Expr

  compute cell = { id: id, ast: ast }
  output cell : Cell
}

pure contract MakeGrid {
  input cells : Collection[Cell]

  compute grid = { cells: cells }
  output grid : Grid
}

contract RunWorkbookDemo {
  compute expr_a = call_contract("MakeNumberExpr", "Number", 7.0)
  compute cell_a = call_contract("MakeCell", "A1", expr_a)
  compute grid = call_contract("MakeGrid", [cell_a])

  compute evaluated = call_contract("RecalculateWorkbook", grid)
  output evaluated : Collection[CellValue]
}
