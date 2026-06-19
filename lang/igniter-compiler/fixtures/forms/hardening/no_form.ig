-- no_form.ig
-- H5 proof fixture: no_form still fail-closed after H1/H2 changes
-- Verify that E-FORM-NOFM-MATCH + E-FORM-NOFM-DECL still work correctly

module Forms.Hardening.NoForm

-- no_form contract with form declaration → E-FORM-NOFM-DECL
-- Also adds to no_form_contracts registry → E-FORM-NOFM-MATCH when trigger used
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

-- Using "+" → trigger in registry (ProtectedAdd) but blocked → E-FORM-NOFM-MATCH
-- After H1/H2 changes: error codes unchanged, behavior same
-- This is closest to "unresolved_form_error" representable in the lab
contract AttemptProtectedUse {
  input x: Integer
  input y: Integer
  compute total = x + y
  output total: Integer
}
