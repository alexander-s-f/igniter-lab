module T2R9Edges

size_relation NodeList next

type NodeList {
  next: NodeList
}

recursive contract IfWrongElse {
  input items: NodeList
  input n: Integer
  compute result = if n > 0 {
    recur(items.next, n - 1)
  } else {
    recur(items, n - 1)
  }
  output result: Integer
  decreases items.next
  max_steps 200
}
