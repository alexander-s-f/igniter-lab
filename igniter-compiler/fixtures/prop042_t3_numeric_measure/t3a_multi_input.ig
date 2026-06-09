module T3A
recursive contract MultiInput {
  input items: Collection[Integer]
  input acc: Integer
  compute result = recur(items.tail, acc)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
