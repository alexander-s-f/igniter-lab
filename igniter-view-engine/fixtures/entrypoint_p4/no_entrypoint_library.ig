module Entrypoint.P4.Library

pure contract Helper {
  input value : Integer
  compute result = value + 1
  output result : Integer
}
