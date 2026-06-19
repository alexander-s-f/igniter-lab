module Lab.FormInvocation.Multi

-- Alpha and Beta: two targets; Composer uses both.
-- Proof-local: Composer could declare two forms, one per target.

contract Alpha {
  input x: String
  compute y = x
  output y: String
}

contract Beta {
  input a: String
  compute b = a
  output b: String
}

contract Composer {
  uses Alpha
  uses Beta
  input data: String
  compute result = data
  output result: String
}
