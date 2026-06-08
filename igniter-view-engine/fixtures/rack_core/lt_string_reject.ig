module Rack.P6.LtStringReject

-- LAB-RACK-P6: negative fixture — proves TypeChecker rejects < for
-- non-Integer types (String < String → OOF-TY0).
-- Expected: compilation fails with OOF-TY0.
-- Closed: lab-only, no canon claim.

pure contract LtStringReject {
  input s : String
  input t : String

  compute bad_cmp = s < t

  output bad_cmp : Bool
}
