module JobRunnerTypes

-- ============================================================
-- job_runner — a pure job dispatch + retry-budget model (Sidekiq-shaped)
-- ============================================================
-- Pulled from `igniter-view-engine/fixtures/sidekiq_core` (job_dispatch_table,
-- retry_policy, jobreceipt_schema). A job request names a job class + args; the
-- runner dispatches STATICALLY to the named job, then decides — per a static
-- retry budget — whether to retry, dead-letter, or finish. No Redis, no worker
-- daemon, no scheduler, no queue.
--
-- PURE CORE only. Whether an attempt "succeeds" is INJECTED (an attempt outcome
-- flag); a real runner re-dispatches a real effect. See PRESSURE_REGISTRY.md.

type JobRequest {
  job_class    : String   -- "process_order" | "compute_report" | "validate_payment"
  job_id       : String
  arg1         : Integer
  arg2         : Integer
  max_attempts : Integer
}

-- ── Job lifecycle outcome (sealed sum) ──────────────────────
-- PRESSURE JR-P01: the lifecycle is a sealed variant, not a stringly status.
variant JobOutcome {
  Done       { result : Integer, attempts : Integer }
  Retry      { budget : Integer, result : Integer }
  Exhausted  { attempts : Integer }
  DeadLetter { reason : String }
}

type JobReceipt {
  job_id   : String
  status   : String   -- flattened label for logging (NOT the routing key)
  result   : Integer
  attempts : Integer
}
