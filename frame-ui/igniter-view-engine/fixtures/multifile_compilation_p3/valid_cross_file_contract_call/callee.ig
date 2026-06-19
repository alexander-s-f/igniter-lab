module Lab.Multifile.Call.Callee

pure contract DoubleValue {
  input n: Integer
  compute doubled = n + n
  output doubled : Integer
}
