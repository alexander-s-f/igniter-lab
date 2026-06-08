module T2C
recursive contract OrderIndependent {
  input queue: JobQueue
  compute result = recur(queue.pending_jobs)
  output result: Integer
  decreases queue.pending_jobs
  max_steps 500
}

type JobQueue {
  pending_jobs: JobQueue
}

size_relation JobQueue pending_jobs
