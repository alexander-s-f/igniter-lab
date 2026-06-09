module T2R9Edges

size_relation NodeList next

type NodeList {
  next: NodeList
}

recursive contract MultiRecurOneWrong {
  input items: NodeList
  compute result = recur(items.next) + recur(items)
  output result: Integer
  decreases items.next
  max_steps 200
}
