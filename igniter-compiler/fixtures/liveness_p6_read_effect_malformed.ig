-- liveness_p6_read_effect_malformed.ig
-- LAB-COMPILER-LIVENESS-P6 fixture: malformed read and effect declarations.
-- Uses `42` (IntLit) after each keyword so name_token() fails without consuming
-- the next body-boundary keyword.  Before P6: dropped silently with no diagnostic.
-- Expected: status="error", OOF-P1 for effect, OOF-P1 for read (2 total).

module Lang.Lab.LivenessP6ReadEffectMalformed

contract Broken {
  effect 42
  read 42
  output result: Integer
}
