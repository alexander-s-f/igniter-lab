module Lab.Multifile.Call.Caller
import Lab.Multifile.Call.Callee.{ DoubleValue }

pure contract UseDoubleValue {
  input n: Integer
  compute doubled = call_contract("DoubleValue", n)
  compute plus_one = doubled + 1
  output plus_one : Integer
}
