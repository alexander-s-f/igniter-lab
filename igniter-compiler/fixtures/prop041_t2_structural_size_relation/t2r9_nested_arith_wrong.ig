module T2R9Edges

size_relation NodeList next

type NodeList {
  next: NodeList
}

recursive contract NestedArithWrong {
  input items: NodeList
  compute result = 0 + recur(items)
  output result: Integer
  decreases items.next
  max_steps 200
}
