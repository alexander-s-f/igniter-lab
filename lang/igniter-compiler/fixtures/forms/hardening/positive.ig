-- positive.ig
-- H4 + H6 + H3 proof fixture
-- Single unambiguous form; explicit call; sidecar resolution evidence

module Forms.Hardening.Positive

-- One form for "+": Add (Integer only)
-- H4: numeric + resolves to Add; no String+ or Collection+ form declared here
contract Add
  form (left) "+" (right)
  priority 5
  associativity :left
{
  input left: Integer
  input right: Integer
  compute result = left + right
  output result: Integer
}

-- H6: explicit call path — uses length(), a Call node
-- Call nodes emit explicit_call trace events; bypass form resolution entirely
contract ExplicitCallDemonstration {
  input s: String
  compute n = length(s)
  output n: Integer
}

-- P4 (sidecar): a + b resolves to Add in form_resolution_trace
-- SemanticIR retains binary_op — this is sidecar_resolution_only, not IR lowering
-- H3: confirmed honest posture
contract UseAdd {
  input a: Integer
  input b: Integer
  compute total = a + b
  output total: Integer
}
