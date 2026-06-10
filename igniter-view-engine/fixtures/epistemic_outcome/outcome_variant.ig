module Lab.Epistemic.OutcomeVariant

-- LAB-OUTCOME-VARIANT-P1: Epistemic outcome as real variant + match.
--
-- Re-expresses the P4 KDR reconciliation routing model using the Rust lab
-- variant/match surface (LAB-VARIANT-RUST-P1 + LAB-VARIANT-VM-P1).
--
-- StillUnknown is split into StillUnknownWithBudget / StillUnknownNoBudget to
-- avoid requiring numeric if-conditions inside match arm bodies. The routing
-- semantics are preserved: budget-present arms reconcile, budget-absent hold.
--
-- Authority: LAB-ONLY. Not canon. Not production. No sealed Outcome[T,E].
-- Depends: LAB-VARIANT-RUST-P1, LAB-VARIANT-VM-P1, LAB-EPISTEMIC-OUTCOME-P4.

variant ReconciliationOutcome {
  ConfirmedSucceededReal        { request_id: String, resource: String }
  ConfirmedSucceededHuman       { request_id: String, resource: String }
  ConfirmedSucceededModel       { request_id: String, resource: String }
  ConfirmedFailedRetryable      { request_id: String, idempotency_key: String }
  ConfirmedFailedCompensatable  { request_id: String, compensation: String }
  ConfirmedFailedTerminal       { request_id: String }
  StillUnknownWithBudget        { request_id: String, attempt: Integer, budget_remaining: Integer }
  StillUnknownNoBudget          { request_id: String, attempt: Integer }
  PartiallyConfirmed            { request_id: String, resource: String }
  ReconciliationDenied          { request_id: String, reason: String }
  ReconciliationError           { request_id: String, detail: String }
}

-- ── RouteOutcome ────────────────────────────────────────────────────────────
-- Exhaustive match over all 11 arms. No wildcard.
-- Forbidden transitions enforced by distinct arm names, not hidden string checks.

contract RouteOutcome {
  input outcome: ReconciliationOutcome

  compute action: String = match outcome {
    ConfirmedSucceededReal {}        => "accept"
    ConfirmedSucceededHuman {}       => "accept"
    ConfirmedSucceededModel {}       => "needs_human_review"
    ConfirmedFailedRetryable {}      => "retry"
    ConfirmedFailedCompensatable {}  => "compensate"
    ConfirmedFailedTerminal {}       => "fail"
    StillUnknownWithBudget {}        => "reconcile_again"
    StillUnknownNoBudget {}          => "hold"
    PartiallyConfirmed {}            => "reconcile_remainder"
    ReconciliationDenied {}          => "hold"
    ReconciliationError {}           => "hold"
  }

  output action: String
}

-- ── Build contracts ─────────────────────────────────────────────────────────

contract BuildSucceededReal {
  input request_id: String
  input resource: String

  compute outcome: ReconciliationOutcome = ConfirmedSucceededReal {
    request_id: request_id,
    resource: resource
  }

  output outcome: ReconciliationOutcome
}

contract BuildSucceededHuman {
  input request_id: String
  input resource: String

  compute outcome: ReconciliationOutcome = ConfirmedSucceededHuman {
    request_id: request_id,
    resource: resource
  }

  output outcome: ReconciliationOutcome
}

contract BuildSucceededModel {
  input request_id: String
  input resource: String

  compute outcome: ReconciliationOutcome = ConfirmedSucceededModel {
    request_id: request_id,
    resource: resource
  }

  output outcome: ReconciliationOutcome
}

contract BuildFailedRetryable {
  input request_id: String
  input idempotency_key: String

  compute outcome: ReconciliationOutcome = ConfirmedFailedRetryable {
    request_id: request_id,
    idempotency_key: idempotency_key
  }

  output outcome: ReconciliationOutcome
}

contract BuildFailedCompensatable {
  input request_id: String
  input compensation: String

  compute outcome: ReconciliationOutcome = ConfirmedFailedCompensatable {
    request_id: request_id,
    compensation: compensation
  }

  output outcome: ReconciliationOutcome
}

contract BuildFailedTerminal {
  input request_id: String

  compute outcome: ReconciliationOutcome = ConfirmedFailedTerminal {
    request_id: request_id
  }

  output outcome: ReconciliationOutcome
}

contract BuildStillUnknownWithBudget {
  input request_id: String
  input attempt: Integer
  input budget_remaining: Integer

  compute outcome: ReconciliationOutcome = StillUnknownWithBudget {
    request_id: request_id,
    attempt: attempt,
    budget_remaining: budget_remaining
  }

  output outcome: ReconciliationOutcome
}

contract BuildStillUnknownNoBudget {
  input request_id: String
  input attempt: Integer

  compute outcome: ReconciliationOutcome = StillUnknownNoBudget {
    request_id: request_id,
    attempt: attempt
  }

  output outcome: ReconciliationOutcome
}

contract BuildReconciliationError {
  input request_id: String
  input detail: String

  compute outcome: ReconciliationOutcome = ReconciliationError {
    request_id: request_id,
    detail: detail
  }

  output outcome: ReconciliationOutcome
}

-- ── RouteBuiltOutcome ───────────────────────────────────────────────────────
-- Constructs and routes in one contract. Proves the full source → SIR → VM
-- pipeline: variant_construct lowers to Record, match_node reads __arm.

contract RouteBuiltOutcome {
  input request_id: String
  input resource: String

  compute outcome: ReconciliationOutcome = ConfirmedSucceededReal {
    request_id: request_id,
    resource: resource
  }

  compute action: String = match outcome {
    ConfirmedSucceededReal {}        => "accept"
    ConfirmedSucceededHuman {}       => "accept"
    ConfirmedSucceededModel {}       => "needs_human_review"
    ConfirmedFailedRetryable {}      => "retry"
    ConfirmedFailedCompensatable {}  => "compensate"
    ConfirmedFailedTerminal {}       => "fail"
    StillUnknownWithBudget {}        => "reconcile_again"
    StillUnknownNoBudget {}          => "hold"
    PartiallyConfirmed {}            => "reconcile_remainder"
    ReconciliationDenied {}          => "hold"
    ReconciliationError {}           => "hold"
  }

  output action: String
}
