module NestedRecordFieldValues

-- LAB-RECORD-VM-P3: Nested Record Field Values
--
-- Proves that a record field can hold another record, and that chained field
-- access expressions like outer.inner.field work end-to-end through
-- typechecking, SemanticIR, bytecode compilation, and VM execution.
--
-- Pressure families:
--   Rack  — ResponseEnvelope { headers: HeaderInfo, ... }
--   Sidekiq — JobEnvelope { meta: JobMeta, ... }
--
-- Implementation finding: one targeted compiler.rs change.
--   P3 adds no new opcodes. OP_GET_FIELD (0x22, from P2) is reused.
--   The only fix: replace Err("Unsupported object type...") in the
--   "field_access" compiler branch with self.compile_expr(object) + OP_GET_FIELD.
--   Handles: envelope.headers.content_type, envelope.meta.priority, etc.
--
-- Lab-only. No Rack compatibility claim. No Sidekiq compatibility claim.
-- No canon grammar change. call_contract is lab-only.

-- ── Rack pressure types ───────────────────────────────────────────────────────

type HeaderInfo {
  cache_control : String,
  content_type  : String
}

type ResponseEnvelope {
  body    : String,
  headers : HeaderInfo,
  status  : Integer
}

-- ── Sidekiq pressure types ────────────────────────────────────────────────────

type JobMeta {
  priority : Integer,
  queue    : String
}

type JobEnvelope {
  budget_remaining : Integer,
  job_class        : String,
  meta             : JobMeta,
  status           : String
}

-- ── Rack contracts ────────────────────────────────────────────────────────────

-- Constructs a ResponseEnvelope with a nested HeaderInfo field.
-- Verifies that VM can build and return a nested record value.
pure contract EnvelopeBuilder {
  input  method : String
  compute headers = {
    cache_control: "no-cache",
    content_type:  "text/plain"
  }
  compute envelope = {
    body:    "OK",
    headers: headers,
    status:  200
  }
  output envelope : ResponseEnvelope
}

-- Reads envelope.headers.content_type via chained field access.
-- Tier 1 dispatch: envelope resolves to ResponseEnvelope;
-- typechecker chains through to HeaderInfo.content_type = String.
pure contract ContentTypeReader {
  input  method : String
  compute envelope     = call_contract("EnvelopeBuilder", method)
  compute content_type = envelope.headers.content_type
  output content_type : String
}

-- Reads envelope.headers.cache_control via chained field access.
-- Same chain as ContentTypeReader; different field extracted.
pure contract CacheControlReader {
  input  method : String
  compute envelope      = call_contract("EnvelopeBuilder", method)
  compute cache_control = envelope.headers.cache_control
  output cache_control : String
}

-- ── Sidekiq contracts ─────────────────────────────────────────────────────────

-- Constructs a JobEnvelope with a nested JobMeta field.
-- budget_remaining computed from inputs (arithmetic before record construction).
pure contract JobEnvelopeBuilder {
  input  job_class    : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute budget_remaining = max_attempts - attempt
  compute meta = {
    priority: 5,
    queue:    "default"
  }
  compute envelope = {
    budget_remaining: budget_remaining,
    job_class:        job_class,
    meta:             meta,
    status:           "ok"
  }
  output envelope : JobEnvelope
}

-- Reads envelope.meta.priority via chained field access.
-- Tier 1 dispatch: envelope resolves to JobEnvelope;
-- typechecker chains through to JobMeta.priority = Integer.
pure contract PriorityReader {
  input  job_class    : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute envelope = call_contract("JobEnvelopeBuilder", job_class, attempt, max_attempts)
  compute priority = envelope.meta.priority
  output priority : Integer
}

-- Reads envelope.meta.queue via chained field access.
-- Same chain as PriorityReader; extracts String field.
pure contract QueueReader {
  input  job_class    : String
  input  attempt      : Integer
  input  max_attempts : Integer
  compute envelope = call_contract("JobEnvelopeBuilder", job_class, attempt, max_attempts)
  compute queue    = envelope.meta.queue
  output queue : String
}
