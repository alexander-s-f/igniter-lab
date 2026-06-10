module Lab.ReservedFields.TypeField

-- OOF-KIND6: type declaration with reserved __arm field
type BadRecord {
  __arm: String,
  value: String
}

contract UsesBadRecord {
  input x: String
  compute result: String = x
  output result: String
}
