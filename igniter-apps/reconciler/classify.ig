module ReconcilerClassify
import ReconcilerTypes

-- ============================================================
-- Classification — raw signal → epistemic Outcome (Covenant P15)
-- ============================================================
-- The honesty rule (failure_taxonomy/network_timeout_unknown_state.ig):
--   pre-dispatch failure         → UpstreamUnavailable (safe to retry)
--   ack + 2xx + real evidence    → SucceededReal
--   ack + 2xx + model evidence   → SucceededModel   (NOT real — no upward coercion)
--   ack + non-2xx                → FailedRetryable
--   dispatched, NO ack           → UNKNOWN external state
--                                  (budget>0 → UnknownWithBudget else UnknownNoBudget)

pure contract Is2xx {
  input code : Integer
  compute ok = if code >= 200 { if code < 300 { 1 } else { 0 } } else { 0 }
  output ok : Integer
}

pure contract ClassifyOutcome {
  input signal : DispatchSignal
  input request_id : String
  input attempt : Integer
  input budget_remaining : Integer

  compute ack2xx = call_contract("Is2xx", signal.status_code)

  compute outcome : Outcome = if signal.dispatch_started == 0 {
    -- never left our process: the external system saw nothing → safe retry
    UpstreamUnavailable { request_id: request_id }
  } else {
    if signal.ack_received == 1 {
      if ack2xx == 1 {
        if signal.evidence_kind == "real" {
          SucceededReal { request_id: request_id, resource: signal.resource }
        } else {
          -- acked + 2xx but only model-level evidence: do NOT call it real
          SucceededModel { request_id: request_id, resource: signal.resource }
        }
      } else {
        FailedRetryable { request_id: request_id, idempotency_key: "", attempt: attempt }
      }
    } else {
      -- dispatched but no acknowledgement: the defining unknown state
      if budget_remaining > 0 {
        UnknownWithBudget { request_id: request_id, attempt: attempt, budget_remaining: budget_remaining }
      } else {
        UnknownNoBudget { request_id: request_id, attempt: attempt }
      }
    }
  }
  output outcome : Outcome
}

-- ── Flattened label for logging (NOT the routing key) ───────
-- PRESSURE RC-P02: a stringly label is fine for a LOG line, but it must
-- never be the dispatch key — that is what the variant is for.
pure contract OutcomeKind {
  input o : Outcome
  compute kind : String = match o {
    SucceededReal {}       => "succeeded_real"
    SucceededModel {}      => "succeeded_model"
    FailedRetryable {}     => "failed_retryable"
    UnknownWithBudget {}   => "unknown_external_state"
    UnknownNoBudget {}     => "unknown_external_state"
    UpstreamUnavailable {} => "upstream_unavailable"
    Denied {}              => "denied"
  }
  output kind : String
}
