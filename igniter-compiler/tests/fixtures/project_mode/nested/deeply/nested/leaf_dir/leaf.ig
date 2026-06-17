module Flat.Single

pure contract C {
  input x : Integer
  compute y : Integer = x
  output y : Integer
}
