-- SemanticIR lowering proof fixture.
-- FSL-3: resolved numeric/Additive + lowers to explicit invocation.

module Forms.SemanticIRLowering.Positive

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

contract UseIntegerAdd {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
