module T3C
recursive contract UnregisteredAccessor {
  input items: Collection[Integer]
  compute result = recur(items.head)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
