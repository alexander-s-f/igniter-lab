-- SemanticIR lowering proof fixture.
-- FSL-6: E-FORM-AMBIG remains hard error with no accepted lowered output.

module Forms.SemanticIRLowering.Ambiguity

contract AddFirst
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract AddSecond
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract UseAmbiguousAdd {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
