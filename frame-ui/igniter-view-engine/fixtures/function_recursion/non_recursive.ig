-- LAB-FUNCTION-RECURSION-P1 / Fixture A
-- non_recursive.ig
-- Baseline: def functions with no recursion.
-- No decreases evidence needed. Compiles cleanly in both Rust and Ruby toolchains.

module Lab.FunctionRecursion.NonRecursive

type Expr { kind: Text, num_val: Float?, left: Expr?, right: Expr? }
type CellValue { kind: Text, num_val: Float?, str_val: Text? }

-- Non-recursive: calls only built-ins and field accessors.
def make_number(n: Float) -> CellValue {
  { kind: "Number", num_val: n, str_val: none() }
}

def make_error(msg: Text) -> CellValue {
  { kind: "Error", num_val: none(), str_val: msg }
}

-- Non-recursive: helper that calls make_number (no cycle back).
def wrap_zero() -> CellValue {
  make_number(0.0)
}

-- Non-recursive: helper that calls make_error (no cycle back).
def wrap_unknown_kind(kind: Text) -> CellValue {
  make_error("Unknown expression kind: " + kind)
}
