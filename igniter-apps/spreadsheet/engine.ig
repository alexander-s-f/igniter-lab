module SpreadsheetEngine
import SpreadsheetTypes

def eval_expr(expr: Expr, grid: Grid) -> CellValue decreases fuel {
  if expr.kind == "Number" {
    { kind: "Number", num_val: expr.num_val, str_val: none() }
  } else {
    if expr.kind == "Ref" {
      eval_ref(expr.ref_id, grid)
    } else {
      if expr.kind == "Add" {
        let left_val = eval_expr(expr.left, grid)
        let right_val = eval_expr(expr.right, grid)
        
        -- Testing if we can operate directly on Option[Float] or if we get an OOF.
        { kind: "Number", num_val: left_val.num_val + right_val.num_val, str_val: none() }
      } else {
        { kind: "Error", num_val: none(), str_val: "Unknown expression kind" }
      }
    }
  }
}

def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel {
  -- This creates a mutual recursion cycle with eval_expr, testing OOF-F1 thoroughly.
  let dummy_expr = { kind: "Number", num_val: 0.0, ref_id: none(), left: none(), right: none() }
  eval_expr(dummy_expr, grid)
}

contract CalculateGrid {
  input grid : Grid

  compute evaluated_cells = map(grid.cells, cell -> eval_expr(cell.ast, grid))

  output evaluated_cells : Collection[CellValue]
}
