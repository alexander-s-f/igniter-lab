module Lab.Multifile.Invalid.Duplicate.Module

pure contract Second {
  input value: String
  compute out = value
  output out : String
}
