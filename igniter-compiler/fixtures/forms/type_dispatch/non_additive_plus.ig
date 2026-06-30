-- Type-directed dispatch proof fixture.
-- FTD-3/FTD-8: String + has a registered + trigger, but no surviving typed
-- candidate. The resolver must record unresolved_form_error.

module Forms.TypeDispatch.NonAdditivePlus

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
