module Over.Main
import Over.Types.{ T }

pure contract M {
  input t : T
  compute v : Integer = t.v
  output v : Integer
}
