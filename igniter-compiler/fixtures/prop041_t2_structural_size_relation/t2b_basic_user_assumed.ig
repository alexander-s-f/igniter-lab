module T2B

size_relation ItemList remaining

type ItemList {
  remaining: ItemList
}

recursive contract UserAssumedBasic {
  input items: ItemList
  compute result = recur(items.remaining)
  output result: Integer
  decreases items.remaining
  max_steps 1000
}
