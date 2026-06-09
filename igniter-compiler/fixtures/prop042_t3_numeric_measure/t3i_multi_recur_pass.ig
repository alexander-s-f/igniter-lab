module T3I
recursive contract MultiRecurPass {
  input items: Collection[Integer]
  compute result = recur(items.tail) + recur(items.rest)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
