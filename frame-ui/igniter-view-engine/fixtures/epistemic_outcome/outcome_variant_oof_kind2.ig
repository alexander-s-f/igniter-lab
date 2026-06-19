module Lab.Epistemic.OutcomeVariant.OOF

variant SimpleOutcome {
  Succeeded {}
  Failed {}
  Unknown {}
}

contract OofKind2UnknownArm {
  input outcome: SimpleOutcome

  compute action: String = match outcome {
    Succeeded {}    => "accept"
    Failed {}       => "fail"
    Unknown {}      => "hold"
    NonExistent {}  => "oops"
  }

  output action: String
}
