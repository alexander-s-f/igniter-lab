module Lab.TypedRef.Chain

-- A three-link chain: Step3 -> Step2 -> Step1.
-- In the typed-ref model this produces a DAG with 2 dependency edges,
-- each edge inspectable as a ContractDependency.

pure contract Step1 {
  input n : Integer
  compute result = n + 1
  output result : Integer
}

pure contract Step2 {
  input n : Integer
  compute step1_result = call_contract("Step1", n)
  compute final = step1_result + 10
  output final : Integer
}

pure contract Step3 {
  input n : Integer
  compute step2_result = call_contract("Step2", n)
  compute total = step2_result + 100
  output total : Integer
}
