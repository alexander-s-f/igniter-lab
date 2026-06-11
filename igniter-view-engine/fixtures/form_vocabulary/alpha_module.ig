module Lab.FormVocab.Alpha

-- AlphaFilter: pure contract used as vocabulary target.
-- Vocabulary word "filter" targeting this triggers at ".filter".
pure contract AlphaFilter {
  input value: String
  compute result = value
  output result: String
}

-- AlphaMapper: second contract in same module for multi-word vocabulary test.
pure contract AlphaMapper {
  input data: String
  compute mapped = data
  output mapped: String
}
