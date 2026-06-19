module Lab.ReservedFields.RecordLiteral

-- OOF-KIND6: record literal with reserved __arm field
contract UsesReservedLiteral {
  input value: String
  compute fake_variant: String = value
  compute bad_record = { __arm: "Injected", __variant: "Fake", value: value }
  output fake_variant: String
}
