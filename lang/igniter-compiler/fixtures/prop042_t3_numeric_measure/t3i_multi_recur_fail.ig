module T3I
recursive contract MultiRecurFail {
  input items: Collection[Integer]
  compute result = recur(items.tail) + recur(items)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
