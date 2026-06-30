module T2A
recursive contract RestDotted {
  input items: Collection[Integer]
  compute result = recur(items.rest)
  output result: Integer
  decreases items.rest
  max_steps 100
}
