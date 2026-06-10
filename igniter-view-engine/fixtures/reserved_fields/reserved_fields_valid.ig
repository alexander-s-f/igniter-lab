module Lab.ReservedFields.Valid

-- Normal records and variants — must pass without OOF-KIND6.

type StatusRecord {
  kind: String,
  value: String,
  attempt: Integer
}

variant SimpleOutcome {
  Succeeded { result: String }
  Failed    { reason: String }
  Unknown   {}
}

contract BuildStatus {
  input kind: String
  compute record = { kind: kind, value: "ok", attempt: 1 }
  output kind: String
}

contract RouteOutcome {
  input outcome: SimpleOutcome
  compute action: String = match outcome {
    Succeeded {} => "accept"
    Failed {}    => "fail"
    Unknown {}   => "hold"
  }
  output action: String
}
