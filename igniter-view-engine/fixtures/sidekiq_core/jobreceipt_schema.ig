module Sidekiq.Lab.JobReceipt

-- JobReceipt schema fixture — LAB-SIDEKIQ-P4
--
-- Proves: a Sidekiq-like job execution surface can return a structured
-- single-output JobReceipt record using P13 nominal record typechecking,
-- replacing raw Integer retry/job outputs with a typed receipt.
--
-- Mechanisms used:
--   P13 check_record_literal_shape   — validates RecordLiteral against JobReceipt fields
--   P11 build_contract_registry      — Tier 1 literal callee resolves to JobReceipt
--   P11 Tier 2 dynamic callee        — stays Unknown (no upgrade without literal)
--   P13 output_type_hints pre-scan   — maps receipt compute → JobReceipt hint
--
-- Authority: lab-only — no Redis, no worker daemon, no scheduler,
-- no ServiceLoop, no Sidekiq compatibility claim, no public API stability.
-- TypeChecker/SemanticIR proof only; VM record construction is deferred to P14.

-- ── JobReceipt: structured 5-field receipt schema ─────────────────────────────
-- Replaces raw Integer retry/job output with a named record type.
--
-- Fields:
--   job_class        : String   — name of the dispatched job contract
--   job_id           : String   — caller-supplied identifier
--   attempt          : Integer  — attempt counter (from RetryPolicy context)
--   budget_remaining : Integer  — retries remaining = max_attempts - attempt
--   status           : String   — vocabulary in P4: "ok" | "exhausted" | "failed"
--
-- No timestamps, no duration, no retry_at, no scheduled_at, no queue id.
-- No error object or stack trace. No effect receipts.
-- `status` is a String vocabulary; enum/status type system is deferred.
type JobReceipt {
  job_class        : String,
  job_id           : String,
  attempt          : Integer,
  budget_remaining : Integer,
  status           : String
}

-- ── ReceiptJob: minimal pure job that outputs a JobReceipt ────────────────────
-- Proves: P13 check_record_literal_shape validates all 5 JobReceipt fields and
-- upgrades the receipt compute node from Unknown to JobReceipt.
--
-- P11 Tier 1 note: ReceiptJob is the named literal target for ReceiptDispatcher.
-- When `call_contract("ReceiptJob", ...)` is resolved, P11 registry lookup returns
-- single_output_type = JobReceipt, and the dispatcher's receipt node is JobReceipt.
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

-- ── ReceiptDispatcher: literal callee → P11 Tier 1 resolves to JobReceipt ─────
-- Proves: P11 Tier 1 resolves `call_contract("ReceiptJob", ...)` to JobReceipt
-- at compile time (TypeChecker registry lookup of ReceiptJob's single_output_type).
-- The receipt compute node is typed JobReceipt without a RecordLiteral in this contract.
pure contract ReceiptDispatcher {
  input  job_class        : String
  input  job_id           : String
  input  attempt          : Integer
  input  max_attempts     : Integer
  compute receipt = call_contract("ReceiptJob", job_class, job_id, attempt, max_attempts)
  output receipt : JobReceipt
}

-- ── DynamicReceiptDispatcher: variable callee → P11 Tier 2 stays Unknown ──────
-- Proves: P11 Tier 2 dynamic callee leaves the receipt compute node as Unknown.
-- P13 does NOT upgrade call_contract nodes (only RecordLiteral nodes).
-- The output annotation `receipt : JobReceipt` is Unknown-compat — no compile error.
pure contract DynamicReceiptDispatcher {
  input  handler_name     : String
  input  job_class        : String
  input  job_id           : String
  input  attempt          : Integer
  input  max_attempts     : Integer
  compute receipt = call_contract(handler_name, job_class, job_id, attempt, max_attempts)
  output receipt : JobReceipt
}
