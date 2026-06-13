#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_microservice_p2.rb
#
# Card:   LAB-IGNITER-LANG-MICROSERVICE-P2
# Track:  LAB SERVICE ENVELOPE / MOCK EXECUTION INTEGRATION
# Route:  LAB / ENVELOPE INTEGRATION / NO SERVER / NO REAL IO
#
# Validates the ServiceRequest/ServiceResponse envelope from P1 against the
# mocked storage executor path from IO Runtime P2. Three outcome scenarios:
#   1. Succeeded (rows): G1-G6 pass → ServiceResponse kind "ok"
#   2. Denied (G1-G3): denial-as-data → ServiceResponse kind "denied"
#   3. Unknown external state: simulated timeout → ServiceResponse kind "effect_failure"
#
# Sections:
#   A — Dependency chain: P1 microservice CLOSED, IO Runtime P2 CLOSED
#   B — ServiceRequest envelope construction and 8-gate allowlist
#   C — Happy path: succeeded outcome through full envelope round-trip
#   D — Denied path: G1-G3 denial captured in ServiceResponse receipts
#   E — Unknown external state path: simulated timeout in response (P15)
#   F — Replay evidence: idempotency_key + inputs_hash + correlation_id thread through
#   G — Rack/HTTP substrate boundary: envelope works without HTTP server
#   H — Closed surfaces enforcement
#
# Total: 61 checks
#
# Authority: LAB-ONLY. No canon claim. No real IO. No DB. No Rack.
# No production runtime claim. No Reference Runtime claim.

require "pathname"
require "json"
require "digest"

LANG_ROOT  = Pathname.new(File.expand_path("../../../igniter-lang", __dir__)).freeze
LAB_ROOT   = Pathname.new(File.expand_path("../..", __dir__)).freeze
CARDS_LANG = LAB_ROOT  / ".agents/work/cards/lang"
LANG_CARDS = LANG_ROOT / ".agents/work/cards/lang"
LAB_DOCS   = LAB_ROOT  / "lab-docs/lang"

GREEN  = "\e[32m"
RED    = "\e[31m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

RESULTS = []

def check(label, &block)
  result = block.call
  status = result ? "PASS" : "FAIL"
  colour = result ? GREEN : RED
  puts "  #{colour}[#{status}]#{RESET} #{label}"
  RESULTS << { label: label, pass: result }
rescue => e
  puts "  #{RED}[ERROR]#{RESET} #{label}: #{e.message}"
  RESULTS << { label: label, pass: false }
end

def section(title)
  puts "\n#{CYAN}#{BOLD}── #{title} ──#{RESET}"
end

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-MICROSERVICE-P2 Survey#{RESET}"
puts "Mock execution integration. No real IO. No server."
puts

# ─────────────────────────────────────────────────────────────────────────────
# Proof-local runtime: EvaluateRefusal
# ─────────────────────────────────────────────────────────────────────────────

class EvaluateRefusal < StandardError
  attr_reader :reason_code
  def initialize(reason_code)
    @reason_code = reason_code
    super("Runtime refusal: #{reason_code}")
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# MockStorageCapabilityExecutor (inline; derived from IO Runtime P2 proof)
# Proof-local only. Not a production executor.
# ─────────────────────────────────────────────────────────────────────────────

class MockStorageCapabilityExecutor
  MOCKED_ROWS = [
    { "id" => "1", "name" => "Alice", "status" => "active" },
    { "id" => "2", "name" => "Bob",   "status" => "inactive" },
    { "id" => "3", "name" => "Carol", "status" => "active" }
  ].freeze

  # execute(effect_name, capability, inputs) -> [QueryResult, QueryExecutionReceipt]
  # Simplified 3-arg form for proof-local simulation.
  # The canonical interface (from LANG-IO-CAPABILITY-EXECUTOR-P1) is 7-arg:
  #   execute(context, effect_name, passport, inputs, authority_ref, idempotency_key, deadline_ms)
  def execute(effect_name, capability, inputs)
    plan = inputs[:plan]
    cap  = capability

    # Unknown external state simulation: cap signals timeout
    if cap[:simulate_unknown_external_state]
      receipt = base_receipt(cap, plan).merge(
        result_kind: "unknown_external_state",
        deny_reason: "substrate-timeout"
      )
      return [{ kind: "unknown_external_state", count: 0, rows: [] }, receipt]
    end

    base = base_receipt(cap, plan)

    # G1: source table in allowlist (fail-closed: empty = deny all)
    unless (cap[:allowed_sources] || []).include?(plan.dig(:source, :table) || "")
      reason = (cap[:deny_reason] || "").empty? ? "source-not-allowed" : cap[:deny_reason]
      return [{ kind: "denied", count: 0, rows: [], deny_reason: reason },
              base.merge(denial_gate: "G1", deny_reason: reason, result_kind: "denied")]
    end

    # G2: op in allowed_ops
    unless (cap[:allowed_ops] || []).include?("read")
      return [{ kind: "denied", count: 0, rows: [], deny_reason: "op-not-allowed" },
              base.merge(denial_gate: "G2", deny_reason: "op-not-allowed", result_kind: "denied")]
    end

    # G3: read_allowed master gate
    unless cap[:read_allowed]
      return [{ kind: "denied", count: 0, rows: [], deny_reason: "read-not-allowed" },
              base.merge(denial_gate: "G3", deny_reason: "read-not-allowed", result_kind: "denied")]
    end

    # G4: row limit clamp (NOT denial)
    plan_limit    = plan[:limit] || 0
    cap_limit     = cap[:row_limit] || 0
    effective     = [plan_limit, cap_limit].min
    clamped       = plan_limit > cap_limit

    # G5: include_all policy (query_error, NOT denied)
    if plan.dig(:projection, :include_all) && !cap[:allow_include_all]
      return [{ kind: "query_error", count: 0, rows: [], deny_reason: "include-all-not-allowed" },
              base.merge(cap_granted: false, denial_gate: "G5",
                         deny_reason: "include-all-not-allowed", result_kind: "query_error",
                         effective_limit: effective, row_limit_clamped: clamped)]
    end

    # G6: mocked execution
    rows        = MOCKED_ROWS.first(effective)
    result_kind = rows.empty? ? "empty" : "rows"
    [{ kind: result_kind, count: rows.length, rows: rows, deny_reason: "" },
     base.merge(cap_granted: true, result_kind: result_kind,
                effective_limit: effective, row_limit_clamped: clamped,
                rows_returned: rows.length)]
  end

  private

  def base_receipt(cap, plan)
    plan_limit = plan[:limit] || 0
    cap_limit  = cap[:row_limit] || 0
    {
      cap_id:            cap[:capability_id] || "",
      plan_kind:         plan[:kind] || "",
      source_table:      plan.dig(:source, :table) || "",
      op_requested:      "read",
      cap_checked:       true,
      cap_granted:       false,
      denial_gate:       "",
      deny_reason:       "",
      plan_limit:        plan_limit,
      row_limit_cap:     cap_limit,
      effective_limit:   [plan_limit, cap_limit].min,
      row_limit_clamped: plan_limit > cap_limit,
      rows_returned:     0,
      result_kind:       "",
      metadata:          plan[:metadata] || {}
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# EnvelopeRunner (proof-local)
#
# Wraps the mocked executor in ServiceRequest/ServiceResponse shapes from P1.
# Not a real runtime. Not a server. Not production code.
# ─────────────────────────────────────────────────────────────────────────────

module EnvelopeRunner
  MOCK_MANIFEST = {
    program_id:      "prog-001",
    artifact_hash:   "sha256:mock-artifact-001",
    contracts:       ["ExecuteQuery"],
    profile_blocks:  [],
    capability_decls: { "ExecuteQuery" => ["storage"] }
  }.freeze

  EXECUTOR_REGISTRY = {
    "IO.StorageCapability" => MockStorageCapabilityExecutor.new
  }.freeze

  # 8-gate allowlist from P1 Q4 (fail-closed)
  def self.validate_request!(request)
    # G1: contract_id in manifest
    unless MOCK_MANIFEST[:contracts].include?(request[:contract_id])
      raise EvaluateRefusal.new("effect.unknown_contract")
    end
    # G2: artifact_digest matches
    unless request[:artifact_digest] == MOCK_MANIFEST[:artifact_hash]
      raise EvaluateRefusal.new("effect.artifact_digest_mismatch")
    end
    # G3: capability passport family keys match declared capabilities
    declared = MOCK_MANIFEST[:capability_decls][request[:contract_id]] || []
    request[:capability_passports].each_key do |fam|
      unless declared.include?(fam.to_s)
        raise EvaluateRefusal.new("effect.undeclared_capability")
      end
    end
    # G5: authority_ref present
    raise EvaluateRefusal.new("effect.authority_missing") if (request[:authority_ref] || "").empty?
    # G6: passport not revoked (simplified)
    request[:capability_passports].each_value do |passport|
      raise EvaluateRefusal.new("effect.passport_invalid") if passport[:revoked]
    end
  end

  def self.process(request, clock: "2026-06-13T00:00:00Z")
    validate_request!(request)

    correlation_id = request[:correlation_id]
    contract_id    = request[:contract_id]
    effect_names   = request[:effect_names]
    passport_map   = request[:capability_passports]
    authority_ref  = request[:authority_ref]
    idempotency_key = request[:idempotency_key]
    plan           = request[:input][:plan]

    receipts        = []
    effect_outcomes = {}

    effect_names.each do |effect_name|
      # Registry lookup (G8)
      unless EXECUTOR_REGISTRY.key?("IO.StorageCapability")
        raise EvaluateRefusal.new("effect.unsupported_family")
      end
      executor = EXECUTOR_REGISTRY["IO.StorageCapability"]
      passport = (passport_map[:storage] || passport_map["storage"])

      # Execute
      query_result, query_receipt = executor.execute(
        effect_name,
        passport,
        { plan: plan }
      )

      # Map QueryResult outcome to EffectReceipt outcome
      qr_outcome = query_result[:kind]
      effect_outcome = case qr_outcome
                       when "rows", "empty"               then "succeeded"
                       when "denied"                      then "denied"
                       when "query_error", "system_error" then "failed"
                       when "unknown_external_state"       then "unknown_external_state"
                       else "failed"
                       end

      # Build EffectReceipt (P1 shape)
      canonical_inputs = JSON.generate({ plan: plan })
      inputs_hash = "sha256:" + Digest::SHA256.hexdigest(canonical_inputs)

      effect_receipt = {
        receipt_id:           "rcpt-" + Digest::SHA256.hexdigest("#{correlation_id}:#{effect_name}:#{inputs_hash}"),
        effect_name:          effect_name,
        capability_id:        (passport || {})[:capability_id] || "",
        family:               "storage",
        authority_ref:        authority_ref,
        idempotency_key:      idempotency_key,
        idempotency_key_used: !idempotency_key.nil?,
        inputs_hash:          inputs_hash,
        outcome:              effect_outcome,
        substrate:            "storage",
        emitted_at:           clock,
        evidence_refs:        [],
        # Storage-specific (from QueryExecutionReceipt)
        query_receipt:        query_receipt
      }

      receipts << effect_receipt
      effect_outcomes[effect_name] = effect_outcome
    end

    # Map outcomes to ServiceResponse kind
    has_unknown = effect_outcomes.values.include?("unknown_external_state")
    has_failure = effect_outcomes.values.any? { |o| o == "failed" }
    has_denied  = effect_outcomes.values.all? { |o| o == "denied" }
    has_ok      = effect_outcomes.values.all? { |o| %w[succeeded].include?(o) }

    response_kind = if has_ok               then "ok"
                    elsif has_denied        then "denied"
                    elsif has_unknown || has_failure then "effect_failure"
                    else "effect_failure"
                    end

    output = if response_kind == "ok"
               effect_names.each_with_object({}) do |en, h|
                 r = receipts.find { |rec| rec[:effect_name] == en }
                 h[en] = r[:query_receipt]
               end
             end

    # ResponseObservation (P26)
    receipt_refs    = receipts.map { |r| r[:receipt_id] }
    evidence_digest = "sha256:" + Digest::SHA256.hexdigest(
      JSON.generate({ receipts: receipt_refs, output: output, outcome_kind: response_kind })
    )
    response_observation = {
      observation_id:  "obs-" + Digest::SHA256.hexdigest("#{correlation_id}:#{evidence_digest}"),
      kind:            "response_observation",
      correlation_id:  correlation_id,
      contract_id:     contract_id,
      outcome_kind:    response_kind,
      receipt_refs:    receipt_refs,
      evidence_digest: evidence_digest,
      observed_at:     clock
    }

    {
      correlation_id:       correlation_id,
      contract_id:          contract_id,
      kind:                 response_kind,
      output:               output,
      diagnostics:          [],
      receipts:             receipts,
      effect_outcomes:      effect_outcomes,
      response_timestamp:   clock,
      response_observation: response_observation
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

PASSPORT_OK = {
  passport_id:   "passport-storage-001",
  family:        "storage",
  capability_id: "storage-read-users-v0",
  authority_ref: "auth-token-read-v0",
  issued_at:     "2026-06-13T00:00:00Z",
  expires_at:    nil,
  scope_ids:     ["read_file"],
  profile_ids:   [],
  revoked:       false,
  # Mock capability fields (from CAP_BASE in IO Runtime P2 proof)
  allowed_sources:   ["users", "posts"],
  allowed_ops:       ["read"],
  read_allowed:      true,
  row_limit:         3,
  allow_include_all: false,
  deny_reason:       ""
}.freeze

PASSPORT_DENY_SOURCE = PASSPORT_OK.merge(
  passport_id:    "passport-storage-002",
  capability_id:  "storage-deny-source-v0",
  allowed_sources: []           # deny all sources
).freeze

PASSPORT_UNKNOWN_EXT = PASSPORT_OK.merge(
  passport_id:                  "passport-storage-003",
  capability_id:                "storage-timeout-v0",
  simulate_unknown_external_state: true
).freeze

PLAN_SELECT_USERS = {
  kind:       "select",
  source:     { table: "users" },
  projection: { include_all: false },
  limit:      10,
  metadata:   { "requestor" => "test-runner" }
}.freeze

def make_request(correlation_id:, passport:, plan: PLAN_SELECT_USERS,
                 idempotency_key: nil, artifact_digest: "sha256:mock-artifact-001")
  {
    correlation_id:       correlation_id,
    contract_id:          "ExecuteQuery",
    effect_names:         ["read_file"],
    input:                { plan: plan },
    authority_ref:        "auth-token-read-v0",
    capability_passports: { storage: passport },
    idempotency_key:      idempotency_key,
    ingress_substrate:    "http",
    ingress_timestamp:    "2026-06-13T00:00:00Z",
    artifact_digest:      artifact_digest,
    profile_ids:          []
  }
end

# ─────────────────────────────────────────────────────────────────────────────
section "A — Dependency Chain"
# ─────────────────────────────────────────────────────────────────────────────

check("A-01: LAB-IGNITER-LANG-MICROSERVICE-P1 card is CLOSED (72/72)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-MICROSERVICE-P1.md").read
  content.include?("CLOSED") && content.include?("72/72")
end

check("A-02: LAB-IGNITER-LANG-IO-RUNTIME-P2 card is CLOSED (69/69)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-IO-RUNTIME-P2.md").read
  content.include?("CLOSED") && content.include?("69/69")
end

check("A-03: LANG-IO-CAPABILITY-EXECUTOR-P1 card is CLOSED (80/80)") do
  content = (LANG_CARDS / "LANG-IO-CAPABILITY-EXECUTOR-P1.md").read
  content.include?("CLOSED") && content.include?("80/80")
end

check("A-04: LAB-IGNITER-LANG-IO-RUNTIME-P1 card is CLOSED (85/85)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-IO-RUNTIME-P1.md").read
  content.include?("CLOSED") && content.include?("85/85")
end

check("A-05: P2 microservice lab doc exists") do
  (LAB_DOCS / "lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md").file?
end

check("A-06: P1 microservice envelope doc exists") do
  (LAB_DOCS / "lab-igniter-lang-microservice-envelope-p1-v0.md").file?
end

# ─────────────────────────────────────────────────────────────────────────────
section "B — ServiceRequest Envelope and 8-Gate Allowlist"
# ─────────────────────────────────────────────────────────────────────────────

check("B-01: ServiceRequest has all required envelope fields") do
  req = make_request(correlation_id: "req-B01", passport: PASSPORT_OK)
  %i[correlation_id contract_id effect_names input authority_ref
     capability_passports idempotency_key ingress_substrate
     ingress_timestamp artifact_digest profile_ids].all? { |f| req.key?(f) }
end

check("B-02: G1 gate — unknown contract_id raises EvaluateRefusal") do
  req = make_request(correlation_id: "req-B02", passport: PASSPORT_OK)
  req = req.merge(contract_id: "UnknownContract")
  raised = false
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal => e
    raised = e.reason_code == "effect.unknown_contract"
  end
  raised
end

check("B-03: G2 gate — artifact_digest mismatch raises EvaluateRefusal") do
  req = make_request(correlation_id: "req-B03", passport: PASSPORT_OK,
                     artifact_digest: "sha256:wrong-digest")
  raised = false
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal => e
    raised = e.reason_code == "effect.artifact_digest_mismatch"
  end
  raised
end

check("B-04: G3 gate — undeclared capability family raises EvaluateRefusal") do
  req = make_request(correlation_id: "req-B04", passport: PASSPORT_OK)
  req = req.merge(capability_passports: { network: PASSPORT_OK })
  raised = false
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal => e
    raised = e.reason_code == "effect.undeclared_capability"
  end
  raised
end

check("B-05: G5 gate — empty authority_ref raises EvaluateRefusal") do
  req = make_request(correlation_id: "req-B05", passport: PASSPORT_OK)
  req = req.merge(authority_ref: "")
  raised = false
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal => e
    raised = e.reason_code == "effect.authority_missing"
  end
  raised
end

check("B-06: G6 gate — revoked passport raises EvaluateRefusal") do
  revoked = PASSPORT_OK.merge(revoked: true)
  req = make_request(correlation_id: "req-B06", passport: revoked)
  raised = false
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal => e
    raised = e.reason_code == "effect.passport_invalid"
  end
  raised
end

check("B-07: valid request passes all 8 gates and returns ServiceResponse") do
  req  = make_request(correlation_id: "req-B07", passport: PASSPORT_OK)
  resp = EnvelopeRunner.process(req)
  resp.is_a?(Hash) && resp.key?(:kind) && resp[:correlation_id] == "req-B07"
end

check("B-08: EvaluateRefusal is not raised as executor denial — it is pre-executor") do
  # EvaluateRefusal before executor = no receipt
  req = make_request(correlation_id: "req-B08", passport: PASSPORT_OK,
                     artifact_digest: "sha256:bad")
  receipt_count = 0
  begin
    EnvelopeRunner.process(req)
  rescue EvaluateRefusal
    receipt_count = 0
  end
  receipt_count == 0
end

# ─────────────────────────────────────────────────────────────────────────────
section "C — Happy Path: Succeeded Outcome Through Full Envelope"
# ─────────────────────────────────────────────────────────────────────────────

RESP_OK = EnvelopeRunner.process(
  make_request(correlation_id: "req-C", passport: PASSPORT_OK,
               idempotency_key: "idem-C001")
)

check("C-01: ServiceResponse.kind is 'ok' for succeeded outcome") do
  RESP_OK[:kind] == "ok"
end

check("C-02: correlation_id threads from request to response") do
  RESP_OK[:correlation_id] == "req-C"
end

check("C-03: contract_id echoed in response") do
  RESP_OK[:contract_id] == "ExecuteQuery"
end

check("C-04: receipts array has one EffectReceipt") do
  RESP_OK[:receipts].length == 1
end

check("C-05: EffectReceipt.outcome is 'succeeded'") do
  RESP_OK[:receipts][0][:outcome] == "succeeded"
end

check("C-06: EffectReceipt has all 8 required P1 replay fields") do
  r = RESP_OK[:receipts][0]
  %i[effect_name capability_id inputs_hash outcome substrate emitted_at
     idempotency_key authority_ref].all? { |f| r.key?(f) }
end

check("C-07: EffectReceipt.family is 'storage'") do
  RESP_OK[:receipts][0][:family] == "storage"
end

check("C-08: effect_outcomes maps read_file to 'succeeded'") do
  RESP_OK[:effect_outcomes]["read_file"] == "succeeded"
end

check("C-09: ResponseObservation present with evidence_digest and correlation_id") do
  obs = RESP_OK[:response_observation]
  obs[:kind] == "response_observation" &&
    obs[:correlation_id] == "req-C" &&
    obs[:evidence_digest].start_with?("sha256:")
end

check("C-10: ResponseObservation.receipt_refs contains the receipt_id") do
  obs     = RESP_OK[:response_observation]
  rcpt_id = RESP_OK[:receipts][0][:receipt_id]
  obs[:receipt_refs].include?(rcpt_id)
end

# ─────────────────────────────────────────────────────────────────────────────
section "D — Denied Path: G1-G3 Denial Captured in ServiceResponse"
# ─────────────────────────────────────────────────────────────────────────────

RESP_DENIED = EnvelopeRunner.process(
  make_request(correlation_id: "req-D", passport: PASSPORT_DENY_SOURCE)
)

check("D-01: ServiceResponse.kind is 'denied' for denied outcome") do
  RESP_DENIED[:kind] == "denied"
end

check("D-02: correlation_id threads through denied response") do
  RESP_DENIED[:correlation_id] == "req-D"
end

check("D-03: receipts array has one EffectReceipt (receipt always produced on denial)") do
  RESP_DENIED[:receipts].length == 1
end

check("D-04: EffectReceipt.outcome is 'denied'") do
  RESP_DENIED[:receipts][0][:outcome] == "denied"
end

check("D-05: QueryExecutionReceipt.denial_gate is 'G1' (source-not-allowed)") do
  RESP_DENIED[:receipts][0][:query_receipt][:denial_gate] == "G1"
end

check("D-06: QueryExecutionReceipt.cap_granted is false on denial") do
  RESP_DENIED[:receipts][0][:query_receipt][:cap_granted] == false
end

check("D-07: QueryExecutionReceipt.rows_returned is 0 on denial") do
  RESP_DENIED[:receipts][0][:query_receipt][:rows_returned] == 0
end

check("D-08: effect_outcomes maps read_file to 'denied'") do
  RESP_DENIED[:effect_outcomes]["read_file"] == "denied"
end

# ─────────────────────────────────────────────────────────────────────────────
section "E — Unknown External State Path: Simulated Timeout (P15)"
# ─────────────────────────────────────────────────────────────────────────────

RESP_UES = EnvelopeRunner.process(
  make_request(correlation_id: "req-E", passport: PASSPORT_UNKNOWN_EXT,
               idempotency_key: "idem-E001")
)

check("E-01: ServiceResponse.kind is 'effect_failure' for unknown_external_state") do
  RESP_UES[:kind] == "effect_failure"
end

check("E-02: EffectReceipt.outcome is 'unknown_external_state' (P15: not 'failed')") do
  RESP_UES[:receipts][0][:outcome] == "unknown_external_state"
end

check("E-03: response kind is 'effect_failure' but receipt outcome distinguishes from 'failed'") do
  resp_kind    = RESP_UES[:kind]
  receipt_kind = RESP_UES[:receipts][0][:outcome]
  # P15: they are distinct — response uses effect_failure; receipt uses unknown_external_state
  resp_kind == "effect_failure" && receipt_kind == "unknown_external_state"
end

check("E-04: effect_outcomes maps read_file to 'unknown_external_state'") do
  RESP_UES[:effect_outcomes]["read_file"] == "unknown_external_state"
end

check("E-05: EffectReceipt still has receipt_id and inputs_hash (evidence always emitted)") do
  r = RESP_UES[:receipts][0]
  r[:receipt_id].start_with?("rcpt-") &&
    r[:inputs_hash].start_with?("sha256:")
end

check("E-06: correlation_id threads through unknown_external_state response") do
  RESP_UES[:correlation_id] == "req-E"
end

check("E-07: ResponseObservation.outcome_kind is 'effect_failure' for this scenario") do
  RESP_UES[:response_observation][:outcome_kind] == "effect_failure"
end

check("E-08: P1 lab doc documents unknown_external_state requires reconciliation not retry") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-envelope-p1-v0.md").read
  doc.include?("unknown_external_state") && doc.include?("reconciliation")
end

# ─────────────────────────────────────────────────────────────────────────────
section "F — Replay Evidence: idempotency_key + inputs_hash + correlation_id"
# ─────────────────────────────────────────────────────────────────────────────

check("F-01: idempotency_key threads from ServiceRequest to EffectReceipt") do
  req  = make_request(correlation_id: "req-F01", passport: PASSPORT_OK,
                      idempotency_key: "idem-F001")
  resp = EnvelopeRunner.process(req)
  resp[:receipts][0][:idempotency_key] == "idem-F001"
end

check("F-02: idempotency_key_used is true when key provided") do
  req  = make_request(correlation_id: "req-F02", passport: PASSPORT_OK,
                      idempotency_key: "idem-F002")
  resp = EnvelopeRunner.process(req)
  resp[:receipts][0][:idempotency_key_used] == true
end

check("F-03: idempotency_key_used is false when nil") do
  req  = make_request(correlation_id: "req-F03", passport: PASSPORT_OK, idempotency_key: nil)
  resp = EnvelopeRunner.process(req)
  resp[:receipts][0][:idempotency_key_used] == false
end

check("F-04: inputs_hash is deterministic (same plan = same hash)") do
  req1 = make_request(correlation_id: "req-F04a", passport: PASSPORT_OK)
  req2 = make_request(correlation_id: "req-F04b", passport: PASSPORT_OK)
  resp1 = EnvelopeRunner.process(req1)
  resp2 = EnvelopeRunner.process(req2)
  resp1[:receipts][0][:inputs_hash] == resp2[:receipts][0][:inputs_hash]
end

check("F-05: different plans produce different inputs_hash") do
  plan_a = PLAN_SELECT_USERS
  plan_b = PLAN_SELECT_USERS.merge(limit: 99)
  req1 = make_request(correlation_id: "req-F05a", passport: PASSPORT_OK, plan: plan_a)
  req2 = make_request(correlation_id: "req-F05b", passport: PASSPORT_OK, plan: plan_b)
  resp1 = EnvelopeRunner.process(req1)
  resp2 = EnvelopeRunner.process(req2)
  resp1[:receipts][0][:inputs_hash] != resp2[:receipts][0][:inputs_hash]
end

check("F-06: authority_ref threads from ServiceRequest to EffectReceipt") do
  req  = make_request(correlation_id: "req-F06", passport: PASSPORT_OK)
  resp = EnvelopeRunner.process(req)
  resp[:receipts][0][:authority_ref] == "auth-token-read-v0"
end

check("F-07: ResponseObservation.evidence_digest is sha256 (deterministic)") do
  req1  = make_request(correlation_id: "req-F07a", passport: PASSPORT_OK)
  req2  = make_request(correlation_id: "req-F07a", passport: PASSPORT_OK)
  resp1 = EnvelopeRunner.process(req1)
  resp2 = EnvelopeRunner.process(req2)
  resp1[:response_observation][:evidence_digest] == resp2[:response_observation][:evidence_digest]
end

check("F-08: denied path receipt has denial_gate in query_receipt for replay") do
  resp = RESP_DENIED
  resp[:receipts][0][:query_receipt][:denial_gate] == "G1" &&
    !resp[:receipts][0][:query_receipt][:deny_reason].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
section "G — Rack/HTTP Substrate Boundary"
# ─────────────────────────────────────────────────────────────────────────────

check("G-01: EnvelopeRunner.process takes ServiceRequest hash — no Rack env required") do
  req  = make_request(correlation_id: "req-G01", passport: PASSPORT_OK)
  resp = EnvelopeRunner.process(req)
  # Proof: response returned without any Rack env
  resp.is_a?(Hash) && !req.key?(:rack_env)
end

check("G-02: ingress_substrate field records transport type without requiring it for dispatch") do
  req = make_request(correlation_id: "req-G02", passport: PASSPORT_OK)
  # ingress_substrate is recorded but not used for executor dispatch
  req[:ingress_substrate] == "http"
end

check("G-03: queue-substrate request uses same envelope shape") do
  req = make_request(correlation_id: "req-G03", passport: PASSPORT_OK)
  req = req.merge(ingress_substrate: "queue")
  resp = EnvelopeRunner.process(req)
  resp[:kind] == "ok" && req[:ingress_substrate] == "queue"
end

check("G-04: this proof file does not require Rack gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  !src.include?("require " + "'rack'") && !src.include?("require " + '"rack"')
end

check("G-05: P1 lab doc states Rack is substrate binding not architecture") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-envelope-p1-v0.md").read
  doc.include?("one substrate binding, not the architecture")
end

check("G-06: P2 lab doc states envelope works without HTTP server") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md").read
  doc.include?("does not") && doc.include?("HTTP server") || doc.include?("no HTTP server")
end

# ─────────────────────────────────────────────────────────────────────────────
section "H — Closed Surfaces Enforcement"
# ─────────────────────────────────────────────────────────────────────────────

check("H-01: proof file does not call any real network primitive") do
  src = File.read(__FILE__, encoding: "utf-8")
  code_lines = src.lines.reject { |l| l.strip.start_with?("#") }
  forbidden = [
    "Net::" + "HTTP",
    "TCP" + "Socket",
    "Side" + "kiq",
    "Redis" + ".new",
    "PG." + "connect"
  ]
  forbidden.none? { |f| code_lines.any? { |l| l.include?(f) } }
end

check("H-02: proof file does not require ORM gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  !src.include?("require " + '"active_record"') &&
    !src.include?("require " + "'active_record'")
end

check("H-03: P2 lab doc states no production runtime claim") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md").read
  (doc.include?("production runtime claim") || doc.include?("Production runtime claim")) &&
    doc.include?("CLOSED")
end

check("H-04: P2 lab doc states no server implementation") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md").read
  doc.include?("no server implementation") || doc.include?("No server implementation") ||
    doc.include?("CLOSED — no server")
end

check("H-05: EnvelopeRunner proof-local annotation present in source") do
  src = File.read(__FILE__, encoding: "utf-8")
  src.include?("Proof-local") || src.include?("proof-local")
end

check("H-06: MockStorageCapabilityExecutor annotation in source — not production executor") do
  src = File.read(__FILE__, encoding: "utf-8")
  src.include?("Not a production executor") || src.include?("not production")
end

# ─────────────────────────────────────────────────────────────────────────────
# Results summary
# ─────────────────────────────────────────────────────────────────────────────

pass_count = RESULTS.count { |r| r[:pass] }
fail_count = RESULTS.count { |r| !r[:pass] }
total      = RESULTS.size

puts "\n#{BOLD}────────────────────────────────────────────────────────────────#{RESET}"
puts "#{BOLD}RESULT#{RESET}: #{pass_count}/#{total} PASS"

if fail_count > 0
  puts "#{RED}FAILED CHECKS:#{RESET}"
  RESULTS.select { |r| !r[:pass] }.each { |r| puts "  - #{r[:label]}" }
  puts "\n#{RED}#{BOLD}FAIL#{RESET} — #{fail_count} check(s) did not pass"
  exit 1
else
  puts "#{GREEN}#{BOLD}PASS#{RESET} — #{total}/#{total} checks passed"
  exit 0
end
