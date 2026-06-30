-- no_form_negative.ig
-- Proof fixture: P7 — no_form contracts fail closed
-- E-FORM-NOFM-DECL: no_form contract must not declare forms
-- E-FORM-NOFM-MATCH: no_form contract blocked at resolution

module Forms.NoFormNegative

-- P7: no_form contract — "+" is declared but should be blocked
-- E-FORM-NOFM-DECL expected in registry diagnostics
contract SafeAdd
  no_form
  form (left) "+" (right)
  priority 5
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- A contract that tries to use "+" which would resolve to SafeAdd
-- E-FORM-NOFM-MATCH expected in resolver diagnostics
-- Compilation should surface the error (fail-closed)
contract AttemptFormUse {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
