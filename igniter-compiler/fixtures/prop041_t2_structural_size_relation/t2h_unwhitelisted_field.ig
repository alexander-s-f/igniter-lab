module T2H
recursive contract UnwhitelistedField {
  input items: Collection[Integer]
  compute result = recur(items.first)
  output result: Integer
  decreases items
  max_steps 100
}
