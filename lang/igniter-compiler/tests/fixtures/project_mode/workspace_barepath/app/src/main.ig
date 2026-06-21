module App.Main
import PathLib.Util.{ Widget }

pure contract Build {
  input w : Widget
  compute s : Integer = w.size
  output s : Integer
}
