module Lab.FormVocab.Consumer

-- Consumer uses AlphaFilter from the Alpha module (same-module canon test).
-- In a cross-module scenario this would need import resolution (OOF-REF2 gate).
-- For proof-local tests the typed-ref anchor is constructed from SIR.
pure contract AlphaFilter {
  input value: String
  compute result = value
  output result: String
}

contract Consumer {
  uses AlphaFilter
  input data: String
  compute processed = data
  output processed: String
}
