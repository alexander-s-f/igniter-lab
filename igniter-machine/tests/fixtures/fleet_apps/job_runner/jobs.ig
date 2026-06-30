module JobRunnerJobs
import JobRunnerTypes

-- ============================================================
-- Job contracts + STATIC dispatch
-- ============================================================
-- All jobs share the uniform arity (job_id, arg1, arg2) -> Integer so the
-- dispatcher can route positionally.

pure contract ProcessOrderJob {
  input job_id : String
  input arg1 : Integer
  input arg2 : Integer
  compute result = arg1 + arg2          -- stub: order total
  output result : Integer
}

pure contract ComputeReportJob {
  input job_id : String
  input arg1 : Integer
  input arg2 : Integer
  compute result = arg1 * 10            -- stub: report metric
  output result : Integer
}

pure contract ValidatePaymentJob {
  input job_id : String
  input arg1 : Integer
  input arg2 : Integer
  compute result = arg1 - arg2          -- stub: validation score
  output result : Integer
}

-- ── Static dispatcher ───────────────────────────────────────
-- PRESSURE JR-P02: the production fixture uses `call_contract(job_class, …)`
-- with a VARIABLE callee — which returns Unknown / fails closed
-- (LAB-DYNAMIC-CONTRACT-DISPATCH-P2). So we branch on the class STATICALLY
-- (the trade_robot StrategyDispatcher / call_router pattern). A typed job
-- registry would let the class be data without losing the static guarantee.
pure contract DispatchJob {
  input job_class : String
  input job_id : String
  input arg1 : Integer
  input arg2 : Integer
  compute result = if job_class == "process_order" {
    call_contract("ProcessOrderJob", job_id, arg1, arg2)
  } else {
    if job_class == "compute_report" {
      call_contract("ComputeReportJob", job_id, arg1, arg2)
    } else {
      if job_class == "validate_payment" {
        call_contract("ValidatePaymentJob", job_id, arg1, arg2)
      } else {
        0   -- unknown job class → no-op result (fail-closed at the gate)
      }
    }
  }
  output result : Integer
}

-- Is the job class known? (fail-closed gate)
pure contract KnownJob {
  input job_class : String
  compute known = if job_class == "process_order" { 1 } else {
    if job_class == "compute_report" { 1 } else {
      if job_class == "validate_payment" { 1 } else { 0 }
    }
  }
  output known : Integer
}
