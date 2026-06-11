module Lab.Multifile.Invalid.Duplicate.Module

pure contract First {
  input value: String
  compute out = value
  output out : String
}
