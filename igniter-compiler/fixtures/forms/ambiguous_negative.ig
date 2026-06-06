-- ambiguous_negative.ig
-- Proof fixture: P9 — ambiguous form candidates fail closed
-- W-FORM-AMBIG expected when two contracts claim same trigger

module Forms.AmbiguousNegative

-- Two contracts both claim "+" with same priority
contract Add1
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

contract Add2
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- Using "+" should trigger W-FORM-AMBIG in resolver diagnostics
-- Compilation continues (warning, not error) but ambiguity is surfaced
contract UseAmbiguous {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
