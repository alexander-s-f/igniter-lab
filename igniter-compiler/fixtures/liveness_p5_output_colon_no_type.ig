-- liveness_p5_output_colon_no_type.ig
-- LAB-COMPILER-LIVENESS-P5 fixture: malformed output — colon but no type.
-- `output result:` previously caused the parser to hang.
-- Expected: status="error", OOF-P1 diagnostic, no hang.

module Lang.Lab.LivenessP5OutputColonNoType

contract Broken {
  input x: Integer
  output result:
}
