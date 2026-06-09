-- liveness_p5_multiple_malformed.ig
-- LAB-COMPILER-LIVENESS-P5 fixture: multiple malformed declarations in one file.
-- Verifies that error recovery continues after a bad declaration,
-- producing diagnostics for ALL bad declarations (not just the first).
-- Expected: status="error", multiple OOF-P1 diagnostics, no hang.

module Lang.Lab.LivenessP5MultipleMalformed

contract BrokenA {
  input x: Integer
  output result
  output other: Integer
}

contract BrokenB {
  input y: Integer
  output
  output final_result: Integer
}
