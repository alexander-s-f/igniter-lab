module Rack.P6.EqTypeMismatch

-- LAB-RACK-P6: negative fixture — proves TypeChecker rejects == for
-- incompatible types (String == Integer → OOF-TY0).
-- Expected: compilation fails with OOF-TY0.
-- Closed: lab-only, no canon claim.

pure contract EqTypeMismatch {
  input path : String

  compute bad_check = path == 42

  output bad_check : Bool
}
