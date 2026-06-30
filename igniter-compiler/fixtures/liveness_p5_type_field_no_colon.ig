-- liveness_p5_type_field_no_colon.ig
-- LAB-COMPILER-LIVENESS-P5 fixture: malformed type declaration — field with no colon or type.
-- `type Lead { x }` previously caused the parser to hang.
-- Expected: status="error", OOF-P1 diagnostic, no hang.

module Lang.Lab.LivenessP5TypeFieldNoColon

type Lead {
  x
}

contract Broken {
  input leads: Lead
  output result: Integer
}
