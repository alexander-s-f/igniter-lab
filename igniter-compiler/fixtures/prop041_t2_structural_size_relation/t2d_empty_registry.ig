module T2D
type SomeType {
  next_item: SomeType
}

recursive contract EmptyRegistry {
  input data: SomeType
  compute result = recur(data.next_item)
  output result: Integer
  decreases data.next_item
  max_steps 100
}
