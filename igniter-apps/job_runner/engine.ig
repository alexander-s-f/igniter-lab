module JobRunnerEngine
import JobRunnerTypes
import JobRunnerJobs

-- ============================================================
-- Retry budget + bounded retry loop (pure)
-- ============================================================

-- Retry budget = max_attempts - attempt (fixtures/sidekiq_core/retry_policy.ig).
pure contract RetryBudget {
  input attempt : Integer
  input max_attempts : Integer
  compute budget = max_attempts - attempt
  output budget : Integer
}

-- One attempt's outcome, given whether it succeeded (injected `ok`).
pure contract AttemptOutcome {
  input result : Integer
  input ok : Integer
  input attempt : Integer
  input max_attempts : Integer
  compute budget = call_contract("RetryBudget", attempt, max_attempts)
  compute o : JobOutcome = if ok == 1 {
    Done { result: result, attempts: attempt }
  } else {
    if budget > 0 {
      Retry { budget: budget, result: result }
    } else {
      Exhausted { attempts: attempt }
    }
  }
  output o : JobOutcome
}

pure contract ShouldRetry {
  input o : JobOutcome
  compute again : Integer = match o {
    Done {}       => 0
    Retry {}      => 1
    Exhausted {}  => 0
    DeadLetter {} => 0
  }
  output again : Integer
}

-- ── Bounded retry loop (manual unroll) ──────────────────────
-- PRESSURE JR-P03: the production fixture uses a managed `loop … max_steps: N`
-- (PROP-039 BudgetedLocalLoop) — but that surface is **Rust-only** today
-- (Ruby TC rejects loop-body compute reassignment with OOF-L7), so it is not
-- dual-clean. We unroll 3 attempts by hand; per-attempt success is injected.
pure contract RunWithRetry3 {
  input req : JobRequest
  input ok1 : Integer
  input ok2 : Integer
  input ok3 : Integer

  compute known = call_contract("KnownJob", req.job_class)
  compute result = call_contract("DispatchJob", req.job_class, req.job_id, req.arg1, req.arg2)

  compute o1 = if known == 0 {
    DeadLetter { reason: "unknown job class" }
  } else {
    call_contract("AttemptOutcome", result, ok1, 1, req.max_attempts)
  }
  compute o2 = if call_contract("ShouldRetry", o1) == 1 {
    call_contract("AttemptOutcome", result, ok2, 2, req.max_attempts)
  } else {
    o1
  }
  compute o3 = if call_contract("ShouldRetry", o2) == 1 {
    call_contract("AttemptOutcome", result, ok3, 3, req.max_attempts)
  } else {
    o2
  }
  output o3 : JobOutcome
}

-- ── Receipt ─────────────────────────────────────────────────
pure contract OutcomeStatus {
  input o : JobOutcome
  compute s : String = match o {
    Done {}       => "done"
    Retry {}      => "retrying"
    Exhausted {}  => "exhausted"
    DeadLetter {} => "dead_letter"
  }
  output s : String
}

pure contract OutcomeResult {
  input o : JobOutcome
  compute r : Integer = match o {
    Done  { result } => result
    Retry { result } => result
    Exhausted {}     => 0
    DeadLetter {}    => 0
  }
  output r : Integer
}

pure contract OutcomeAttempts {
  input o : JobOutcome
  compute n : Integer = match o {
    Done      { attempts } => attempts
    Retry {}               => 0
    Exhausted { attempts } => attempts
    DeadLetter {}          => 0
  }
  output n : Integer
}

pure contract BuildReceipt {
  input job_id : String
  input o : JobOutcome
  compute status = call_contract("OutcomeStatus", o)
  compute result = call_contract("OutcomeResult", o)
  compute attempts = call_contract("OutcomeAttempts", o)
  compute receipt = {
    job_id: job_id,
    status: status,
    result: result,
    attempts: attempts
  }
  output receipt : JobReceipt
}
