module T2B

size_relation TaskList pending
size_relation TaskList backlog

type TaskList {
  pending: TaskList
  backlog: TaskList
}

recursive contract MultiRelation {
  input tasks: TaskList
  compute result = recur(tasks.pending)
  output result: Integer
  decreases tasks.pending
  max_steps 500
}
