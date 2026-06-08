module T2E

size_relation ItemQueue remaining

type ItemQueue {
  remaining: ItemQueue
  secondary: ItemQueue
}

recursive contract WrongAccessor {
  input queue: ItemQueue
  compute result = recur(queue.secondary)
  output result: Integer
  decreases queue.remaining
  max_steps 100
}
