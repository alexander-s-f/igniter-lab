module Lab.Epistemic.OutcomeVariant.OOF

variant SimpleOutcome {
  Succeeded {}
  Failed {}
  Unknown {}
}

contract OofKind5DivergentTypes {
  input outcome: SimpleOutcome

  compute result = match outcome {
    Succeeded {} => "accept"
    Failed {}    => 0
    Unknown {}   => "hold"
  }

  output result: String
}
