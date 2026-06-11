module Lab.Multifile.Invalid.DuplicateContract.A

pure contract SharedName {
  input value: String
  compute out = value
  output out : String
}
