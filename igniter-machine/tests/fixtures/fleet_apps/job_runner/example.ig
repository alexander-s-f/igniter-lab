module JobRunnerExample
import JobRunnerTypes
import JobRunnerEngine

-- ============================================================
-- Example: dispatch jobs and exercise the retry budget
-- ============================================================

pure contract MakeReq {
  input job_class : String
  input arg1 : Integer
  input arg2 : Integer
  compute r = { job_class: job_class, job_id: "job-001", arg1: arg1, arg2: arg2, max_attempts: 3 }
  output r : JobRequest
}

-- succeeds on the first attempt → Done { attempts: 1 }
contract RunSuccessFirst {
  compute req = call_contract("MakeReq", "process_order", 40, 2)
  compute outcome = call_contract("RunWithRetry3", req, 1, 0, 0)
  output outcome : JobOutcome
}

-- fails attempt 1, succeeds attempt 2 → Done { attempts: 2 }
contract RunSuccessSecond {
  compute req = call_contract("MakeReq", "compute_report", 7, 0)
  compute outcome = call_contract("RunWithRetry3", req, 0, 1, 0)
  output outcome : JobOutcome
}

-- never succeeds within the budget → Exhausted
contract RunExhausted {
  compute req = call_contract("MakeReq", "validate_payment", 100, 5)
  compute outcome = call_contract("RunWithRetry3", req, 0, 0, 0)
  output outcome : JobOutcome
}

-- unknown job class → DeadLetter
contract RunDeadLetter {
  compute req = call_contract("MakeReq", "ghost_job", 1, 1)
  compute outcome = call_contract("RunWithRetry3", req, 0, 0, 0)
  output outcome : JobOutcome
}

-- full path → a JobReceipt
contract RunReceipt {
  compute req = call_contract("MakeReq", "process_order", 40, 2)
  compute outcome = call_contract("RunWithRetry3", req, 0, 1, 0)
  compute receipt = call_contract("BuildReceipt", req.job_id, outcome)
  output receipt : JobReceipt
}

entrypoint RunSuccessSecond
