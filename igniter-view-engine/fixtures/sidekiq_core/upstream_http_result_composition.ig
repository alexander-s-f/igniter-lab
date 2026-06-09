-- LAB-SIDEKIQ-P5: Sidekiq upstream composition with Map[String,String] metadata.
--
-- Proves a Sidekiq-shaped job that consumes typed HttpResult / ContractResult
-- envelopes, applies retry policy as explicit data (BudgetedLocalLoop analog),
-- and returns a typed JobReceipt or RetryEnvelope with Map[String,String] metadata.
--
-- Depends on: PROP-043-P5 C1 fix (preserves Map params through @type_shapes),
--             LAB-SIDEKIQ-P4 (5-field JobReceipt baseline), LAB-STDLIB-NET-P8/P9
--             (HttpResult / ContractResult envelope shapes).
--
-- P5 extension of JobReceipt: adds metadata : Map[String, String] field.
-- New type: RetryEnvelope with metadata and next_attempt.
-- New type: JobInput with metadata for structured job input.
--
-- Authority: LAB-ONLY. No canon claim. No public API surface. No runtime.
module Sidekiq.Lab.UpstreamComposition

-- HttpResult: typed result from a mocked upstream HTTP dispatch.
-- kind discriminant: "ok" / "denied" / "error" (from LAB-STDLIB-NET-P8).
type HttpResult {
  body:       String,
  error_code: String,
  kind:       String,
  status:     Integer
}

-- ContractResult: typed domain-level output from the composition layer.
-- kind discriminant: "found" / "created" / "not_found" / "upstream_error" /
--                    "capability_denied" / "upstream_unavailable" (from LAB-STDLIB-NET-P9).
type ContractResult {
  data:       String,
  error_code: String,
  kind:       String,
  message:    String
}

-- JobInput: structured Sidekiq job input with Map[String,String] metadata.
-- metadata holds job-level key/value annotations (queue, worker, timeout_ms, etc.).
type JobInput {
  attempt:      Integer,
  job_class:    String,
  job_id:       String,
  max_attempts: Integer,
  metadata:     Map[String, String],
  payload:      String
}

-- JobReceipt: typed job outcome with Map[String,String] metadata passthrough.
-- P5 extension of P4 JobReceipt: adds message and metadata fields.
-- status values: "ok" / "non_retryable" / "upstream_unavailable".
type JobReceipt {
  attempt:      Integer,
  job_class:    String,
  job_id:       String,
  max_attempts: Integer,
  message:      String,
  metadata:     Map[String, String],
  status:       String
}

-- RetryEnvelope: typed retry state for retryable job failures.
-- next_attempt = attempt + 1 (explicit arithmetic, no scheduler).
-- reason holds the ContractResult.error_code for the failed attempt.
type RetryEnvelope {
  attempt:      Integer,
  job_class:    String,
  job_id:       String,
  max_attempts: Integer,
  metadata:     Map[String, String],
  next_attempt: Integer,
  reason:       String
}

-- SJOB5-MAP: Metadata lookup chain.
-- Proves: map_get(job.metadata, key) -> Option[String] via named Record field access.
-- The C1 fix ensures @type_shapes["JobInput"]["metadata"] = Map[String,String] (not Map).
-- Without C1: map_get(job.metadata, key) -> Option[Unknown].
-- With C1:    map_get(job.metadata, key) -> Option[String].
-- or_else(Option[String], default) -> String (infer_or_else extracts V from params[0]).
pure contract MetadataReader {
  input  job:     JobInput
  compute worker  = map_get(job.metadata, "worker")
  compute queue   = or_else(map_get(job.metadata, "queue"), "default")
  compute timeout = map_get(job.metadata, "timeout_ms")
  output  queue:  String
}

-- SJOB5-SUCCESS: Upstream found/created -> ok JobReceipt.
-- Proves: a job contract that receives a successful ContractResult builds a
-- typed JobReceipt with Map[String,String] metadata passthrough.
-- receipt type resolved by @output_type_hints["receipt"] = JobReceipt via C1.
pure contract SuccessPath {
  input  job:    JobInput
  input  result: ContractResult
  compute queue   = or_else(map_get(job.metadata, "queue"), "default")
  compute receipt = { attempt: job.attempt, job_class: job.job_class, job_id: job.job_id, max_attempts: job.max_attempts, message: result.data, metadata: job.metadata, status: "ok" }
  output receipt: JobReceipt
}

-- SJOB5-DENIED: capability_denied -> non-retryable JobReceipt.
-- Proves: a job contract that receives a capability_denied ContractResult builds
-- a non-retryable JobReceipt (status = "non_retryable").
-- Capability denial is deterministic: retrying changes nothing.
pure contract DeniedPath {
  input  job:    JobInput
  input  result: ContractResult
  compute receipt = { attempt: job.attempt, job_class: job.job_class, job_id: job.job_id, max_attempts: job.max_attempts, message: result.error_code, metadata: job.metadata, status: "non_retryable" }
  output receipt: JobReceipt
}

-- SJOB5-RETRY: upstream_error within budget -> RetryEnvelope.
-- Proves: a job contract receiving a retriable upstream error returns a typed
-- RetryEnvelope (next_attempt = attempt + 1) with metadata passthrough.
-- Only reachable when attempt < max_attempts (budget not exhausted).
-- next_attempt = job.attempt + 1: field_access Integer + literal Integer -> Integer.
pure contract RetryablePath {
  input  job:          JobInput
  input  result:       ContractResult
  compute next_attempt = job.attempt + 1
  compute envelope     = { attempt: job.attempt, job_class: job.job_class, job_id: job.job_id, max_attempts: job.max_attempts, metadata: job.metadata, next_attempt: next_attempt, reason: result.error_code }
  output envelope: RetryEnvelope
}

-- SJOB5-EXHAUSTED: budget exhausted -> dead-letter JobReceipt.
-- Proves: a job contract that has exhausted its retry budget returns a
-- dead-letter JobReceipt (status = "upstream_unavailable").
-- upstream_unavailable is ONLY reachable when attempt >= max_attempts.
pure contract ExhaustedPath {
  input  job:    JobInput
  input  result: ContractResult
  compute receipt = { attempt: job.attempt, job_class: job.job_class, job_id: job.job_id, max_attempts: job.max_attempts, message: result.error_code, metadata: job.metadata, status: "upstream_unavailable" }
  output receipt: JobReceipt
}
