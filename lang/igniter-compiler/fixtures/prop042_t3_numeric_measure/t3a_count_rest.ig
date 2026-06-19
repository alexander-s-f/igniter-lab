module T3A
recursive contract CountRest {
  input items: Collection[Integer]
  compute result = recur(items.rest)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
