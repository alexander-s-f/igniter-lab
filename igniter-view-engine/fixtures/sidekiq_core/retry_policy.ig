module Sidekiq.Lab.RetryPolicy

-- Static retry policy proof fixture — LAB-SIDEKIQ-P3
--
-- Proves: Sidekiq-like retry policy modeled as a pure BudgetedLocalLoop
-- over an explicit attempt counter with a static max_steps budget.
--
-- Contracts:
--   StubJob               — minimal dispatchable pure job (dispatch target for RetryWithDispatch)
--   RetryPolicy           — explicit attempt budget arithmetic; no clock; no queue
--   RetrySimulator        — BudgetedLocalLoop (PROP-039) over attempt outcomes; max_steps: 5
--   RetryWithDispatch     — call_contract dispatch + retry budget composability
--
-- Authority: lab-only — no Redis, no worker daemon, no scheduler,
-- no ServiceLoop, no Sidekiq compatibility claim, no stable API.
-- BudgetedLocalLoop (PROP-039): proposal-only, experiment-pass compiler surface.

-- ── StubJob: minimal dispatchable pure job ───────────────────────────────────
-- Provides a pure callee for RetryWithDispatch dispatch testing.
-- Arity matches P2 uniform arity: (job_id: String, arg1: Integer, arg2: Integer) -> Integer
-- Proves: call_contract(StubJob, ...) dispatches correctly in the retry context.
pure contract StubJob {
  input  job_id  : String
  input  arg1    : Integer
  input  arg2    : Integer
  compute result = arg1 + arg2
  output result  : Integer
}

-- ── RetryPolicy: explicit attempt budget arithmetic ──────────────────────────
-- Models the retry decision gate: given the current attempt counter and the
-- static maximum, compute how many retries remain.
--
-- budget_remaining > 0  -> retry permitted
-- budget_remaining = 0  -> budget exhausted (no more retries)
-- budget_remaining < 0  -> over-budget (deterministic signal; observable)
--
-- Proves: retry budget is explicit Integer arithmetic; no clock; no queue;
-- no scheduler; no external authority.
pure contract RetryPolicy {
  input  attempt       : Integer
  input  max_attempts  : Integer
  compute budget_remaining = max_attempts - attempt
  output budget_remaining  : Integer
}

-- ── RetrySimulator: BudgetedLocalLoop over attempt outcomes ──────────────────
-- outcomes: Collection[Integer] representing one element per retry attempt.
-- The loop counts total_attempts processed via an explicit loop-carried accumulator.
-- max_steps: 5 = maximum retry budget (static literal; Postulate 14).
--
-- BudgetedLocalLoop enforcement (PROP-039, VM runtime):
--   len(outcomes) <= 5  ->  processes all elements; returns total_attempts
--   len(outcomes) >  5  ->  VM OP_LOOP_STEP fuel check fires;
--                            error: "OOF-L-FUEL: loop fuel exhausted"
--
-- Proves:
--   - Retry loop terminates at max_steps budget
--   - Unbounded retry is structurally impossible in this model
--   - Retry count is a deterministic output of the loop
--   - No clock access, no scheduler, no queue, no side effects
pure contract RetrySimulator {
  input  outcomes      : Collection[Integer]
  compute total_attempts = 0

  loop RetryLoop outcome in outcomes max_steps: 5 {
    compute total_attempts = total_attempts + 1
  }

  output total_attempts : Integer
}

-- ── RetryWithDispatch: dispatch + retry budget composability ─────────────────
-- Dispatches the named job contract via call_contract (LAB-RACK-P9 mechanism)
-- and computes the remaining retry budget as pure Integer arithmetic.
--
-- job_result:       dispatch output (Unknown at compile time; Integer at VM runtime).
-- budget_remaining: retries remaining = max_attempts - attempt.
--
-- Proves: call_contract dispatch and retry budget check are composable as pure
-- data within the same contract. Does NOT retry the job — retry scheduling
-- is permanently closed in v0.
pure contract RetryWithDispatch {
  input  job_class    : String
  input  job_id       : String
  input  arg1         : Integer
  input  arg2         : Integer
  input  attempt      : Integer
  input  max_attempts : Integer
  compute job_result       = call_contract(job_class, job_id, arg1, arg2)
  compute budget_remaining = max_attempts - attempt
  output budget_remaining  : Integer
}
