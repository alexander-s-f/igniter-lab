module T3G
recursive contract T2Regression {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases items.tail
  max_steps 1000
}
