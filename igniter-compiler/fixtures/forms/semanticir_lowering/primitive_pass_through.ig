-- SemanticIR lowering proof fixture.
-- FSL-10: primitive pass-through remains primitive, not form lowering.

module Forms.SemanticIRLowering.PrimitivePassThrough

contract PrimitiveMinus {
  input a: Integer
  input b: Integer
  compute diff = a - b
  output diff: Integer
}
