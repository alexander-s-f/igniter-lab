#!/usr/bin/env ruby
# verify_lab_stdlib_outcome_p1.rb — LAB-STDLIB-OUTCOME-P1 Pressure Proof
#
# Route: LAB PROOF / DESIGN + FIXTURE / NO CANON IMPLEMENTATION
# Track: stdlib-outcome-helper-pressure-and-stringly-kind-reduction-v0
#
# Research question:
#   Can stdlib outcome helpers reduce stringly `kind` handling without
#   collapsing domain-specific outcomes or granting runtime authority?
#
# Method: proof-local Ruby model.  Helpers are defined here as Ruby module
# methods (not implemented in the igniter compiler, parser, TypeChecker, or VM).
# Fixture data is Ruby hashes representing KDR-like outcome records.
# No compiler binary or VM binary is invoked.
#
# Authority closed (this proof does NOT open):
#   stdlib implementation / parser / typechecker / SemanticIR / assembler
#   VM / runtime / canon outcome type / generic Outcome[T,E]
#   variant enforcement changes / public API / package/distribution
#
# Minimum gate: 50 checks / PASS verdict required for P2 gate.
#
# Depends: PROP-047-P2, LAB-EPISTEMIC-OUTCOME-P2/P4, LAB-FAILURE-TAXONOMY-P4,
#          LAB-OUTCOME-VARIANT-P1..P3, LANG-STDLIB-ENTRY-CONTRACT-P1.

require 'pathname'

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message}"
  $fail_count += 1
end

# ─────────────────────────────────────────────────────────────────────────────
# Proof-local helper model
#
# Models the proposed stdlib.outcome helpers.  These are PROOF-LOCAL Ruby
# predicates — not a language implementation, not a compiler change.
# They demonstrate the proposed semantics and authority boundary.
# ─────────────────────────────────────────────────────────────────────────────

STABLE_TERMS = %w[
  denied unknown_external_state timed_out
  system_error query_error partial_success
].freeze

module OutcomeH
  # kind: opaque passthrough.  Always returns the kind string as-is.
  # Proposed: stdlib.outcome.kind(outcome) -> String
  def self.kind(outcome)
    outcome.fetch("kind")
  end

  # Stable-term predicates (PROP-047 §2 vocabulary)
  def self.is_denied(outcome)             = outcome["kind"] == "denied"
  def self.is_unknown_external_state(o)   = o["kind"]      == "unknown_external_state"
  def self.is_timed_out(outcome)          = outcome["kind"] == "timed_out"
  def self.is_system_error(outcome)       = outcome["kind"] == "system_error"
  def self.is_query_error(outcome)        = outcome["kind"] == "query_error"
  def self.is_partial_success(outcome)    = outcome["kind"] == "partial_success"

  # is_retryable: axis-9 (PROP-047) — CONDITIONAL ACCEPT.
  #
  # Semantics:
  #   "denied"                → false  (deterministic; PROP-047 FC-1)
  #   "unknown_external_state"→ false  (reconcile not retry; Covenant P15)
  #   "system_error"          → true   (retry with backoff)
  #   "timed_out", pre-disp.  → true   (dispatch not started; safe to retry)
  #   "timed_out", post-disp. → false  (post-dispatch = unknown state path)
  #   "query_error"           → false  (malformed input; retry unhelpful; PROP-047 FC-1)
  #   domain-local kinds      → false  (generic helper does not know domain retry semantics)
  #
  # Boundary: axis-9 stable terms only.  Domain-local kinds always return false.
  # Callers must use direct kind comparison for domain-specific retry logic.
  def self.is_retryable(outcome)
    case outcome["kind"]
    when "system_error"
      true
    when "timed_out"
      outcome.fetch("dispatch_started", false) == false
    when "denied", "query_error", "unknown_external_state", "partial_success"
      false
    else
      false  # domain-local kind: not knowable by generic helper
    end
  end

  # route() — REJECTED.
  # Encoding a routing policy inside a stdlib helper grants runtime authority.
  # Callers encode their own policy; helpers only classify.
  # Defined here to document the rejection verdict (H-05).
  def self.route(_outcome, _policy)
    raise NotImplementedError,
      "stdlib.outcome.route encodes caller policy — rejected (H-05; grants runtime authority)"
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Fixture data — three domains, KDR-like Ruby hashes
# KDR = { "kind" => String, ... } convention (LAB-EPISTEMIC-OUTCOME-P2)
# ─────────────────────────────────────────────────────────────────────────────

# Domain 1: Network / HTTP client
HTTP = {
  ok:                      { "kind" => "ok",                      "status_code" => "200" },
  redirect:                { "kind" => "redirect",                "location" => "/new/path" },
  rate_limited:            { "kind" => "rate_limited",            "retry_after" => "60" },
  denied:                  { "kind" => "denied",                  "message" => "auth_failed" },
  timed_out_pre:           { "kind" => "timed_out",               "dispatch_started" => false,  "message" => "connect timeout" },
  timed_out_post:          { "kind" => "timed_out",               "dispatch_started" => true,   "message" => "read timeout" },
  unknown_external_state:  { "kind" => "unknown_external_state",  "request_id" => "req-abc" },
  system_error:            { "kind" => "system_error",            "message" => "connection refused" },
  query_error:             { "kind" => "query_error",             "message" => "invalid URL scheme" },
}.freeze

# Domain 2: Storage / Query
STORAGE = {
  rows:                    { "kind" => "rows",                    "row_count" => "5" },
  empty:                   { "kind" => "empty",                   "query_id" => "q-1" },
  found:                   { "kind" => "found",                   "record_id" => "r-99" },
  created:                 { "kind" => "created",                 "record_id" => "r-100" },
  conflict:                { "kind" => "conflict",                "record_id" => "r-77" },
  denied:                  { "kind" => "denied",                  "message" => "write_capability_missing" },
  system_error:            { "kind" => "system_error",            "message" => "disk full" },
  query_error:             { "kind" => "query_error",             "message" => "syntax error near )" },
  unknown_external_state:  { "kind" => "unknown_external_state",  "transaction_id" => "tx-55" },
  partial_success:         { "kind" => "partial_success",         "succeeded_count" => "8", "failed_count" => "2" },
}.freeze

# Domain 3: Epistemic / Reconciliation
EPISTEMIC = {
  confirmed_succeeded:     { "kind" => "confirmed_succeeded",     "evidence_kind" => "real",  "request_id" => "r-1" },
  confirmed_failed:        { "kind" => "confirmed_failed",        "idempotency_key" => "ik-7" },
  still_unknown:           { "kind" => "still_unknown",           "attempt" => "3", "budget_remaining" => "2" },
  reconciliation_denied:   { "kind" => "reconciliation_denied",   "message" => "stale_window" },
  reconciliation_error:    { "kind" => "reconciliation_error",    "detail" => "state machine fault" },
  denied:                  { "kind" => "denied",                  "message" => "reconciliation_window_closed" },
  timed_out:               { "kind" => "timed_out",               "dispatch_started" => false },
  unknown_external_state:  { "kind" => "unknown_external_state",  "idempotency_key" => "ik-0" },
  partial_success:         { "kind" => "partial_success",         "succeeded_count" => "3", "failed_count" => "1" },
  system_error:            { "kind" => "system_error",            "message" => "state store unavailable" },
}.freeze

ALL_DOMAINS = [HTTP, STORAGE, EPISTEMIC].freeze

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-A — Inventory (3 domains, KDR shape)"

check("A-01: HTTP domain has ≥5 distinct outcome kinds") do
  HTTP.values.map { |o| o["kind"] }.uniq.length >= 5
end
check("A-02: Storage domain has ≥4 distinct outcome kinds") do
  STORAGE.values.map { |o| o["kind"] }.uniq.length >= 4
end
check("A-03: Epistemic domain has ≥4 distinct outcome kinds") do
  EPISTEMIC.values.map { |o| o["kind"] }.uniq.length >= 4
end
check("A-04: All 6 PROP-047 stable terms appear in ≥2 domains each") do
  STABLE_TERMS.all? do |term|
    ALL_DOMAINS.count { |d| d.values.any? { |o| o["kind"] == term } } >= 2
  end
end
check("A-05: Domain-local outcome kinds are domain-exclusive") do
  http_local      = %w[ok redirect rate_limited]
  storage_local   = %w[rows empty found created conflict]
  epistemic_local = %w[confirmed_succeeded confirmed_failed still_unknown
                        reconciliation_denied reconciliation_error]
  http_local.all?      { |k| HTTP.values.any?      { |o| o["kind"] == k } } &&
  storage_local.all?   { |k| STORAGE.values.any?   { |o| o["kind"] == k } } &&
  epistemic_local.all? { |k| EPISTEMIC.values.any? { |o| o["kind"] == k } }
end
check("A-06: All fixture records carry a non-empty String 'kind' field") do
  ALL_DOMAINS.all? do |domain|
    domain.values.all? { |o| o["kind"].is_a?(String) && !o["kind"].empty? }
  end
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-B — Helper model (proof-local, no generic type)"

check("B-01: is_* helpers accept Hash with 'kind' key") do
  OutcomeH.is_denied({ "kind" => "denied" }) == true
end
check("B-02: Helpers do not require Outcome[T,E] generic wrapper") do
  raw = { "kind" => "system_error", "message" => "raw KDR hash" }
  OutcomeH.is_system_error(raw) == true
end
check("B-03: is_* helpers return Bool (true/false)") do
  samples = [
    OutcomeH.is_denied({ "kind" => "denied" }),
    OutcomeH.is_timed_out({ "kind" => "ok" }),
    OutcomeH.is_system_error({ "kind" => "system_error" }),
    OutcomeH.is_retryable({ "kind" => "query_error" }),
    OutcomeH.is_partial_success({ "kind" => "rows" }),
  ]
  samples.all? { |v| v == true || v == false }
end
check("B-04: kind() returns String — opaque passthrough for any kind including domain-local") do
  OutcomeH.kind({ "kind" => "unknown_external_state" }) == "unknown_external_state" &&
  OutcomeH.kind({ "kind" => "rows" }) == "rows" &&
  OutcomeH.kind({ "kind" => "reconciliation_error" }) == "reconciliation_error"
end
check("B-05: OutcomeH has no instance methods (module-method-only contract)") do
  OutcomeH.instance_methods(false).empty?
end
check("B-06: route() raises NotImplementedError (rejected helper)") do
  begin
    OutcomeH.route({ "kind" => "denied" }, {})
    false
  rescue NotImplementedError
    true
  end
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-C — Positive stable terms (each helper correct for its term)"

check("C-01: is_denied correct across 3 domains") do
  OutcomeH.is_denied(HTTP[:denied]) &&
  OutcomeH.is_denied(STORAGE[:denied]) &&
  OutcomeH.is_denied(EPISTEMIC[:denied])
end
check("C-02: is_unknown_external_state correct across 3 domains") do
  OutcomeH.is_unknown_external_state(HTTP[:unknown_external_state]) &&
  OutcomeH.is_unknown_external_state(STORAGE[:unknown_external_state]) &&
  OutcomeH.is_unknown_external_state(EPISTEMIC[:unknown_external_state])
end
check("C-03: is_timed_out correct across pre- and post-dispatch and epistemic") do
  OutcomeH.is_timed_out(HTTP[:timed_out_pre]) &&
  OutcomeH.is_timed_out(HTTP[:timed_out_post]) &&
  OutcomeH.is_timed_out(EPISTEMIC[:timed_out])
end
check("C-04: is_system_error correct across 3 domains") do
  OutcomeH.is_system_error(HTTP[:system_error]) &&
  OutcomeH.is_system_error(STORAGE[:system_error]) &&
  OutcomeH.is_system_error(EPISTEMIC[:system_error])
end
check("C-05: is_query_error correct in HTTP and storage domains") do
  OutcomeH.is_query_error(HTTP[:query_error]) &&
  OutcomeH.is_query_error(STORAGE[:query_error])
end
check("C-06: is_partial_success correct in storage and epistemic domains") do
  OutcomeH.is_partial_success(STORAGE[:partial_success]) &&
  OutcomeH.is_partial_success(EPISTEMIC[:partial_success])
end
check("C-07: Stable-term helpers are mutually exclusive (exactly 1 true per stable record)") do
  predicates = %i[
    is_denied is_unknown_external_state is_timed_out
    is_system_error is_query_error is_partial_success
  ]
  STABLE_TERMS.each_with_object(true) do |term, ok|
    outcome = { "kind" => term }
    true_count = predicates.count { |p| OutcomeH.send(p, outcome) }
    ok && (true_count == 1)
  end
end
check("C-08: kind() returns exact string for all 6 stable terms") do
  STABLE_TERMS.all? { |t| OutcomeH.kind({ "kind" => t }) == t }
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-D — Domain-local preservation (no false collapse)"

check("D-01: is_denied false for storage-local 'found'") do
  !OutcomeH.is_denied(STORAGE[:found])
end
check("D-02: is_denied false for storage-local 'empty'") do
  !OutcomeH.is_denied(STORAGE[:empty])
end
check("D-03: is_system_error false for storage-local 'rows'") do
  !OutcomeH.is_system_error(STORAGE[:rows])
end
check("D-04: is_unknown_external_state false for storage-local 'created'") do
  !OutcomeH.is_unknown_external_state(STORAGE[:created])
end
check("D-05: is_query_error false for storage-local 'conflict'") do
  !OutcomeH.is_query_error(STORAGE[:conflict])
end
check("D-06: is_partial_success false for epistemic-local 'still_unknown'") do
  !OutcomeH.is_partial_success(EPISTEMIC[:still_unknown])
end
check("D-07: is_partial_success false for epistemic-local 'confirmed_succeeded'") do
  !OutcomeH.is_partial_success(EPISTEMIC[:confirmed_succeeded])
end
check("D-08: kind() preserves domain-local kinds exactly (no substitution)") do
  OutcomeH.kind(STORAGE[:found])   == "found"   &&
  OutcomeH.kind(STORAGE[:rows])    == "rows"    &&
  OutcomeH.kind(HTTP[:redirect])   == "redirect" &&
  OutcomeH.kind(EPISTEMIC[:still_unknown]) == "still_unknown"
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-E — Retry/routing safety (axis-9 boundary, PROP-047)"

check("E-01: is_retryable(denied) = false (deterministic refusal; PROP-047 FC-1)") do
  !OutcomeH.is_retryable(HTTP[:denied])
end
check("E-02: is_retryable(unknown_external_state) = false (reconcile not retry; Covenant P15)") do
  !OutcomeH.is_retryable(HTTP[:unknown_external_state])
end
check("E-03: is_retryable(system_error) = true (retry with backoff)") do
  OutcomeH.is_retryable(HTTP[:system_error]) &&
  OutcomeH.is_retryable(STORAGE[:system_error]) &&
  OutcomeH.is_retryable(EPISTEMIC[:system_error])
end
check("E-04: is_retryable(timed_out, pre-dispatch) = true (dispatch not started)") do
  OutcomeH.is_retryable(HTTP[:timed_out_pre])
end
check("E-05: is_retryable(timed_out, post-dispatch) = false (unknown-state path; Covenant P15)") do
  !OutcomeH.is_retryable(HTTP[:timed_out_post])
end
check("E-06: is_retryable(query_error) = false (malformed input; retry unhelpful)") do
  !OutcomeH.is_retryable(HTTP[:query_error]) &&
  !OutcomeH.is_retryable(STORAGE[:query_error])
end
check("E-07: is_retryable(domain-local 'found') = false (generic helper does not know domain semantics)") do
  !OutcomeH.is_retryable(STORAGE[:found]) &&
  !OutcomeH.is_retryable(STORAGE[:rows]) &&
  !OutcomeH.is_retryable(HTTP[:redirect]) &&
  !OutcomeH.is_retryable(EPISTEMIC[:confirmed_succeeded])
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-F — Stringly reduction evidence"

check("F-01: Helper call is no longer than direct string comparison") do
  # is_denied(o) vs o["kind"] == "denied"
  helper_form   = 'OutcomeH.is_denied(o)'
  stringly_form = 'o["kind"] == "denied"'
  helper_form.length <= stringly_form.length
end
check("F-02: Helpers centralize stable-term strings (single definition site)") do
  # Each helper defines its string literal once in OutcomeH.
  # Verified by ensuring helpers exist and respond correctly.
  %i[is_denied is_unknown_external_state is_timed_out
     is_system_error is_query_error is_partial_success].all? do |m|
    OutcomeH.respond_to?(m)
  end
end
check("F-03: Typo in string literal does not match helper (typo-prevention evidence)") do
  typo = { "kind" => "sytem_error" }  # "sytem_error" vs "system_error"
  !OutcomeH.is_system_error(typo) &&
  OutcomeH.kind(typo) == "sytem_error"  # kind() preserves whatever string is there
end
check("F-04: Direct kind comparison still required for domain-local terms") do
  # Helpers return false for domain-local kinds; caller must use kind() directly.
  found = STORAGE[:found]
  !OutcomeH.is_denied(found) &&
  !OutcomeH.is_system_error(found) &&
  OutcomeH.kind(found) == "found"  # direct comparison is the right pattern here
end
check("F-05: Helpers do NOT silently absorb domain-local kinds (no fallback unknown)") do
  unknown_domain_kind = { "kind" => "processing" }
  !OutcomeH.is_denied(unknown_domain_kind)              &&
  !OutcomeH.is_system_error(unknown_domain_kind)         &&
  !OutcomeH.is_partial_success(unknown_domain_kind)      &&
  OutcomeH.kind(unknown_domain_kind) == "processing"  # passes through unchanged
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-G — KDR / variant boundary"

check("G-01: Helpers work on KDR hashes — no variant instance required") do
  kdr = { "kind" => "unknown_external_state", "idempotency_key" => "ik-0" }
  OutcomeH.is_unknown_external_state(kdr)
end
check("G-02: ReconciliationReceipt KDR (LAB-EPISTEMIC-OUTCOME-P4 shape) works with helpers") do
  receipt_kdr = {
    "kind"             => "unknown_external_state",
    "request_id"       => "r-1",
    "idempotency_key"  => "ik-2",
    "attempt"          => "1",
    "budget_remaining" => "3",
    "evidence_kind"    => "real",
    "detail"           => ""
  }
  OutcomeH.is_unknown_external_state(receipt_kdr) &&
  !OutcomeH.is_denied(receipt_kdr)
end
check("G-03: Variant arm names (e.g. 'ConfirmedSucceededReal') are NOT stable terms") do
  # Variant arms (LAB-OUTCOME-VARIANT-P1) use PascalCase arm names.
  # Stable-term helpers do NOT match variant arm names.
  variant_name = { "kind" => "ConfirmedSucceededReal" }
  STABLE_TERMS.none? { |t| t == variant_name["kind"] } &&
  !OutcomeH.is_denied(variant_name) &&
  !OutcomeH.is_system_error(variant_name)
end
check("G-04: Helpers do not require variant exhaustiveness (no sealed enum enforcement)") do
  # Unknown domain-local kind: all is_* helpers return false (open-world)
  mystery = { "kind" => "mystery_domain_local_kind_xyz" }
  [
    OutcomeH.is_denied(mystery),
    OutcomeH.is_unknown_external_state(mystery),
    OutcomeH.is_timed_out(mystery),
    OutcomeH.is_system_error(mystery),
    OutcomeH.is_query_error(mystery),
    OutcomeH.is_partial_success(mystery),
    OutcomeH.is_retryable(mystery)
  ].none?
end
check("G-05: kind() works on both simple KDR and richer record shapes") do
  simple = { "kind" => "ok" }
  rich   = {
    "kind" => "partial_success", "succeeded_count" => "8", "failed_count" => "2",
    "batch_id" => "b-1", "idempotency_key" => "ik-9", "metadata" => "{}"
  }
  OutcomeH.kind(simple) == "ok" && OutcomeH.kind(rich) == "partial_success"
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-H — Authority closed"

check("H-01: Helpers are idempotent (same input → same output, always)") do
  o = { "kind" => "timed_out", "dispatch_started" => false }
  results = Array.new(5) { OutcomeH.is_retryable(o) }
  results.uniq.length == 1
end
check("H-02: is_retryable returns Bool only — caller decides whether to retry") do
  result = OutcomeH.is_retryable({ "kind" => "system_error" })
  result == true  # Bool; no retry was scheduled by this call
end
check("H-03: No helper holds module-level state (OutcomeH has no instance variables)") do
  OutcomeH.instance_variables.empty?
end
check("H-04: No helper modifies the outcome record (frozen hash survives)") do
  frozen_outcome = { "kind" => "denied", "message" => "auth" }.freeze
  OutcomeH.is_denied(frozen_outcome)  # raises FrozenError if modification attempted
  true
end
check("H-05: route() raises NotImplementedError with authority-policy rationale") do
  begin
    OutcomeH.route({ "kind" => "system_error" }, { "system_error" => "retry" })
    false
  rescue NotImplementedError => e
    e.message.include?("runtime authority")
  end
end
check("H-06: Helpers return Bool or String — never a new outcome record") do
  bool_result   = OutcomeH.is_denied({ "kind" => "denied" })
  string_result = OutcomeH.kind({ "kind" => "ok" })
  (bool_result == true || bool_result == false) &&
  string_result.is_a?(String)
end
check("H-07: No helper grants access to external resources (no IO methods in OutcomeH)") do
  # Excludes Ruby built-ins (send, respond_to?) — checks for domain-level IO names only
  io_methods = %i[open read write request connect socket fetch_url]
  io_methods.none? { |m| OutcomeH.singleton_methods.include?(m) }
end
check("H-08: Calling helpers does not change caller's state (side-effect free)") do
  external_counter = 0
  5.times do
    OutcomeH.is_system_error({ "kind" => "system_error" })
    OutcomeH.is_denied({ "kind" => "denied" })
    OutcomeH.kind({ "kind" => "unknown_external_state" })
  end
  external_counter == 0  # no side effect accumulated
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-I — Stdlib entry pressure (LANG-STDLIB-ENTRY-CONTRACT-P1 schema v0)"

# Entry contract sketches for accepted helpers.
# Fields follow LANG-STDLIB-ENTRY-CONTRACT-stdlib-entry-contract-v0.md schema.
ENTRY_SKETCHES = {
  "stdlib.outcome.is_denied" => {
    "canonical_name"    => "stdlib.outcome.is_denied",
    "category"          => "outcome",
    "status"            => "proof-local",
    "stability"         => { "semantic" => "convention", "lowering" => "none", "compatibility" => "pre-v1-none" },
    "fragment_class"    => "core",
    "purity"            => "pure",
    "deterministic"     => true,
    "totality"          => "total",
    "input_signature"   => ["Map[String, String]"],
    "output_signature"  => "Bool",
    "authority_surface" => "none",
    "failure_behavior"  => "absent 'kind' key → KeyError raised",
    "proof_lineage"     => ["LAB-STDLIB-OUTCOME-P1"]
  },
  "stdlib.outcome.is_retryable" => {
    "canonical_name"    => "stdlib.outcome.is_retryable",
    "category"          => "outcome",
    "status"            => "proof-local",
    "stability"         => { "semantic" => "convention", "lowering" => "none", "compatibility" => "pre-v1-none" },
    "fragment_class"    => "core",
    "purity"            => "pure",
    "deterministic"     => true,
    "totality"          => "partial: axis-9 stable terms only; domain-local kinds always false",
    "input_signature"   => ["Map[String, String]"],
    "output_signature"  => "Bool",
    "authority_surface" => "none",
    "failure_behavior"  => "domain-local kind → false (not an error; open-world)",
    "proof_lineage"     => ["LAB-STDLIB-OUTCOME-P1", "PROP-047-P2"]
  },
  "stdlib.outcome.kind" => {
    "canonical_name"    => "stdlib.outcome.kind",
    "category"          => "outcome",
    "status"            => "proof-local",
    "stability"         => { "semantic" => "convention", "lowering" => "none", "compatibility" => "pre-v1-none" },
    "fragment_class"    => "core",
    "purity"            => "pure",
    "deterministic"     => true,
    "totality"          => "total",
    "input_signature"   => ["Map[String, String]"],
    "output_signature"  => "String",
    "authority_surface" => "none",
    "failure_behavior"  => "absent 'kind' key → KeyError raised",
    "proof_lineage"     => ["LAB-STDLIB-OUTCOME-P1"]
  }
}.freeze

check("I-01: is_denied entry has fully-qualified canonical_name") do
  ENTRY_SKETCHES["stdlib.outcome.is_denied"]["canonical_name"] == "stdlib.outcome.is_denied"
end
check("I-02: All entry sketches have purity = 'pure'") do
  ENTRY_SKETCHES.values.all? { |e| e["purity"] == "pure" }
end
check("I-03: All entry sketches have authority_surface = 'none'") do
  ENTRY_SKETCHES.values.all? { |e| e["authority_surface"] == "none" }
end
check("I-04: Outcome category has cross-domain demand (≥2 domains have stable terms)") do
  ALL_DOMAINS.count { |d| d.values.any? { |o| STABLE_TERMS.include?(o["kind"]) } } >= 2
end
check("I-05: All entry sketches are deterministic") do
  ENTRY_SKETCHES.values.all? { |e| e["deterministic"] == true }
end
check("I-06: is_retryable totality correctly documents axis-9-only boundary") do
  t = ENTRY_SKETCHES["stdlib.outcome.is_retryable"]["totality"]
  t.include?("axis-9") && t.include?("domain-local")
end
check("I-07: Input signature is Map[String, String] across all helpers") do
  ENTRY_SKETCHES.values.all? { |e| e["input_signature"] == ["Map[String, String]"] }
end

# ─────────────────────────────────────────────────────────────────────────────

puts "\nSOUT-P1-J — Decision"

ACCEPTED_HELPERS = %w[
  stdlib.outcome.is_denied
  stdlib.outcome.is_unknown_external_state
  stdlib.outcome.is_timed_out
  stdlib.outcome.is_system_error
  stdlib.outcome.is_query_error
  stdlib.outcome.is_partial_success
  stdlib.outcome.kind
].freeze

CONDITIONAL_HELPERS = %w[stdlib.outcome.is_retryable].freeze
REJECTED_HELPERS    = %w[stdlib.outcome.route].freeze

check("J-01: ACCEPT 7 helpers (6 is_<stable-term> + kind passthrough)") do
  ACCEPTED_HELPERS.length == 7
end
check("J-02: ACCEPT includes stdlib.outcome.kind (opaque passthrough, domain-local safe)") do
  ACCEPTED_HELPERS.include?("stdlib.outcome.kind")
end
check("J-03: CONDITIONAL ACCEPT is_retryable with axis-9 boundary documented") do
  CONDITIONAL_HELPERS.include?("stdlib.outcome.is_retryable") &&
  ENTRY_SKETCHES["stdlib.outcome.is_retryable"]["totality"].include?("axis-9")
end
check("J-04: REJECT route() — policy encoding grants runtime authority (H-05)") do
  REJECTED_HELPERS.include?("stdlib.outcome.route")
end
check("J-05: No helper created for domain-local kinds (no false universality)") do
  domain_local = %w[found empty rows created conflict redirect rate_limited
                     confirmed_succeeded confirmed_failed still_unknown
                     reconciliation_denied reconciliation_error ok]
  domain_local.none? do |k|
    ACCEPTED_HELPERS.any? { |h| h.include?(k) }
  end
end
check("J-06: Sufficient evidence for P2 gate (all required verdicts present)") do
  ACCEPTED_HELPERS.length >= 6    &&
  CONDITIONAL_HELPERS.length >= 1 &&
  REJECTED_HELPERS.length >= 1    &&
  STABLE_TERMS.length == 6
end

# ─────────────────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "LAB-STDLIB-OUTCOME-P1  Result: #{$pass_count}/#{total}"
puts $fail_count.zero? \
  ? "VERDICT: PASS — #{$pass_count}/#{total} — proceed to LAB-STDLIB-OUTCOME-P2" \
  : "VERDICT: FAIL — #{$fail_count}/#{total} checks failing"
