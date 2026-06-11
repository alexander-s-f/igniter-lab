-- LAB-FUNCTION-RECURSION-P2 / Case 2
-- Self-recursive def function WITH `decreases fuel` annotation.
-- Expected Rust behavior: no diagnostic, status ok (correct).
-- is_recursive("countdown") = true; decreases == "fuel" → gate satisfied.

module Lab.FunctionRecursion.P2.Case2

def countdown(n: Float) -> Float decreases fuel {
  countdown(n)
}
