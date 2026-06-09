-- liveness_p6_deferred_no_hang.ig
-- LAB-COMPILER-LIVENESS-P6 fixture: P7-deferred arms (window, loop, for) do not hang.
-- These arms still use .ok() (no outer OOF-P1) because skip_until_body_boundary would
-- stop at the inner } rather than the contract's closing }.
-- P7 will introduce skip_to_matching_brace and migrate these three arms.
-- Expected: status="error" (malformed decl), NO hang, does NOT require OOF-P1 from outer.

module Lang.Lab.LivenessP6DeferredNoHang

contract BrokenWindow {
  input x: Integer
  window
  output result: Integer
}
