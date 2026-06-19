module T2B

size_relation WorkQueue depth
size_relation EventLog remaining

type WorkQueue {
  depth: WorkQueue
}

type EventLog {
  remaining: EventLog
}

recursive contract DifferentTypes {
  input queue: WorkQueue
  compute result = recur(queue.depth)
  output result: Integer
  decreases queue.depth
  max_steps 200
}
