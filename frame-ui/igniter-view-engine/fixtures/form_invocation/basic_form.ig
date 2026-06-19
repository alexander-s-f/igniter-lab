module Lab.FormInvocation.Basic

-- Validator: the form's target contract (pure, 1 input, 1 output)
contract Validator {
  input value: String
  compute result = value
  output result: String
}

-- Processor: declares typed-ref anchor via uses.
-- Proof-local form notation (not canon-parsed):
--   [FORM] form (value) ".validate" -> Validator
contract Processor {
  uses Validator
  input data: String
  compute processed = data
  output processed: String
}
