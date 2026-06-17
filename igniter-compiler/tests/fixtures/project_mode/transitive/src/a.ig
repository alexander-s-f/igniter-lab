module Chain.A
import Chain.B.{ MakeB }

pure contract Top {
  input n : Integer
  compute m : Integer = n
  output m : Integer
}
