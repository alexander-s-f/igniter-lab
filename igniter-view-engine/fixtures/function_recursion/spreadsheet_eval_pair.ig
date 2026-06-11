-- LAB-FUNCTION-RECURSION-P1 / Fixture D
-- spreadsheet_eval_pair.ig
-- PRESSURE FIXTURE: exact eval_expr/eval_ref pattern from igniter-apps/spreadsheet/engine.ig
-- This fixture reproduces the SS-P02 and SS-P03 blockers verbatim.
-- It is intentionally missing `decreases fuel` to show the failing state.
--
-- CURRENT STATE (no evidence):
--   eval_expr is self-recursive with no `decreases fuel` → OOF-L4 fires (SS-P02)
--   eval_ref calls eval_expr but is NOT self-recursive → NOT flagged today (SS-P03 gap)
--
-- MINIMAL FIX FOR SS-P02:
--   Add `decreases fuel` to eval_expr's declaration (between return type and `{`)
--   See mutual_recursive_fuel.ig for the proposed annotated form.
--
-- DESIGN GAP (SS-P03):
--   eval_ref participates in the eval_expr ↔ eval_ref mutual SCC.
--   Current Rust detection misses this; a safe model requires evidence on eval_ref too.

module Lab.FunctionRecursion.SpreadsheetEvalPair

type Expr { kind: Text, num_val: Float?, ref_id: Text?, left: Expr?, right: Expr? }
type CellValue { kind: Text, num_val: Float?, str_val: Text? }
type Grid { cells: Collection[Cell] }
type Cell { id: Text, ast: Expr }

-- BLOCKED: OOF-L4 fires here (self-recursive, no decreases fuel)
def eval_expr(expr: Expr, grid: Grid) -> CellValue {
  if expr.kind == "Number" {
    { kind: "Number", num_val: expr.num_val, str_val: none() }
  } else {
    if expr.kind == "Ref" {
      eval_ref(expr.ref_id, grid)
    } else {
      if expr.kind == "Add" {
        let left_val = eval_expr(expr.left, grid)
        let right_val = eval_expr(expr.right, grid)
        { kind: "Number", num_val: left_val.num_val + right_val.num_val, str_val: none() }
      } else {
        { kind: "Error", num_val: none(), str_val: "Unknown expression kind" }
      }
    }
  }
}

-- NOT FLAGGED TODAY: is_recursive("eval_ref") = false (no self-call).
-- But eval_ref participates in the eval_expr ↔ eval_ref SCC.
-- A complete SCC-based check would require decreases fuel here too.
def eval_ref(ref_id: Text, grid: Grid) -> CellValue {
  let dummy_expr = { kind: "Number", num_val: 0.0, ref_id: none(), left: none(), right: none() }
  eval_expr(dummy_expr, grid)
}

contract CalculateGrid {
  input grid: Grid
  compute evaluated_cells = map(grid.cells, cell -> eval_expr(cell.ast, grid))
  output evaluated_cells: Collection[CellValue]
}
