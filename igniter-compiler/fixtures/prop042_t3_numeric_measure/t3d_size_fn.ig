module T3D
recursive contract SizeFn {
  input items: Collection[Integer]
  compute result = recur(items.tail)
  output result: Integer
  decreases size(items)
  max_steps 1000
}
