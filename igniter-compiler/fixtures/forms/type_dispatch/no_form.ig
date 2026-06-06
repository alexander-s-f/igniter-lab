-- Type-directed dispatch proof fixture.
-- FTD-9: no_form remains fail-closed after type filtering is available.

module Forms.TypeDispatch.NoForm

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
