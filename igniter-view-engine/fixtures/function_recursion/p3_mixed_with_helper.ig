-- LAB-FUNCTION-RECURSION-P3 / Reference Fixture
-- eval_expr/eval_ref spreadsheet pattern with helper.
-- Mirrors SS-P02/SS-P03 blocker context.
--
-- eval_expr: self-recursive AND calls eval_ref → in {eval_expr, eval_ref} mutual SCC
-- eval_ref:  calls eval_expr only → in the SAME mutual SCC
-- format_result: called by eval_expr but non-recursive → separate :none SCC
--
-- Under per-SCC rule:
--   SS-P02 minimal fix: decreases fuel on eval_expr only → eval_ref still REJECT
--   SS-P03 full fix:    decreases fuel on both → ACCEPT

module Lab.FunctionRecursion.P3.MixedWithHelper

type Expr { kind: Text, num_val: Float?, ref_id: Text?, left: Expr?, right: Expr? }
type CellValue { kind: Text, num_val: Float? }

-- Currently blocked by OOF-L4 (self-recursive, no evidence).
-- Add `decreases fuel` here to unblock SS-P02.
-- Under per-SCC model, eval_ref also needs it (SS-P03).
def eval_expr(expr: Expr) -> CellValue decreases fuel {
  if expr.kind == "Number" {
    { kind: "Number", num_val: expr.num_val }
  } else {
    eval_ref(expr.ref_id)
  }
}

-- Under per-SCC model: must also carry decreases fuel (SS-P03).
def eval_ref(ref_id: Text) -> CellValue decreases fuel {
  let dummy = { kind: "Number", num_val: 0.0, ref_id: none(), left: none(), right: none() }
  eval_expr(dummy)
}

-- Non-recursive display helper. Does NOT need decreases fuel.
def format_result(v: CellValue) -> Text {
  v.kind
}
