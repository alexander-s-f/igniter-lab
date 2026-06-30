module T3D
recursive contract UnknownFn {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases depth(items)
  max_steps 1000
}
