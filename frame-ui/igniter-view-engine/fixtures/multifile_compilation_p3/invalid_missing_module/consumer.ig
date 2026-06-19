import Lab.Multifile.Invalid.MissingModule.Types

pure contract MissingModuleConsumer {
  input value: String
  compute out = value
  output out : String
}
