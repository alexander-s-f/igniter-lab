module ReconcilerRoute
import ReconcilerTypes
import ReconcilerClassify

-- ============================================================
-- Routing — epistemic Outcome → action (+ idempotency gate)
-- ============================================================
-- The routing key is the VARIANT ARM, never a string. Distinct epistemic
-- states get distinct actions; model evidence never routes like real.

pure contract RouteOutcome {
  input o : Outcome
  compute action : String = match o {
    SucceededReal {}       => "accept"
    SucceededModel {}      => "needs_human_review"   -- no upward coercion
    FailedRetryable {}     => "retry"
    UnknownWithBudget {}   => "reconcile_again"
    UnknownNoBudget {}     => "escalate_human"
    UpstreamUnavailable {} => "retry"                -- pre-dispatch: safe
    Denied {}              => "hold"
  }
  output action : String
}

-- ── Idempotency gate (Covenant P16) ─────────────────────────
-- PRESSURE RC-P03: an action that mutates the external system ("retry",
-- "reconcile_again") is only SAFE if an idempotency key is present.
-- Without one, downgrade to "hold" — never retry blind.
pure contract ApplyIdempotencyGate {
  input action : String
  input idem_present : Integer
  compute gated = if idem_present == 1 {
    action
  } else {
    if action == "retry" {
      "hold"
    } else {
      if action == "reconcile_again" { "hold" } else { action }
    }
  }
  output gated : String
}

-- ── Outcome payload extractors (match-bound) ────────────────
pure contract OutcomeRequestId {
  input o : Outcome
  compute rid : String = match o {
    SucceededReal       { request_id } => request_id
    SucceededModel      { request_id } => request_id
    FailedRetryable     { request_id } => request_id
    UnknownWithBudget   { request_id } => request_id
    UnknownNoBudget     { request_id } => request_id
    UpstreamUnavailable { request_id } => request_id
    Denied              { request_id } => request_id
  }
  output rid : String
}

pure contract OutcomeAttempt {
  input o : Outcome
  compute n : Integer = match o {
    SucceededReal {}                 => 0
    SucceededModel {}                => 0
    FailedRetryable   { attempt }    => attempt
    UnknownWithBudget { attempt }    => attempt
    UnknownNoBudget   { attempt }    => attempt
    UpstreamUnavailable {}           => 0
    Denied {}                        => 0
  }
  output n : Integer
}

-- ── Receipt assembly ────────────────────────────────────────
pure contract BuildReceipt {
  input o : Outcome
  input idem_present : Integer
  input metadata : Map[String,String]

  compute raw_action = call_contract("RouteOutcome", o)
  compute action = call_contract("ApplyIdempotencyGate", raw_action, idem_present)
  compute rid = call_contract("OutcomeRequestId", o)
  compute attempt = call_contract("OutcomeAttempt", o)
  compute kind = call_contract("OutcomeKind", o)
  compute trace_id = or_else(map_get(metadata, "trace_id"), "none")

  compute receipt = {
    request_id: rid,
    action: action,
    outcome_kind: kind,
    attempt: attempt,
    trace_id: trace_id
  }
  output receipt : ReconReceipt
}
