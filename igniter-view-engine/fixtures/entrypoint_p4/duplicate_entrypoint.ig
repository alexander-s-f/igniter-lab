module Entrypoint.P4.Duplicate

entrypoint FirstContract
entrypoint SecondContract

pure contract FirstContract {
  input value : Integer
  compute result = value + 1
  output result : Integer
}

pure contract SecondContract {
  input value : Integer
  compute result = value + 2
  output result : Integer
}
