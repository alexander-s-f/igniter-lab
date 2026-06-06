-- Type-directed dispatch proof fixture.
-- FTD-7: known primitive trigger with no form remains primitive_pass_through.

module Forms.TypeDispatch.MissingTrigger

contract PrimitiveMinus {
  input a: Integer
  input b: Integer
  compute diff = a - b
  output diff: Integer
}
