module T2A
recursive contract TailDotted {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases items.tail
  max_steps 100
}
