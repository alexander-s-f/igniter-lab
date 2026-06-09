-- liveness_p5_type_field_no_type.ig
-- LAB-COMPILER-LIVENESS-P5 fixture: malformed type declaration — field and colon but no type.
-- `type Lead { x: }` previously caused the parser to hang.
-- Expected: status="error", OOF-P1 diagnostic, no hang.

module Lang.Lab.LivenessP5TypeFieldNoType

type Lead {
  x:
}

contract Broken {
  input leads: Lead
  output result: Integer
}
