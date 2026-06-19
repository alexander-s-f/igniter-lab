module Lab.Multifile.Invalid.UnknownImport.Consumer
import Lab.Multifile.Invalid.UnknownImport.Missing.{ MissingType }

pure contract UsesMissingType {
  input value: String
  compute out = value
  output out : String
}
