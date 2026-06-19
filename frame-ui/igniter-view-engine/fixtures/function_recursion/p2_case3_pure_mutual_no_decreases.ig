-- LAB-FUNCTION-RECURSION-P2 / Case 3 — THE CORRECTNESS BUG
-- Pure mutual recursion: ping calls pong, pong calls ping.
-- Neither function calls itself directly.
-- Expected SAFE behavior: OOF-L4 on both (both unacknowledged cycles).
-- ACTUAL Rust behavior: status ok, diagnostics empty.
--
-- WHY THIS IS A CORRECTNESS BUG (not just a gap):
--   is_recursive(ping.body, "ping") = false (ping doesn't call "ping")
--   is_recursive(pong.body, "pong") = false (pong doesn't call "pong")
--   → OOF-L4 loop is skipped entirely for both functions
--   → Programmer gets no acknowledgment requirement for an infinite loop
--
-- The safety property ("you must acknowledge potential non-termination")
-- is COMPLETELY BYPASSED for pure mutual recursion.
-- Calling ping() or pong() with no argument bound loops forever
-- with zero static warning.

module Lab.FunctionRecursion.P2.Case3

def ping(n: Float) -> Float {
  pong(n)
}

def pong(n: Float) -> Float {
  ping(n)
}
