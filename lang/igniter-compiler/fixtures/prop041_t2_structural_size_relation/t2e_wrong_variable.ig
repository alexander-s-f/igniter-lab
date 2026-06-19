module T2E

size_relation Pipeline steps

type Pipeline {
  steps: Pipeline
}

recursive contract WrongVariable {
  input items: Pipeline
  input other: Pipeline
  compute result = recur(items, other.steps)
  output result: Integer
  decreases items.steps
  max_steps 100
}
