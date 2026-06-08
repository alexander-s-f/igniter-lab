module T2D

size_relation OtherList remaining

type MyList {
  remaining: MyList
}

recursive contract DifferentType {
  input items: MyList
  compute result = recur(items.remaining)
  output result: Integer
  decreases items.remaining
  max_steps 100
}
