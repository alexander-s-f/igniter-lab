-- LAB-FUNCTION-RECURSION-P1 / Fixture B
-- self_recursive_fuel.ig
-- PROPOSED: self-recursive def functions with `decreases fuel` annotation.
-- Syntax: def name(params) -> ReturnType decreases fuel { body }
-- `decreases fuel` appears between the return type and the opening brace.
-- This syntax is already parseable by the Rust compiler (FunctionDecl.decreases field).
-- Without `decreases fuel`, the Rust typechecker emits OOF-L4.
-- With `decreases fuel`, the typechecker gate is satisfied.
-- Ruby typechecker does NOT check OOF-L4 for def functions (parity gap — P2 work).

module Lab.FunctionRecursion.SelfRecursiveFuel

type Expr { kind: Text, num_val: Float?, left: Expr?, right: Expr? }
type CellValue { kind: Text, num_val: Float?, str_val: Text? }

-- Self-recursive: count_depth counts the depth of a nested Expr tree.
-- Without `decreases fuel` → OOF-L4 in Rust typechecker.
-- With `decreases fuel` → gate satisfied; compilation proceeds.
def count_depth(expr: Expr) -> Float decreases fuel {
  if expr.left == none() {
    0.0
  } else {
    count_depth(expr.left) + 1.0
  }
}

-- Self-recursive: eval_simple evaluates only Number and Add expressions.
-- Direct self-call in both the left and right arms.
def eval_simple(expr: Expr) -> CellValue decreases fuel {
  if expr.kind == "Number" {
    { kind: "Number", num_val: expr.num_val, str_val: none() }
  } else {
    if expr.kind == "Add" {
      let left_val = eval_simple(expr.left)
      let right_val = eval_simple(expr.right)
      { kind: "Number", num_val: left_val.num_val + right_val.num_val, str_val: none() }
    } else {
      { kind: "Error", num_val: none(), str_val: "Unsupported expression kind" }
    }
  }
}
