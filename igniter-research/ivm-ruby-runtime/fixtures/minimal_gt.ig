module Playground.Comparison

contract MinimalGt {
  input a: Integer
  input b: Integer

  compute is_greater = a > b

  output is_greater: Bool
}
