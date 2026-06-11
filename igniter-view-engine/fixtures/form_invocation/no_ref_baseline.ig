module Lab.FormInvocation.NoRef

-- Validator: target contract present in module
contract Validator {
  input value: String
  compute result = value
  output result: String
}

-- Consumer: does NOT declare uses Validator.
-- Proof-local: any form targeting Validator from Consumer → E-FORM-NO-REF.
contract Consumer {
  input data: String
  compute result = data
  output result: String
}
