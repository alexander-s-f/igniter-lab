-- liveness_p6_multi_keyword_recovery.ig
-- LAB-COMPILER-LIVENESS-P6 fixture: multiple different keyword failures in one contract.
-- Uses `42` (IntLit) after each keyword so each name_token() fails quickly and
-- independently, without consuming the next body-boundary keyword.
-- Before P6: all three dropped silently (no OOF-P1).
-- After P6: each emits OOF-P1 and recovery continues to the next declaration.
-- Expected: status="error", >= 3 OOF-P1 diagnostics, `output` still parsed.

module Lang.Lab.LivenessP6MultiKeywordRecovery

contract BrokenMix {
  input 42
  stream 42
  snapshot 42
  output result: Integer
}
