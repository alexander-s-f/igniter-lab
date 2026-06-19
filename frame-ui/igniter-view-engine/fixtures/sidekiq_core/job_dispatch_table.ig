module Sidekiq.Lab.JobDispatch

-- Static job dispatch table — LAB-SIDEKIQ-P2
--
-- Proves: call_contract dispatches to named job contracts by job_class string,
-- enforcing arity, fail-closed on unknown job class, and cycle detection.
--
-- All job contracts share the same arity:
--   (job_id: String, arg1: Integer, arg2: Integer) → result: Integer
-- so that JobDispatcher can route uniformly via positional mapping.
--
-- Authority: lab-only — no Redis, no worker daemon, no scheduler,
-- no ServiceLoop, no Sidekiq compatibility claim, no stable API.

-- ── Job contracts (callees) ───────────────────────────────────────────────────

-- ProcessOrderJob: order_id + order_id (stub: doubles the order value)
-- Proves: Integer-output pure job dispatched by class name
pure contract ProcessOrderJob {
  input  job_id    : String
  input  order_id  : Integer
  input  attempt   : Integer
  compute result   = order_id + order_id
  output result    : Integer
}

-- ComputeReportJob: period * 10 (stub: period in some unit times 10)
-- Proves: named-variant dispatch by job_class string (different name, same arity)
pure contract ComputeReportJob {
  input  job_id  : String
  input  period  : Integer
  input  code    : Integer
  compute result = period * 10
  output result  : Integer
}

-- ValidatePaymentJob: amount + attempt (stub: validation score)
-- Proves: two-integer-arg dispatch; numeric accumulation
pure contract ValidatePaymentJob {
  input  job_id   : String
  input  amount   : Integer
  input  attempt  : Integer
  compute result  = amount + attempt
  output result   : Integer
}

-- ── Dispatcher contract ───────────────────────────────────────────────────────

-- JobDispatcher: routes by job_class string to the named job contract.
--
-- Uses call_contract (LAB-RACK-P9 mechanism) for named dispatch.
-- Positional mapping: (job_id, arg1, arg2) → callee (job_id, input2, input3)
-- All job contracts share arity 3 so dispatch is uniform.
--
-- Fail-closed:
--   unknown job_class → "no contract named 'X' in igapp (available: [...])"
--   arity mismatch    → "contract 'X' expects N input(s), got M"
--   effect callee     → "callee 'X' is not pure (modifier: effect)"
--   cycle             → "dispatch cycle detected"
--   depth > 8         → "max call depth (8) exceeded"
pure contract JobDispatcher {
  input  job_class : String
  input  job_id    : String
  input  arg1      : Integer
  input  arg2      : Integer
  compute result   = call_contract(job_class, job_id, arg1, arg2)
  output result    : Integer
}

-- NOTE (2026-06-09, LAB-SIDEKIQ-P3 fix):
-- SelfDispatch was removed from this fixture.
-- With the P10 TypeChecker (literal callee static resolution), a contract that calls
-- call_contract("SelfDispatch", ...) from within SelfDispatch triggers OOF-TY0 at
-- COMPILE TIME, not at VM runtime. This causes the whole igapp to fail to compile.
-- Self-dispatch cycle detection is verified via a separate inline fixture in
-- verify_sidekiq_p2_job_dispatch.rb (SELF_DISPATCH_SRC / SELF_RESULT).
