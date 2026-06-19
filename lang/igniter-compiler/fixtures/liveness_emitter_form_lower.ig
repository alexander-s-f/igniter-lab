-- liveness_emitter_form_lower.ig
-- LAB-COMPILER-LIVENESS-P4 calibration fixture
-- Exercises emitter.lower_expr_for_targets via a registered Add form
-- 30 left-associative additions matching the Add form trigger "+"
-- Expected: em_lower_max_depth ~ 30, status=ok

module Lang.Lab.LivenessEmitterFormLower

contract Add
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract DeepFormLowering {
  input a: Integer
  compute result = a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a + a
  output result: Integer
}
