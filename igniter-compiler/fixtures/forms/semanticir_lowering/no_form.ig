-- SemanticIR lowering proof fixture.
-- FSL-9: no_form remains fail-closed and emits no accepted lowered output.

module Forms.SemanticIRLowering.NoForm

contract ProtectedAdd
  no_form
  form (left) "+" (right)
  priority 5
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract AttemptProtectedUse {
  input x: Integer
  input y: Integer
  compute total = x + y
  output total: Integer
}
