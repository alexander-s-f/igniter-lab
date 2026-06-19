module Over.Main
import Over.Types.{ T }

pure contract M {
  input t : T
  compute v : Integer = t.nonexistent_field
  output v : Integer
}
