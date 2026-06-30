-- ambiguity.ig
-- H1 proof fixture: E-FORM-AMBIG, status=oof, NO winner selected
-- Two contracts claim same trigger "+" with same priority
-- Expected: compilation fails (oof); no form resolution occurs

module Forms.Hardening.Ambiguity

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

-- Trigger "+" → E-FORM-AMBIG error, status=oof, resolved_to=null
-- H1: NO winner selected — compilation must refuse
contract TriggerAmbiguity {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
