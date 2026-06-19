module Lab.ReservedFields.VariantNameField

-- OOF-KIND6: type with reserved __variant field
type AnotherBad {
  __variant: String,
  data: String
}

contract UsesAnotherBad {
  input x: String
  compute result: String = x
  output result: String
}
