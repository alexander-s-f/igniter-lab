module Over.Main
import Over.Types.{ T }
import Over.Extra.{ E }

pure contract M {
  input t : T
  input e : E
  compute v : Integer = t.v + e.w
  output v : Integer
}
