-- SemanticIR lowering proof fixture.
-- FSL-7: declaration order does not select a lowered semantic winner.

module Forms.SemanticIRLowering.DeclarationOrder

contract ZDeclaredFirst
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract ADeclaredSecond
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract UseDeclarationOrderCheck {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
