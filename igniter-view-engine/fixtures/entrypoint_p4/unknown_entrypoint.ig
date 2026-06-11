module Entrypoint.P4.Unknown

entrypoint MissingContract

pure contract PresentContract {
  input value : Integer
  compute result = value + 1
  output result : Integer
}
