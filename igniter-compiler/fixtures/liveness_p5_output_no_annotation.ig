-- liveness_p5_output_no_annotation.ig
-- LAB-COMPILER-LIVENESS-P5 fixture: malformed output — missing type annotation.
-- `output result` without `: Type` previously caused the parser to hang.
-- Expected: status="error", OOF-P1 diagnostic, no hang.

module Lang.Lab.LivenessP5OutputNoAnnotation

contract Broken {
  input x: Integer
  output result
}
