module Lab.Multifile.Invalid.DuplicateContract.B

pure contract SharedName {
  input value: String
  compute out = value
  output out : String
}
