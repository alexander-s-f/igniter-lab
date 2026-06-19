module Entrypoint.P4.Qualified

entrypoint Entrypoint.P4.Qualified.RunQualified

pure contract RunQualified {
  input value : Integer
  compute result = value + 3
  output result : Integer
}
