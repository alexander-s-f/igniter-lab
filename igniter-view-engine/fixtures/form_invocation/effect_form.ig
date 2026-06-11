module Lab.FormInvocation.Effect

-- Logger: effect-modifier target contract
effect contract Logger {
  input log_text: String
  compute logged = log_text
  output logged: String
}

-- Analyzer: pure contract that uses Logger (typed-ref anchor)
-- Proof-local: a form targeting Logger preserves Analyzer's pure modifier.
contract Analyzer {
  uses Logger
  input text: String
  compute result = text
  output result: String
}
