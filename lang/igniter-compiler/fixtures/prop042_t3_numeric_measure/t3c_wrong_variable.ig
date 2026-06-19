module T3C
recursive contract WrongVariable {
  input items: Collection[Integer]
  input other: Collection[Integer]
  compute result = recur(other.tail, other)
  output result: Integer
  decreases count(items)
  max_steps 1000
}
