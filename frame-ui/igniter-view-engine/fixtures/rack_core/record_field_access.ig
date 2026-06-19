module RecordFieldAccess

-- LAB-RECORD-VM-P2: Dispatched Record Field Access
--
-- Proves that a record value produced by one contract via call_contract can be
-- consumed by another contract through static field access expressions.
--
-- Pressure families: RackResponse (P13) and JobReceipt (P4).
-- Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim.
-- No canon grammar change. call_contract is lab-only.

type RackResponse {
  body   : String,
  status : Integer
}

type JobReceipt {
  attempt          : Integer,
  budget_remaining : Integer,
  job_class        : String,
  job_id           : String,
  status           : String
}

-- RackResponse contracts

pure contract OkHandler {
  input  method : String
  input  path   : String
  compute body_val   = "OK"
  compute status_val = 200
  compute response = {
    body:   body_val,
    status: status_val
  }
  output response : RackResponse
}

pure contract RackStatusReader {
  input  method : String
  input  path   : String
  compute response   = call_contract("OkHandler", method, path)
  compute status_out = response.status
  output status_out : Integer
}

pure contract RackBodyReader {
  input  method : String
  input  path   : String
  compute response = call_contract("OkHandler", method, path)
  compute body_out = response.body
  output body_out : String
}

-- JobReceipt contracts

pure contract ReceiptJob {
  input  job_class        : String
  input  job_id           : String
  input  attempt          : Integer
  input  max_attempts     : Integer
  compute budget_remaining = max_attempts - attempt
  compute status_val       = "ok"
  compute receipt = {
    job_class:        job_class,
    job_id:           job_id,
    attempt:          attempt,
    budget_remaining: budget_remaining,
    status:           status_val
  }
  output receipt : JobReceipt
}

pure contract FieldStatusReader {
  input  job_class    : String
  input  job_id       : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute receipt    = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  compute status_out = receipt.status
  output status_out : String
}

pure contract FieldBudgetReader {
  input  job_class    : String
  input  job_id       : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute receipt    = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  compute budget_out = receipt.budget_remaining
  output budget_out : Integer
}

pure contract FieldJobClassReader {
  input  job_class    : String
  input  job_id       : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute receipt       = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  compute job_class_out = receipt.job_class
  output job_class_out : String
}

pure contract FieldComputeOnField {
  input  job_class    : String
  input  job_id       : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute receipt  = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  compute budget   = receipt.budget_remaining
  compute doubled  = budget + budget
  output doubled : Integer
}
