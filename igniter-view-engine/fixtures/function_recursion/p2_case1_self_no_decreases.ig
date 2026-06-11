-- LAB-FUNCTION-RECURSION-P2 / Case 1
-- Self-recursive def function with NO `decreases fuel` annotation.
-- Expected Rust behavior: OOF-L4 fires (correct).
-- is_recursive("countdown") = true (direct self-call in body).
-- Gate fires correctly — programmer must acknowledge non-termination.

module Lab.FunctionRecursion.P2.Case1

def countdown(n: Float) -> Float {
  countdown(n)
}
