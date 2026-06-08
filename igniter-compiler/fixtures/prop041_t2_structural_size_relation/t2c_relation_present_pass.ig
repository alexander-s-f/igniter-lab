module T2C

size_relation NodeList next_segment

type NodeList {
  next_segment: NodeList
}

recursive contract RelationPresentPass {
  input items: NodeList
  compute result = recur(items.next_segment)
  output result: Integer
  decreases items.next_segment
  max_steps 300
}
