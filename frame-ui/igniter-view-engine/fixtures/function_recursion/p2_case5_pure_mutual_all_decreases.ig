-- LAB-FUNCTION-RECURSION-P2 / Case 5
-- Pure mutual recursion: BOTH functions have `decreases fuel`.
-- Expected safe behavior (under per-SCC model): accepted (all members annotated).
-- ACTUAL Rust behavior: status ok, diagnostics empty.
--
-- Annotations are silently accepted but NOT validated by the Rust typechecker
-- (is_recursive returns false for both → neither is checked).
-- The annotations exist but provide no enforcement today.
--
-- This is the TARGET STATE that a correct per-SCC model should accept.
-- Under per-SCC model: SCC {ping, pong} with all members having :fuel → ACCEPT.
-- Currently this compiles for the wrong reason (undetected, not validated).

module Lab.FunctionRecursion.P2.Case5

def ping(n: Float) -> Float decreases fuel {
  pong(n)
}

def pong(n: Float) -> Float decreases fuel {
  ping(n)
}
