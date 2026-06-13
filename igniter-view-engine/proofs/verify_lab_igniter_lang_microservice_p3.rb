#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_microservice_p3.rb
#
# Card:   LAB-IGNITER-LANG-MICROSERVICE-P3
# Track:  LAB SERVICE ENVELOPE / RUNTIME-WIRED STORAGE EXECUTION
# Route:  LAB / ENVELOPE INTEGRATION / RUNTIME P4 PATH / NO SERVER / NO REAL IO
#
# Validates the ServiceRequest/ServiceResponse envelope from P1/P2 over the
# actual RuntimeMachine.evaluate_effect path from IO Runtime P4.
# Key difference from P2: passports are CapabilityExecutorRuntime::CapabilityPassport
# structs; dispatch goes through RuntimeMachine (8 preflight gates + executor registry).
#
# Five scenarios:
#   1. Succeeded: G1-G6 pass → ServiceResponse kind "ok"
#   2. RuntimeRefusal: envelope-level (unknown contract, artifact mismatch) + machine
#      preflight (revoked, expired, wrong family, nil passport) → kind "runtime_refusal"
#   3. Executor denial-as-data: G1–G3 capability gate → kind "denied", receipt always emitted
#   4. Unknown external state (P15): proof-local UnknownStateStorageExecutor →
#      kind "effect_failure", receipt.outcome "unknown_external_state"
#   5. Deterministic replay evidence: inputs_hash, idempotency_key, evidence_digest
#
# Sections:
#   A — Dependency chain                              (8)
#   B — CompiledProgram fixture + RuntimeMachine wire (10)
#   C — ServiceRequest with CapabilityPassport struct  (8)
#   D — Pre-evaluate envelope + machine refusals       (8)
#   E — Scenario S1: Succeeded                        (12)
#   F — Scenario S2: RuntimeRefusal (machine preflight)(10)
#   G — Scenario S3: Executor denial-as-data           (9)
#   H — Scenario S4: Unknown external state (P15)      (8)
#   I — Scenario S5: Deterministic replay evidence     (7)
#   J — Rack/HTTP substrate boundary                   (5)
#   K — Closed surfaces enforcement                    (5)
#
# Total: 90 checks
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

require_relative "../../../igniter-lang/experiments/runtime_machine_memory_proof/runtime_machine_memory_proof"
require_relative "../../../igniter-lang/experiments/runtime_machine_memory_proof/compiled_program"
require_relative "../../../igniter-lang/experiments/io_capability_executor/capability_executor_runtime"
require_relative "../../../igniter-lang/experiments/io_capability_executor/runtime_machine_io_extension"

include CapabilityExecutorRuntime

GREEN = "\e[32m"
RED   = "\e[31m"
CYAN  = "\e[36m"
BOLD  = "\e[1m"
RESET = "\e[0m"

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

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-MICROSERVICE-P3 Survey#{RESET}"
puts "Runtime-wired envelope: RuntimeMachine.evaluate_effect path. No real IO. No server."
puts

# =============================================================================
# Proof-local: UnknownStateStorageExecutor
#
# Returns EffectResult.unknown_external_state for every execute call.
# Used for Scenario S4 — registered in P3_UNKNOWN_REGISTRY instead of the
# canonical StorageCapabilityExecutor. Proof-local only; not a production executor.
# =============================================================================

class UnknownStateStorageExecutor
  include CapabilityExecutor

  PROOF_TS = StorageCapabilityExecutor::PROOF_LOCAL_TIMESTAMP

  def family_id
    "storage"
  end

  def execute(context:, effect_name:, passport:, inputs:, authority_ref:, idempotency_key:, deadline_ms:)
    inputs_str  = JSON.generate(inputs.transform_keys(&:to_s).sort.to_h)
    inputs_hash = "sha256:#{Digest::SHA256.hexdigest(inputs_str)}"
    seed        = "#{passport.capability_id}:#{effect_name}:#{inputs_hash}"
    receipt_id  = "receipt/sha256:#{Digest::SHA256.hexdigest(seed)}"

    receipt = EffectReceipt.new(
      receipt_id:      receipt_id,
      effect_ref:      "effect/#{context.contract_ref}/#{effect_name}",
      program_id:      context.program_id,
      contract_ref:    context.contract_ref,
      capability_id:   passport.capability_id,
      family:          passport.family,
      authority_ref:   passport.authority_ref,
      idempotency_key: idempotency_key,
      idempotency_used: !idempotency_key.nil?,
      inputs_hash:     inputs_hash,
      outcome:         "unknown_external_state",
      substrate:       "storage",
      emitted_at:      PROOF_TS,
      evidence_refs:   []
    )

    EffectResult.unknown_external_state(
      receipt:    receipt,
      sent_at:    PROOF_TS,
      last_known: nil
    )
  end
end

# =============================================================================
# CompiledProgram fixture (P3)
#
# Carries an effect_surface_v0_stub so RuntimeMachine.evaluate_effect can
# resolve the capability_binding for "storage_read" → "IO.StorageCapability".
# =============================================================================

P3_CONTRACT_ID = "contract/io-storage-read-v0"
P3_ARTIFACT_HASH = "sha256:proof-p3-storage-effect-artifact"
P3_CLOCK = "2026-06-13T00:00:00Z"
P3_NOW = P3_CLOCK
P3_EFFECT_NAME = "storage_read"
P3_AUTHORITY_REF = "authority/proof-p3"

P3_STORAGE_CONTRACT = {
  "contract_id"    => P3_CONTRACT_ID,
  "name"           => "io_storage_read",
  "fragment_class" => "escape",
  "escape_set"     => ["io_capability"],
  "lifecycle"      => "session",
  "type_signature" => {},
  "input_ports"    => [],
  "output_ports"   => [],
  "compute_nodes"  => [],
  "effect_surface" => {
    "kind" => "effect_surface_v0_stub",
    "capability_bindings" => [
      {
        "capability_name" => "store",
        "capability_type" => "IO.StorageCapability",
        "effect_name"     => P3_EFFECT_NAME
      }
    ]
  },
  "escape_boundaries" => [
    {
      "kind"            => "io_capability",
      "name"            => P3_EFFECT_NAME,
      "required_caps"   => ["IO.StorageCapability"],
      "capability_name" => "store",
      "capability_type" => "IO.StorageCapability"
    }
  ]
}.freeze

P3_EFFECT_PROGRAM = RuntimeMachineMemoryProof::CompiledProgram.new(
  manifest: {
    "program_id"       => "io-storage-proof-p3",
    "artifact_hash"    => P3_ARTIFACT_HASH,
    "language_version" => "0.1.0",
    "format"           => "igapp-v1",
    "contracts"        => [P3_CONTRACT_ID],
    "schema_version"   => "0.0.0"
  },
  semantic_ir: {
    "contracts"            => [],
    "boundary_descriptors" => [],
    "dependency_graph"     => {}
  },
  classified_ast: {
    "fragment_class"    => "escape",
    "oof_count"         => 0,
    "generic_templates" => []
  },
  requirements: {
    "required_tbackend_caps" => {}
  },
  diagnostics: { "diagnostics" => [] },
  contracts:   { P3_CONTRACT_ID => P3_STORAGE_CONTRACT }
)

# Boot + load one RuntimeMachine for all scenarios
P3_BACKEND = RuntimeMachineMemoryProof::MemoryTBackend.new
P3_MACHINE  = RuntimeMachineMemoryProof::RuntimeMachine.new(
  machine_id: "proof-p3-machine",
  session_id: "session-p3",
  backend:    P3_BACKEND
)
P3_MACHINE.boot
P3_MACHINE.load_program(P3_EFFECT_PROGRAM)

# Executor registries
P3_STORAGE_EXECUTOR = StorageCapabilityExecutor.new
P3_REGISTRY         = CapabilityExecutorRegistry.new.register("IO.StorageCapability", P3_STORAGE_EXECUTOR)
P3_UNKNOWN_REGISTRY = CapabilityExecutorRegistry.new.register("IO.StorageCapability", UnknownStateStorageExecutor.new)
P3_EMPTY_REGISTRY   = CapabilityExecutorRegistry.new

# =============================================================================
# Passport fixtures
# CapabilityExecutorRuntime::CapabilityPassport structs (P4 form, 7 fields).
# RuntimeMachine.evaluate_effect expects these structs for preflight gates.
# =============================================================================

P3_VALID_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-users-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)

P3_REVOKED_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-revoked-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       true,
  family_fields: {}
)

P3_EXPIRED_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-expired-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2025-01-01T00:00:00Z",
  expires_at:    "2025-12-31T23:59:59Z",
  revoked:       false,
  family_fields: {}
)

P3_WRONG_FAMILY_PASSPORT = CapabilityPassport.new(
  capability_id: "file-read-v0",
  family:        "file",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {}
)

P3_DENY_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-deny-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => [],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)

P3_G2_DENY_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-no-op-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["write"],
    "read_allowed"      => true,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)

P3_G3_DENY_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-blocked-v0",
  family:        "storage",
  authority_ref: P3_AUTHORITY_REF,
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => false,
    "row_limit"         => 3,
    "allow_include_all" => false
  }
)

P3_VALID_INPUTS = {
  plan: {
    "kind"       => "select",
    "source"     => { "table" => "users" },
    "projection" => { "include_all" => false },
    "limit"      => 2
  }
}

# =============================================================================
# RuntimeEnvelopeAdapter (proof-local)
#
# Wraps RuntimeMachine.evaluate_effect in P1 ServiceRequest/ServiceResponse shapes.
# Not a real runtime. Not a server. Not production code.
# =============================================================================

module RuntimeEnvelopeAdapter
  DECLARED_CONTRACTS = [P3_CONTRACT_ID].freeze
  PROGRAM_ARTIFACT_HASH = P3_ARTIFACT_HASH

  class PreEvaluateRefusal < StandardError
    attr_reader :reason_code
    def initialize(reason_code)
      @reason_code = reason_code
      super("Pre-evaluate refusal: #{reason_code}")
    end
  end

  def self.validate_envelope!(request)
    unless DECLARED_CONTRACTS.include?(request[:contract_id])
      raise PreEvaluateRefusal.new("effect.unknown_contract")
    end
    unless request[:artifact_digest] == PROGRAM_ARTIFACT_HASH
      raise PreEvaluateRefusal.new("effect.artifact_digest_mismatch")
    end
    if (request[:authority_ref] || "").empty?
      raise PreEvaluateRefusal.new("effect.authority_missing")
    end
  end

  def self.process(request, machine:, executor_registry:, clock: P3_CLOCK)
    begin
      validate_envelope!(request)
    rescue PreEvaluateRefusal => e
      return build_refusal_response(request, e.reason_code, clock)
    end

    correlation_id   = request[:correlation_id]
    contract_id      = request[:contract_id]
    effect_names     = request[:effect_names]
    passport_map     = request[:capability_passports]
    authority_ref    = request[:authority_ref]
    idempotency_key  = request[:idempotency_key]
    inputs           = request[:input]

    receipts         = []
    effect_outcomes  = {}
    last_effect_result = nil

    effect_names.each do |effect_name|
      passport = passport_map[:storage] || passport_map["storage"]

      dispatch_result = machine.evaluate_effect(
        contract_id:       contract_id,
        effect_name:       effect_name,
        passport:          passport,
        inputs:            inputs,
        authority_ref:     authority_ref,
        executor_registry: executor_registry,
        now_iso8601:       clock,
        idempotency_key:   idempotency_key,
        deadline_ms:       30_000
      )

      if dispatch_result[:status] == "refused"
        refusal = dispatch_result[:refusal]
        return build_refusal_response(request, refusal.reason_code, clock)
      end

      effect_result      = dispatch_result[:effect_result]
      last_effect_result = effect_result
      outcome            = EffectResult.outcome_of(effect_result)
      runtime_receipt    = effect_result["receipt"]

      effect_receipt = {
        receipt_id:          runtime_receipt["receipt_id"],
        effect_name:         effect_name,
        capability_id:       runtime_receipt["capability_id"],
        family:              runtime_receipt["family"],
        authority_ref:       runtime_receipt["authority_ref"],
        idempotency_key:     idempotency_key,
        idempotency_key_used: !idempotency_key.nil?,
        inputs_hash:         runtime_receipt["inputs_hash"],
        outcome:             outcome,
        substrate:           runtime_receipt["substrate"],
        emitted_at:          runtime_receipt["emitted_at"],
        evidence_refs:       runtime_receipt["evidence_refs"] || [],
        runtime_receipt:     runtime_receipt,
        # denial metadata threaded from EffectResult (not in inner receipt struct)
        denial_gate:         effect_result["gate"],
        denial_reason:       effect_result["reason"]
      }

      receipts        << effect_receipt
      effect_outcomes[effect_name] = outcome
    end

    all_succeeded = effect_outcomes.values.all? { |o| o == "succeeded" }
    all_denied    = effect_outcomes.values.all? { |o| o == "denied" }

    response_kind = if all_succeeded then "ok"
                   elsif all_denied  then "denied"
                   else                   "effect_failure"
                   end

    output = if response_kind == "ok" && last_effect_result
               last_effect_result["value"]
             end

    build_response(
      correlation_id:  correlation_id,
      contract_id:     contract_id,
      kind:            response_kind,
      output:          output,
      receipts:        receipts,
      effect_outcomes: effect_outcomes,
      clock:           clock
    )
  end

  def self.build_response(correlation_id:, contract_id:, kind:, output:,
                           receipts:, effect_outcomes:, clock:)
    receipt_refs    = receipts.map { |r| r[:receipt_id] }
    evidence_digest = "sha256:" + Digest::SHA256.hexdigest(
      JSON.generate({ receipts: receipt_refs, output: output, outcome_kind: kind })
    )
    response_observation = {
      observation_id:  "obs-" + Digest::SHA256.hexdigest("#{correlation_id}:#{evidence_digest}"),
      kind:            "response_observation",
      correlation_id:  correlation_id,
      contract_id:     contract_id,
      outcome_kind:    kind,
      receipt_refs:    receipt_refs,
      evidence_digest: evidence_digest,
      observed_at:     clock
    }
    {
      correlation_id:       correlation_id,
      contract_id:          contract_id,
      kind:                 kind,
      output:               output,
      diagnostics:          [],
      receipts:             receipts,
      effect_outcomes:      effect_outcomes,
      response_timestamp:   clock,
      response_observation: response_observation
    }
  end

  def self.build_refusal_response(request, reason_code, clock)
    correlation_id = request[:correlation_id]
    contract_id    = request[:contract_id]
    evidence_digest = "sha256:" + Digest::SHA256.hexdigest(
      JSON.generate({ reason_code: reason_code })
    )
    {
      correlation_id:       correlation_id,
      contract_id:          contract_id,
      kind:                 "runtime_refusal",
      output:               nil,
      diagnostics:          [{ reason_code: reason_code }],
      receipts:             [],
      effect_outcomes:      {},
      response_timestamp:   clock,
      response_observation: {
        observation_id:  "obs-refusal-" + Digest::SHA256.hexdigest("#{correlation_id}:#{reason_code}"),
        kind:            "response_observation",
        correlation_id:  correlation_id,
        contract_id:     contract_id,
        outcome_kind:    "runtime_refusal",
        receipt_refs:    [],
        evidence_digest: evidence_digest,
        observed_at:     clock
      }
    }
  end
end

# =============================================================================
# make_request helper
# =============================================================================

def make_request(correlation_id:, passport:, inputs: P3_VALID_INPUTS,
                 idempotency_key: nil,
                 artifact_digest: P3_ARTIFACT_HASH,
                 authority_ref:   P3_AUTHORITY_REF)
  {
    correlation_id:       correlation_id,
    contract_id:          P3_CONTRACT_ID,
    effect_names:         [P3_EFFECT_NAME],
    input:                inputs,
    authority_ref:        authority_ref,
    capability_passports: { storage: passport },
    idempotency_key:      idempotency_key,
    ingress_substrate:    "http",
    ingress_timestamp:    P3_CLOCK,
    artifact_digest:      artifact_digest,
    profile_ids:          []
  }
end

# Pre-compute scenario responses
RESP_OK = RuntimeEnvelopeAdapter.process(
  make_request(correlation_id: "req-ok", passport: P3_VALID_PASSPORT,
               idempotency_key: "idem-ok-001"),
  machine:           P3_MACHINE,
  executor_registry: P3_REGISTRY
)

RESP_DENIED = RuntimeEnvelopeAdapter.process(
  make_request(correlation_id: "req-denied", passport: P3_DENY_PASSPORT),
  machine:           P3_MACHINE,
  executor_registry: P3_REGISTRY
)

RESP_UES = RuntimeEnvelopeAdapter.process(
  make_request(correlation_id: "req-ues", passport: P3_VALID_PASSPORT,
               idempotency_key: "idem-ues-001"),
  machine:           P3_MACHINE,
  executor_registry: P3_UNKNOWN_REGISTRY
)

RESP_REVOKED = RuntimeEnvelopeAdapter.process(
  make_request(correlation_id: "req-revoked", passport: P3_REVOKED_PASSPORT),
  machine:           P3_MACHINE,
  executor_registry: P3_REGISTRY
)

# ─────────────────────────────────────────────────────────────────────────────
section "A — Dependency Chain"
# ─────────────────────────────────────────────────────────────────────────────

check("A-01: LAB-IGNITER-LANG-MICROSERVICE-P2 card is CLOSED (60/60)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-MICROSERVICE-P2.md").read
  content.include?("CLOSED") && content.include?("60/60")
end

check("A-02: LAB-IGNITER-LANG-IO-RUNTIME-P4 card is CLOSED (104/104)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-IO-RUNTIME-P4.md").read
  content.include?("CLOSED") && content.include?("104/104")
end

check("A-03: LAB-IGNITER-LANG-IO-RUNTIME-P3 card is CLOSED (129/129)") do
  content = (CARDS_LANG / "LAB-IGNITER-LANG-IO-RUNTIME-P3.md").read
  content.include?("CLOSED") && content.include?("129/129")
end

check("A-04: LANG-IO-CAPABILITY-EXECUTOR-P1 card is CLOSED (80/80)") do
  content = (LANG_CARDS / "LANG-IO-CAPABILITY-EXECUTOR-P1.md").read
  content.include?("CLOSED") && content.include?("80/80")
end

check("A-05: runtime_machine_io_extension.rb exists (P4 evaluate_effect wiring)") do
  (LANG_ROOT / "experiments/io_capability_executor/runtime_machine_io_extension.rb").file?
end

check("A-06: capability_executor_runtime.rb exists (StorageCapabilityExecutor)") do
  (LANG_ROOT / "experiments/io_capability_executor/capability_executor_runtime.rb").file?
end

check("A-07: P3 lab doc exists") do
  (LAB_DOCS / "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md").file?
end

check("A-08: P2 lab doc exists") do
  (LAB_DOCS / "lab-igniter-lang-microservice-p2-storage-envelope-proof-v0.md").file?
end

# ─────────────────────────────────────────────────────────────────────────────
section "B — CompiledProgram Fixture + RuntimeMachine Wiring"
# ─────────────────────────────────────────────────────────────────────────────

check("B-01: P3 contract has effect_surface with kind 'effect_surface_v0_stub'") do
  P3_STORAGE_CONTRACT["effect_surface"]["kind"] == "effect_surface_v0_stub"
end

check("B-02: capability_binding for 'storage_read' maps to 'IO.StorageCapability'") do
  binding = P3_STORAGE_CONTRACT["effect_surface"]["capability_bindings"].first
  binding["effect_name"] == P3_EFFECT_NAME &&
    binding["capability_type"] == "IO.StorageCapability"
end

check("B-03: CompiledProgram carries the contract with effect_surface") do
  P3_EFFECT_PROGRAM.contracts.key?(P3_CONTRACT_ID) &&
    P3_EFFECT_PROGRAM.contracts[P3_CONTRACT_ID]["effect_surface"] != nil
end

check("B-04: CompiledProgram.artifact_hash matches P3_ARTIFACT_HASH") do
  P3_EFFECT_PROGRAM.artifact_hash == P3_ARTIFACT_HASH
end

check("B-05: RuntimeMachine is in 'loaded' state after boot + load_program") do
  P3_MACHINE.state == "loaded"
end

check("B-06: RuntimeMachine has the loaded program accessible") do
  P3_MACHINE.loaded_program == P3_EFFECT_PROGRAM
end

check("B-07: StorageCapabilityExecutor registered in P3_REGISTRY under IO.StorageCapability") do
  P3_REGISTRY.supports?("IO.StorageCapability")
end

check("B-08: UnknownStateStorageExecutor registered in P3_UNKNOWN_REGISTRY") do
  P3_UNKNOWN_REGISTRY.supports?("IO.StorageCapability")
end

check("B-09: P3_EMPTY_REGISTRY does not support IO.StorageCapability") do
  !P3_EMPTY_REGISTRY.supports?("IO.StorageCapability")
end

check("B-10: RuntimeMachine responds to evaluate_effect (P4 extension present)") do
  P3_MACHINE.respond_to?(:evaluate_effect)
end

# ─────────────────────────────────────────────────────────────────────────────
section "C — ServiceRequest with CapabilityPassport Struct"
# ─────────────────────────────────────────────────────────────────────────────

check("C-01: ServiceRequest has all 11 required envelope fields") do
  req = make_request(correlation_id: "req-C01", passport: P3_VALID_PASSPORT)
  %i[correlation_id contract_id effect_names input authority_ref
     capability_passports idempotency_key ingress_substrate
     ingress_timestamp artifact_digest profile_ids].all? { |f| req.key?(f) }
end

check("C-02: capability_passports[:storage] is a CapabilityPassport struct") do
  req = make_request(correlation_id: "req-C02", passport: P3_VALID_PASSPORT)
  req[:capability_passports][:storage].is_a?(CapabilityPassport)
end

check("C-03: CapabilityPassport.revoked is false for P3_VALID_PASSPORT") do
  P3_VALID_PASSPORT.revoked == false
end

check("C-04: CapabilityPassport.family is 'storage'") do
  P3_VALID_PASSPORT.family == "storage"
end

check("C-05: CapabilityPassport.capability_id is present") do
  !P3_VALID_PASSPORT.capability_id.nil? && !P3_VALID_PASSPORT.capability_id.empty?
end

check("C-06: CapabilityPassport responds to expired? (machine preflight gate)") do
  P3_VALID_PASSPORT.respond_to?(:expired?)
end

check("C-07: artifact_digest in ServiceRequest matches P3 program artifact_hash") do
  req = make_request(correlation_id: "req-C07", passport: P3_VALID_PASSPORT)
  req[:artifact_digest] == P3_EFFECT_PROGRAM.artifact_hash
end

check("C-08: ingress_substrate is 'http' — recorded but not used for dispatch") do
  req = make_request(correlation_id: "req-C08", passport: P3_VALID_PASSPORT)
  req[:ingress_substrate] == "http"
end

# ─────────────────────────────────────────────────────────────────────────────
section "D — Pre-Evaluate Envelope + Machine Refusals"
# ─────────────────────────────────────────────────────────────────────────────

check("D-01: unknown contract_id raises PreEvaluateRefusal before evaluate_effect") do
  req = make_request(correlation_id: "req-D01", passport: P3_VALID_PASSPORT)
  req = req.merge(contract_id: "contract/unknown-v0")
  raised = false
  begin
    RuntimeEnvelopeAdapter.validate_envelope!(req)
  rescue RuntimeEnvelopeAdapter::PreEvaluateRefusal => e
    raised = e.reason_code == "effect.unknown_contract"
  end
  raised
end

check("D-02: artifact_digest mismatch raises PreEvaluateRefusal before evaluate_effect") do
  req = make_request(correlation_id: "req-D02", passport: P3_VALID_PASSPORT,
                     artifact_digest: "sha256:wrong-hash")
  raised = false
  begin
    RuntimeEnvelopeAdapter.validate_envelope!(req)
  rescue RuntimeEnvelopeAdapter::PreEvaluateRefusal => e
    raised = e.reason_code == "effect.artifact_digest_mismatch"
  end
  raised
end

check("D-03: pre-evaluate refusal produces ServiceResponse kind 'runtime_refusal'") do
  req  = make_request(correlation_id: "req-D03", passport: P3_VALID_PASSPORT,
                      artifact_digest: "sha256:wrong")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:kind] == "runtime_refusal"
end

check("D-04: pre-evaluate refusal produces empty receipts array (no receipt before executor)") do
  req  = make_request(correlation_id: "req-D04", passport: P3_VALID_PASSPORT,
                      artifact_digest: "sha256:wrong")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:receipts].empty?
end

check("D-05: pre-evaluate refusal produces empty effect_outcomes") do
  req  = make_request(correlation_id: "req-D05", passport: P3_VALID_PASSPORT,
                      artifact_digest: "sha256:wrong")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:effect_outcomes].empty?
end

check("D-06: pre-evaluate refusal ResponseObservation still present (audit record)") do
  req  = make_request(correlation_id: "req-D06", passport: P3_VALID_PASSPORT,
                      artifact_digest: "sha256:wrong")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  obs  = resp[:response_observation]
  obs[:kind] == "response_observation" && obs[:outcome_kind] == "runtime_refusal"
end

check("D-07: no_executor in registry → RuntimeRefusal from machine (effect.no_executor)") do
  req    = make_request(correlation_id: "req-D07", passport: P3_VALID_PASSPORT)
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_VALID_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_EMPTY_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "refused" &&
    result[:refusal].reason_code == "effect.no_executor"
end

check("D-08: authority_ref empty → PreEvaluateRefusal effect.authority_missing") do
  req = make_request(correlation_id: "req-D08", passport: P3_VALID_PASSPORT,
                     authority_ref: "")
  raised = false
  begin
    RuntimeEnvelopeAdapter.validate_envelope!(req)
  rescue RuntimeEnvelopeAdapter::PreEvaluateRefusal => e
    raised = e.reason_code == "effect.authority_missing"
  end
  raised
end

# ─────────────────────────────────────────────────────────────────────────────
section "E — Scenario S1: Succeeded"
# ─────────────────────────────────────────────────────────────────────────────

check("E-01: evaluate_effect returns status 'ok' for valid passport + allowed plan") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_VALID_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "ok"
end

check("E-02: EffectResult.outcome is 'succeeded' for S1") do
  EffectResult.outcome_of(RESP_OK[:receipts][0][:runtime_receipt]) == "succeeded" ||
    RESP_OK[:receipts][0][:outcome] == "succeeded"
end

check("E-03: ServiceResponse.kind is 'ok' for succeeded outcome") do
  RESP_OK[:kind] == "ok"
end

check("E-04: correlation_id threads from ServiceRequest to ServiceResponse") do
  RESP_OK[:correlation_id] == "req-ok"
end

check("E-05: contract_id echoed in ServiceResponse") do
  RESP_OK[:contract_id] == P3_CONTRACT_ID
end

check("E-06: receipts array has one EffectReceipt") do
  RESP_OK[:receipts].length == 1
end

check("E-07: EffectReceipt.outcome is 'succeeded'") do
  RESP_OK[:receipts][0][:outcome] == "succeeded"
end

check("E-08: EffectReceipt has all 8 required P1 replay fields") do
  r = RESP_OK[:receipts][0]
  %i[effect_name capability_id inputs_hash outcome substrate emitted_at
     idempotency_key authority_ref].all? { |f| r.key?(f) }
end

check("E-09: EffectReceipt.inputs_hash starts with 'sha256:'") do
  RESP_OK[:receipts][0][:inputs_hash].start_with?("sha256:")
end

check("E-10: effect_outcomes maps storage_read to 'succeeded'") do
  RESP_OK[:effect_outcomes][P3_EFFECT_NAME] == "succeeded"
end

check("E-11: ResponseObservation present with kind 'response_observation'") do
  obs = RESP_OK[:response_observation]
  obs[:kind] == "response_observation" &&
    obs[:correlation_id] == "req-ok" &&
    obs[:evidence_digest].start_with?("sha256:")
end

check("E-12: ServiceResponse.output contains rows from StorageCapabilityExecutor") do
  out = RESP_OK[:output]
  !out.nil? && out.is_a?(Hash) && out.key?("rows") && out["rows"].is_a?(Array)
end

# ─────────────────────────────────────────────────────────────────────────────
section "F — Scenario S2: RuntimeRefusal (Machine Preflight)"
# ─────────────────────────────────────────────────────────────────────────────

check("F-01: revoked passport → evaluate_effect returns status 'refused'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_REVOKED_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "refused"
end

check("F-02: revoked passport → RuntimeRefusal.reason_code is 'effect.passport_revoked'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_REVOKED_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:refusal].reason_code == "effect.passport_revoked"
end

check("F-03: RESP_REVOKED ServiceResponse.kind is 'runtime_refusal'") do
  RESP_REVOKED[:kind] == "runtime_refusal"
end

check("F-04: RESP_REVOKED.receipts is empty (no receipt on RuntimeRefusal)") do
  RESP_REVOKED[:receipts].empty?
end

check("F-05: RESP_REVOKED.effect_outcomes is empty") do
  RESP_REVOKED[:effect_outcomes].empty?
end

check("F-06: expired passport → reason_code 'effect.passport_expired'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_EXPIRED_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "refused" &&
    result[:refusal].reason_code == "effect.passport_expired"
end

check("F-07: wrong-family passport → reason_code 'effect.passport_family_mismatch'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_WRONG_FAMILY_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "refused" &&
    result[:refusal].reason_code == "effect.passport_family_mismatch"
end

check("F-08: nil passport → reason_code 'effect.missing_passport'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          nil,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "refused" &&
    result[:refusal].reason_code == "effect.missing_passport"
end

check("F-09: RuntimeRefusal 'runtime_refusal' is distinct from executor denial 'denied'") do
  RESP_REVOKED[:kind] == "runtime_refusal" && RESP_DENIED[:kind] == "denied"
end

check("F-10: RuntimeRefusal response.diagnostics carries reason_code") do
  diag = RESP_REVOKED[:diagnostics]
  diag.is_a?(Array) && diag.length == 1 &&
    !diag[0][:reason_code].nil? && !diag[0][:reason_code].empty?
end

# ─────────────────────────────────────────────────────────────────────────────
section "G — Scenario S3: Executor Denial-as-Data"
# ─────────────────────────────────────────────────────────────────────────────

check("G-01: evaluate_effect returns status 'ok' for denial (executor-side outcome)") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_DENY_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  result[:status] == "ok"
end

check("G-02: EffectResult.outcome is 'denied' for G1 source-not-allowed") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_DENY_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  EffectResult.denied?(result[:effect_result])
end

check("G-03: ServiceResponse.kind is 'denied'") do
  RESP_DENIED[:kind] == "denied"
end

check("G-04: receipts array has one EffectReceipt (receipt always produced on denial)") do
  RESP_DENIED[:receipts].length == 1
end

check("G-05: EffectReceipt.outcome is 'denied'") do
  RESP_DENIED[:receipts][0][:outcome] == "denied"
end

check("G-06: denial_gate is 'G1' for source-not-allowed denial (gate threaded from EffectResult)") do
  RESP_DENIED[:receipts][0][:denial_gate] == "G1"
end

check("G-07: effect_outcomes maps storage_read to 'denied'") do
  RESP_DENIED[:effect_outcomes][P3_EFFECT_NAME] == "denied"
end

check("G-08: G2 denial (read-op-not-in-allowed-ops) → executor returns 'denied'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_G2_DENY_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  eff = result[:effect_result]
  EffectResult.denied?(eff) && eff["gate"] == "G2"
end

check("G-09: G3 denial (read-not-allowed master gate) → executor returns 'denied'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_G3_DENY_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_REGISTRY,
    now_iso8601:       P3_NOW
  )
  eff = result[:effect_result]
  EffectResult.denied?(eff) && eff["gate"] == "G3"
end

# ─────────────────────────────────────────────────────────────────────────────
section "H — Scenario S4: Unknown External State (P15)"
# ─────────────────────────────────────────────────────────────────────────────

check("H-01: UnknownStateStorageExecutor returns outcome 'unknown_external_state'") do
  result = P3_MACHINE.evaluate_effect(
    contract_id:       P3_CONTRACT_ID,
    effect_name:       P3_EFFECT_NAME,
    passport:          P3_VALID_PASSPORT,
    inputs:            P3_VALID_INPUTS,
    authority_ref:     P3_AUTHORITY_REF,
    executor_registry: P3_UNKNOWN_REGISTRY,
    now_iso8601:       P3_NOW
  )
  EffectResult.unknown_external_outcome?(result[:effect_result])
end

check("H-02: ServiceResponse.kind is 'effect_failure' for unknown_external_state") do
  RESP_UES[:kind] == "effect_failure"
end

check("H-03: EffectReceipt.outcome is 'unknown_external_state' (P15: NOT 'failed')") do
  RESP_UES[:receipts][0][:outcome] == "unknown_external_state"
end

check("H-04: response kind 'effect_failure' != receipt outcome 'unknown_external_state' (P15 distinction)") do
  resp_kind    = RESP_UES[:kind]
  receipt_kind = RESP_UES[:receipts][0][:outcome]
  resp_kind == "effect_failure" && receipt_kind == "unknown_external_state"
end

check("H-05: effect_outcomes maps storage_read to 'unknown_external_state'") do
  RESP_UES[:effect_outcomes][P3_EFFECT_NAME] == "unknown_external_state"
end

check("H-06: receipt still has receipt_id and inputs_hash (evidence always emitted)") do
  r = RESP_UES[:receipts][0]
  r[:receipt_id].start_with?("receipt/") &&
    r[:inputs_hash].start_with?("sha256:")
end

check("H-07: ResponseObservation.outcome_kind is 'effect_failure' for S4") do
  RESP_UES[:response_observation][:outcome_kind] == "effect_failure"
end

check("H-08: P3 lab doc documents P15 reconciliation requirement") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md").read
  doc.include?("unknown_external_state") && doc.include?("reconciliation")
end

# ─────────────────────────────────────────────────────────────────────────────
section "I — Scenario S5: Deterministic Replay Evidence"
# ─────────────────────────────────────────────────────────────────────────────

check("I-01: same inputs → same inputs_hash (deterministic)") do
  req1  = make_request(correlation_id: "req-I01a", passport: P3_VALID_PASSPORT)
  req2  = make_request(correlation_id: "req-I01b", passport: P3_VALID_PASSPORT)
  resp1 = RuntimeEnvelopeAdapter.process(req1, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp2 = RuntimeEnvelopeAdapter.process(req2, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp1[:receipts][0][:inputs_hash] == resp2[:receipts][0][:inputs_hash]
end

check("I-02: different inputs → different inputs_hash") do
  inputs_a = P3_VALID_INPUTS
  inputs_b = { plan: P3_VALID_INPUTS[:plan].merge("limit" => 99) }
  req1  = make_request(correlation_id: "req-I02a", passport: P3_VALID_PASSPORT, inputs: inputs_a)
  req2  = make_request(correlation_id: "req-I02b", passport: P3_VALID_PASSPORT, inputs: inputs_b)
  resp1 = RuntimeEnvelopeAdapter.process(req1, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp2 = RuntimeEnvelopeAdapter.process(req2, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp1[:receipts][0][:inputs_hash] != resp2[:receipts][0][:inputs_hash]
end

check("I-03: idempotency_key threads from ServiceRequest to EffectReceipt") do
  req  = make_request(correlation_id: "req-I03", passport: P3_VALID_PASSPORT,
                      idempotency_key: "idem-I03")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:receipts][0][:idempotency_key] == "idem-I03"
end

check("I-04: idempotency_key_used is true when key provided") do
  req  = make_request(correlation_id: "req-I04", passport: P3_VALID_PASSPORT,
                      idempotency_key: "idem-I04")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:receipts][0][:idempotency_key_used] == true
end

check("I-05: idempotency_key_used is false when nil") do
  req  = make_request(correlation_id: "req-I05", passport: P3_VALID_PASSPORT, idempotency_key: nil)
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:receipts][0][:idempotency_key_used] == false
end

check("I-06: capability_id from CapabilityPassport appears in EffectReceipt") do
  RESP_OK[:receipts][0][:capability_id] == P3_VALID_PASSPORT.capability_id
end

check("I-07: ResponseObservation.evidence_digest is deterministic (same inputs → same digest)") do
  req1  = make_request(correlation_id: "req-I07a", passport: P3_VALID_PASSPORT)
  req2  = make_request(correlation_id: "req-I07a", passport: P3_VALID_PASSPORT)
  resp1 = RuntimeEnvelopeAdapter.process(req1, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp2 = RuntimeEnvelopeAdapter.process(req2, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp1[:response_observation][:evidence_digest] == resp2[:response_observation][:evidence_digest]
end

# ─────────────────────────────────────────────────────────────────────────────
section "J — Rack/HTTP Substrate Boundary"
# ─────────────────────────────────────────────────────────────────────────────

check("J-01: RuntimeEnvelopeAdapter.process takes ServiceRequest hash — no Rack env required") do
  req  = make_request(correlation_id: "req-J01", passport: P3_VALID_PASSPORT)
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp.is_a?(Hash) && !req.key?(:rack_env)
end

check("J-02: ingress_substrate recorded in ServiceRequest but not used for machine dispatch") do
  req = make_request(correlation_id: "req-J02", passport: P3_VALID_PASSPORT)
  req[:ingress_substrate] == "http"
end

check("J-03: queue-substrate ServiceRequest uses same RuntimeMachine dispatch path") do
  req  = make_request(correlation_id: "req-J03", passport: P3_VALID_PASSPORT)
  req  = req.merge(ingress_substrate: "queue")
  resp = RuntimeEnvelopeAdapter.process(req, machine: P3_MACHINE, executor_registry: P3_REGISTRY)
  resp[:kind] == "ok" && req[:ingress_substrate] == "queue"
end

check("J-04: proof file does not require the Rack gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  !src.include?("require " + "'rack'") && !src.include?("require " + '"rack"')
end

check("J-05: P1 lab doc states Rack is substrate binding not architecture") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-envelope-p1-v0.md").read
  doc.include?("one substrate binding, not the architecture")
end

# ─────────────────────────────────────────────────────────────────────────────
section "K — Closed Surfaces Enforcement"
# ─────────────────────────────────────────────────────────────────────────────

check("K-01: proof file does not use real network primitives") do
  src = File.read(__FILE__, encoding: "utf-8")
  code_lines = src.lines.reject { |l| l.strip.start_with?("#") }
  forbidden = [
    "Net::" + "HTTP",
    "TCP" + "Socket",
    "PG." + "connect",
    "Redis" + ".new"
  ]
  forbidden.none? { |f| code_lines.any? { |l| l.include?(f) } }
end

check("K-02: proof file does not require ORM gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  !src.include?("require " + '"active_record"') &&
    !src.include?("require " + "'active_record'")
end

check("K-03: P3 lab doc states no production runtime claim") do
  doc = (LAB_DOCS / "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md").read
  (doc.include?("production runtime claim") || doc.include?("Production runtime claim")) &&
    doc.include?("CLOSED")
end

check("K-04: runtime_machine_io_extension.rb states LAB-ONLY authority") do
  src = (LANG_ROOT / "experiments/io_capability_executor/runtime_machine_io_extension.rb").read
  src.include?("LAB-ONLY")
end

check("K-05: capability_executor_runtime.rb states no real DB") do
  src = (LANG_ROOT / "experiments/io_capability_executor/capability_executor_runtime.rb").read
  src.include?("No real DB")
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
