-- liveness_p6_well_formed_regression.ig
-- LAB-COMPILER-LIVENESS-P6 regression guard: all 11 newly-wrapped keywords still
-- parse correctly when well-formed. The recovery wrapping must not break valid paths.
-- Expected: status="ok", no diagnostics.

module Lang.Lab.LivenessP6WellFormedRegression

contract WellFormed {
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}
