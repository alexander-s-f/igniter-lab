module T2E

size_relation WorkList remaining

type WorkList {
  remaining: WorkList
}

recursive contract PlainRef {
  input queue: WorkList
  compute result = recur(queue)
  output result: Integer
  decreases queue.remaining
  max_steps 100
}
