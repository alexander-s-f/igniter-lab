module T2R9Edges

size_relation NodeList next

type NodeList {
  next: NodeList
}

recursive contract MultiRecurBothCorrect {
  input items: NodeList
  compute result = recur(items.next) + recur(items.next)
  output result: Integer
  decreases items.next
  max_steps 200
}
