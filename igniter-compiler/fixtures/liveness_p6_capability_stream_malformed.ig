-- liveness_p6_capability_stream_malformed.ig
-- LAB-COMPILER-LIVENESS-P6 fixture: malformed capability and stream declarations.
-- Uses `42` (IntLit) after each keyword so name_token() fails without consuming
-- the NEXT body-boundary keyword.  Before P6 these dropped silently with no diagnostic.
-- Expected: status="error", OOF-P1 for capability, OOF-P1 for stream (2 total).

module Lang.Lab.LivenessP6CapabilityStreamMalformed

contract Broken {
  capability 42
  stream 42
  output result: Integer
}
