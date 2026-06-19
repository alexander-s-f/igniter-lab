-- LAB-FUNCTION-RECURSION-P1 / Fixture C
-- mutual_recursive_fuel.ig
-- PROPOSED: mutually recursive def functions, each with `decreases fuel`.
--
-- Design question: does mutual recursion require evidence on ALL SCC members?
-- This fixture shows the SAFE answer: YES — all members of the SCC must declare
-- `decreases fuel`. The proof-local model validates this.
--
-- Current Rust is_recursive() only detects self-recursion. eval_ref in
-- spreadsheet/engine.ig does NOT call itself, so Rust does not flag it —
-- even though it participates in the eval_expr ↔ eval_ref mutual cycle.
-- This fixture shows what the CORRECT annotated form should look like.
--
-- Gap (SS-P03): Rust's is_recursive() currently only checks self-calls.
-- eval_ref would not be flagged without the annotation shown here.
-- Recommendation: extend detection to SCC-level (all members flagged).

module Lab.FunctionRecursion.MutualRecursiveFuel

type Expr { kind: Text, num_val: Float?, ref_id: Text?, left: Expr?, right: Expr? }
type CellValue { kind: Text, num_val: Float?, str_val: Text? }
type Grid { cells: Collection[Cell] }
type Cell { id: Text, ast: Expr }

-- Primary evaluator: self-recursive (Add/Number arms call eval_expr).
-- Also calls eval_ref for Ref-kind expressions.
-- With `decreases fuel` on both → SCC is fully evidence-covered.
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
        { kind: "Number", num_val: left_val.num_val + right_val.num_val, str_val: none() }
      } else {
        { kind: "Error", num_val: none(), str_val: "Unknown expression kind" }
      }
    }
  }
}

-- Reference resolver: not self-recursive, but part of eval_expr's SCC.
-- Without `decreases fuel` here, the mutual cycle is only half-covered.
-- Design recommendation: require evidence on ALL SCC members.
-- Current Rust: would NOT flag eval_ref (is_recursive check only looks for
-- direct self-call "eval_ref" in eval_ref's body — not found → no OOF-L4).
def eval_ref(ref_id: Text, grid: Grid) -> CellValue decreases fuel {
  let dummy_expr = { kind: "Number", num_val: 0.0, ref_id: none(), left: none(), right: none() }
  eval_expr(dummy_expr, grid)
}
