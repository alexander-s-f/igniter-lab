module T3C
recursive contract PlainRef {
  input items: Collection[Integer]
  compute result = recur(items)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
