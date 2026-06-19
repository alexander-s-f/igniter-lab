-- LAB-FUNCTION-RECURSION-P3 / Reference Fixture
-- Recursive function calling a non-recursive helper.
-- SCC {recurse_with_helper}: self-loop → :self
-- SCC {format_result}: no cycle → :none
--
-- Under per-SCC rule:
--   recurse_with_helper: needs `decreases fuel` (recursive)
--   format_result: needs nothing (not in any cycle)
--
-- KEY POINT: the call from recurse_with_helper → format_result
-- does NOT drag format_result into the recursive SCC.
-- Tarjan's correctly identifies format_result as a separate SCC.

module Lab.FunctionRecursion.P3.HelperCall

-- Recursive, but calls a non-recursive helper.
-- Should need decreases fuel.
def recurse_with_helper(n: Float) -> Float decreases fuel {
  let result = recurse_with_helper(n)
  format_result(result)
}

-- Pure helper, not recursive. Does NOT need decreases fuel.
def format_result(n: Float) -> Float {
  n
}
