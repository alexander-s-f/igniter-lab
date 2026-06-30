-- liveness_p6_input_malformed.ig
-- LAB-COMPILER-LIVENESS-P6 fixture: malformed input declaration.
-- `input x` (no `: Type`) previously dropped silently (no diagnostic).
-- With P6: OOF-P1 emitted, parsing continues to `output result: Integer`.
-- Expected: status="error", OOF-P1 for malformed input, output still visible in parse.

module Lang.Lab.LivenessP6InputMalformed

contract Broken {
  input x
  output result: Integer
}
