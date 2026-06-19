module Lab.FormVocab.Beta

-- BetaFilter: different contract than AlphaFilter.
-- Used to test ambiguity when both Alpha.Forms and Beta.Forms
-- export the same trigger token ">>" for incompatible targets.
pure contract BetaFilter {
  input query: String
  compute matches = query
  output matches: String
}
