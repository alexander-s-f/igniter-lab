module Chain.B
import Chain.C.{ Tc }

pure contract MakeB {
  input c : Tc
  compute v : Integer = c.v
  output v : Integer
}
