module Lab.Epistemic.OutcomeVariant.OOF

variant SimpleOutcome {
  Succeeded {}
  Failed {}
  Unknown {}
}

contract OofKind3DuplicateArm {
  input outcome: SimpleOutcome

  compute action: String = match outcome {
    Succeeded {} => "accept"
    Failed {}    => "fail"
    Unknown {}   => "hold"
    Succeeded {} => "duplicate"
  }

  output action: String
}
