module Lab.Multifile.Invalid.MissingSelective.Consumer
import Lab.Multifile.Invalid.MissingSelective.Types.{ MissingRecord }

pure contract NeedsMissingRecord {
  input value: String
  compute out = value
  output out : String
}
