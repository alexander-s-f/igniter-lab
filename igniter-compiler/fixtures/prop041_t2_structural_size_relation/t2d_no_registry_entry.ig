module T2D
type CustomList {
  remaining: CustomList
}

recursive contract NoRegistryEntry {
  input items: CustomList
  compute result = recur(items.remaining)
  output result: Integer
  decreases items.remaining
  max_steps 100
}
