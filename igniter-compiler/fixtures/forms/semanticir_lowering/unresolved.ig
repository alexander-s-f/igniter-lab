-- SemanticIR lowering proof fixture.
-- FSL-8: typed trigger has registered forms but no surviving typed candidate.

module Forms.SemanticIRLowering.Unresolved

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

contract StringPlusRejected {
  input s1: String
  input s2: String
  compute bad = s1 + s2
  output bad: String
}
