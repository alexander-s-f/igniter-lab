module T3F
recursive contract T1Items {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases items
  max_steps 100
}
