module Map.B
import Map.A.{ Rec }

pure contract C {
  input r : Rec
  compute v : Integer = r.missing_field
  output v : Integer
}
