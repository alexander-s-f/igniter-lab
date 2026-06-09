module Lab.Validation.ThirdDomain

-- LAB-RESULT-ENVELOPE-P2: Third-domain kind-discriminant pressure proof.
-- Domain: Form validation and submission processing.
--
-- Proves the kind-discriminant envelope pattern in a domain orthogonal to:
--   HTTP/Rack   -- no HTTP status codes, no integer status field
--   Sidekiq     -- no attempt/retry budget, no job_class/job_id fields
--
-- ValidationResult: a four-kind domain envelope.
--   "valid"        -- submission passed all constraints (happy path)
--   "invalid"      -- field-level constraint violated (user input error)
--   "unauthorized" -- submission not permitted (denial-as-data, non-HTTP form)
--   "system_error" -- constraint evaluation failed (infrastructure error, not user error)
--
-- Metadata: Map[String, String] for field context (rule, expected, field_name, etc.)
-- No HTTP status codes. No retry budget. No job identity fields.
--
-- Types mirror P9 ContractResult shape at the design level but use domain vocabulary:
--   ContractResult.data      → ValidationResult.field  (domain identifier, not payload)
--   ContractResult.message   → ValidationResult.message (same name, same role)
--   HttpResult.kind          → ValidationResult.kind (same pattern, different value space)
--
-- Authority: LAB-ONLY. No canon claim. No framework compat. No public API.
-- Depends: PROP-043-P5 (Map[String,String]), LAB-VM-MAP-P1 (map_get VM runtime).

-- ── Types ──────────────────────────────────────────────────────────────────────

type ValidationResult {
  field:    String,
  kind:     String,
  message:  String,
  metadata: Map[String, String]
}

type SubmissionOutcome {
  action:  String,
  summary: String
}

-- ── Kind: "valid" ─────────────────────────────────────────────────────────────
-- Happy path. All constraints satisfied. Field is empty (no failure site).
-- Metadata carries ambient context (source, form id, etc.).

pure contract ValidSubmission {
  input  name    : String
  input  email   : String
  input  context : Map[String, String]
  compute result = { field: "", kind: "valid", message: "submission accepted", metadata: context }
  output  result : ValidationResult
}

-- ── Kind: "invalid" — required field ─────────────────────────────────────────
-- Required field is missing or empty. Field names the failing input.
-- The domain consumer decides what to show the user; this contract is pure data.

pure contract InvalidRequired {
  input  field_name : String
  input  metadata   : Map[String, String]
  compute result    = { field: field_name, kind: "invalid", message: "required field missing", metadata: metadata }
  output  result    : ValidationResult
}

-- ── Kind: "invalid" — format constraint ──────────────────────────────────────
-- Field value does not match a format constraint (email, phone, date, etc.).
-- The 'rule' key in metadata identifies which constraint fired.

pure contract InvalidFormat {
  input  field_name : String
  input  metadata   : Map[String, String]
  compute result    = { field: field_name, kind: "invalid", message: "field value fails format constraint", metadata: metadata }
  output  result    : ValidationResult
}

-- ── Kind: "unauthorized" ──────────────────────────────────────────────────────
-- Submission is not permitted (capability denied equivalent for a form domain).
-- Denial-as-data: no exception raised; consumer handles it as a typed branch.
-- Deterministic: retrying will not change this outcome.
-- No HTTP status code. No job fields. Pure domain semantics.

pure contract UnauthorizedSubmission {
  input  reason   : String
  input  metadata : Map[String, String]
  compute result  = { field: "", kind: "unauthorized", message: reason, metadata: metadata }
  output  result  : ValidationResult
}

-- ── Kind: "system_error" ──────────────────────────────────────────────────────
-- Constraint evaluation machinery failed. Not a user error.
-- Equivalent to upstream_error / system_error in other domains (infrastructure fault).
-- Consumer should not ask user to retry input changes; the error is not their fault.

pure contract SystemError {
  input  error_detail : String
  input  metadata     : Map[String, String]
  compute result      = { field: "", kind: "system_error", message: error_detail, metadata: metadata }
  output  result      : ValidationResult
}

-- ── Map metadata extraction (VM layer proof) ──────────────────────────────────
-- Proves: map_get(vr.metadata, key) → Option[String] + or_else → String
-- over a ValidationResult named-record input in the third domain.
-- Mirrors the MetadataReader (Sidekiq P5) and HeaderChain (VM-MAP-P1) patterns
-- but for the validation domain (orthogonal to HTTP and job processing).

pure contract MetadataInspector {
  input  vr         : ValidationResult
  compute rule_opt  = map_get(vr.metadata, "rule")
  compute rule_name = or_else(rule_opt, "unknown_rule")
  compute field_opt = map_get(vr.metadata, "field_name")
  compute field_ctx = or_else(field_opt, "no_field")
  output  rule_name : String
}

-- ── Low-level → domain mapper ─────────────────────────────────────────────────
-- Strips raw boundary detail; domain consumer sees only kind + domain-safe fields.
-- Proves the three-layer composition pattern (mapper role) in a validation context.
-- map_get(context, "message") retrieves a message from the raw context Map, then
-- or_else provides a default if absent — same chain as Rack P14 HeadersAwareHandler.

pure contract ValidationMapper {
  input  raw_kind  : String
  input  raw_field : String
  input  context   : Map[String, String]
  compute msg      = or_else(map_get(context, "message"), "validation processed")
  compute result   = { field: raw_field, kind: raw_kind, message: msg, metadata: context }
  output  result   : ValidationResult
}
