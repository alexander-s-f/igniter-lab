module T3H
recursive contract DottedCount {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases items.count
  max_steps 1000
}
