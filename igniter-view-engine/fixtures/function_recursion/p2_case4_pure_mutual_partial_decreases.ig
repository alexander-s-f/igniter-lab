-- LAB-FUNCTION-RECURSION-P2 / Case 4
-- Pure mutual recursion: ping has `decreases fuel`, pong does not.
-- Expected SAFE behavior: OOF-L4 on pong (participates in cycle, no acknowledgment).
-- ACTUAL Rust behavior: status ok, diagnostics empty.
--
-- The `decreases fuel` on ping is never checked by the Rust typechecker
-- because is_recursive(ping.body, "ping") = false.
-- The annotation is silently accepted but not validated.
-- The annotation on pong is absent and also not checked.
-- Net result: the mutual cycle is completely undetected regardless of
-- whether one, both, or neither member carries the annotation.
--
-- Classification: BOUNDED GAP
--   Not as severe as Case 3 (at least ping carries a marker),
--   but the gap means the annotation provides false confidence.

module Lab.FunctionRecursion.P2.Case4

def ping(n: Float) -> Float decreases fuel {
  pong(n)
}

def pong(n: Float) -> Float {
  ping(n)
}
