module T3A
recursive contract CountTail {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
