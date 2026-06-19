module Lab.Epistemic.OutcomeVariant.OOF

variant SimpleOutcome {
  Succeeded {}
  Failed {}
  Unknown {}
}

contract OofKind1NonExhaustive {
  input outcome: SimpleOutcome

  compute action: String = match outcome {
    Succeeded {} => "accept"
    Failed {}    => "fail"
  }

  output action: String
}
