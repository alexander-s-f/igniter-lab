module Lab.ReservedFields.VariantField

-- OOF-KIND6: variant arm with reserved __arm field
variant BadVariant {
  GoodArm  { value: String }
  ClashArm { __arm: String, value: String }
}

contract UsesBadVariant {
  input x: String
  compute result: String = x
  output result: String
}
