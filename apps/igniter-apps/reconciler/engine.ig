module ReconcilerEngine
import ReconcilerTypes
import ReconcilerClassify

-- ============================================================
-- The reconciliation engine — step + bounded reconcile loop
-- ============================================================

-- One reconciliation attempt: classify the latest probe signal.
-- budget_remaining = max_attempts - attempt (epistemic retry budget).
pure contract ReconcileStep {
  input ctx : ReconContext
  input signal : DispatchSignal
  compute budget = ctx.max_attempts - ctx.attempt
  compute o = call_contract("ClassifyOutcome", signal, ctx.request_id, ctx.attempt, budget)
  output o : Outcome
}

-- Should we reconcile again? Only when still unknown AND budget remains.
pure contract ShouldReconcile {
  input o : Outcome
  compute again : Integer = match o {
    SucceededReal {}       => 0
    SucceededModel {}      => 0
    FailedRetryable {}     => 0
    UnknownWithBudget {}   => 1
    UnknownNoBudget {}     => 0
    UpstreamUnavailable {} => 0
    Denied {}              => 0
  }
  output again : Integer
}

-- Advance the context to the next attempt (factory).
pure contract NextContext {
  input ctx : ReconContext
  compute n = {
    request_id: ctx.request_id,
    idempotency_key: ctx.idempotency_key,
    attempt: ctx.attempt + 1,
    max_attempts: ctx.max_attempts
  }
  output n : ReconContext
}

-- ── Bounded reconciliation loop (manual unroll) ─────────────
-- PRESSURE RC-P04: this WANTS to be a fold-over-state / ServiceLoop:
--   fold(probes, ctx0, (ctx, sig) -> if still_unknown ReconcileStep else stop)
-- but state-threaded fold and a managed reconcile loop are unavailable, so
-- we unroll 3 attempts by hand (trade_robot RunBacktest pattern). The loop
-- also wants a clock/poll source (ServiceLoop / PROP-037) to space probes.
pure contract Reconcile3 {
  input ctx0 : ReconContext
  input s1 : DispatchSignal
  input s2 : DispatchSignal
  input s3 : DispatchSignal

  compute ctx1 = call_contract("NextContext", ctx0)
  compute ctx2 = call_contract("NextContext", ctx1)

  compute o1 = call_contract("ReconcileStep", ctx0, s1)
  compute o2 = if call_contract("ShouldReconcile", o1) == 1 {
    call_contract("ReconcileStep", ctx1, s2)
  } else {
    o1
  }
  compute o3 = if call_contract("ShouldReconcile", o2) == 1 {
    call_contract("ReconcileStep", ctx2, s3)
  } else {
    o2
  }
  output o3 : Outcome
}
