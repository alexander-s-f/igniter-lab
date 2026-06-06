-- Type-directed dispatch proof fixture.
-- FTD-5: equal surviving typed candidates produce E-FORM-AMBIG.

module Forms.TypeDispatch.Ambiguity

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
