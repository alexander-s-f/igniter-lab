-- SemanticIR lowering proof fixture.
-- FSL-4: ++ lowers separately from +.

module Forms.SemanticIRLowering.ConcatSeparate

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

contract ConcatString
  form (left) "++" (right)
  priority 5
  associativity :left
{
  input left: String
  input right: String
  compute result = left ++ right
  output result: String
}

contract UseConcat {
  input left: String
  input right: String
  compute joined = left ++ right
  output joined: String
}
