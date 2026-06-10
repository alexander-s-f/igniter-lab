module Lab.Epistemic.OutcomeVariant.OOF

contract OofKind4NonVariantSubject {
  input status_str: String

  compute action: String = match status_str {
    Succeeded {} => "accept"
    Failed {}    => "fail"
    Unknown {}   => "hold"
  }

  output action: String
}
