-- Type-directed dispatch proof fixture.
-- FTD-1/FTD-2/FTD-10/FTD-11: typed operands select the Integer Add form.

module Forms.TypeDispatch.Positive

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
  compute n = length("typed")
  output total: Integer
}
