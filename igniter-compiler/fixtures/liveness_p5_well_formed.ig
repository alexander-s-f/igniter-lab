-- liveness_p5_well_formed.ig
-- LAB-COMPILER-LIVENESS-P5 regression guard: well-formed contracts still compile ok.
-- After P5 parser fixes, valid contracts must continue to compile successfully.
-- Expected: status="ok", no diagnostics.

module Lang.Lab.LivenessP5WellFormed

type Lead {
  bid_amount: Integer
  name: String
}

contract Add {
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}
