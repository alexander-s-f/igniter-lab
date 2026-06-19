-- SemanticIR lowering proof fixture.
-- FSL-5: explicit calls bypass form lowering.

module Forms.SemanticIRLowering.ExplicitCall

contract AddInteger
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract ExplicitCallBypass {
  compute size = length("forms")
  output size: Integer
}
