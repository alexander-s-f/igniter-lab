module Lab.FormInvocation.Chain

-- A three-link chain: Step3 uses Step2, Step2 uses Step1.
-- Proof-local: each link could declare a form for its direct dependency.

contract Step1 {
  input n: String
  compute out = n
  output out: String
}

contract Step2 {
  uses Step1
  input n: String
  compute out = n
  output out: String
}

contract Step3 {
  uses Step2
  input n: String
  compute out = n
  output out: String
}
