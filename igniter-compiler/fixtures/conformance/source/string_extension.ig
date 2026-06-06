-- string_extension.ig
-- Conformance fixture verifying String operations.

module SparkCRM.StringExtensions

contract StringWorkflow {
  input s1: String
  input s2: String
  input sep: String
  input prefix: String
  input sub: String

  compute len1 = length(s1)
  compute concatenated = concat(s1, s2)
  compute trimmed = trim(s1)
  compute split_col = split(s1, sep)
  compute has_sub = contains(s1, sub)
  compute has_prefix = starts_with(s1, prefix)

  output len1: Integer
  output concatenated: String
  output trimmed: String
  output split_col: Collection[String]
  output has_sub: Bool
  output has_prefix: Bool
}
