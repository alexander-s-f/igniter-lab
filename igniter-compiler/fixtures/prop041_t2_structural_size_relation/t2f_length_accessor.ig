module T2F
type Document {
  length: Integer
}

recursive contract LengthAccessor {
  input doc: Document
  compute result = recur(doc)
  output result: Integer
  decreases doc.length
  max_steps 100
}
