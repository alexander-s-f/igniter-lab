module T2G
recursive contract T1Tail {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases items
  max_steps 100
}
