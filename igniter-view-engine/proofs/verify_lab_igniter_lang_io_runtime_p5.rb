#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_io_runtime_p5.rb
#
# Card:   LAB-IGNITER-LANG-IO-RUNTIME-P5
# Route:  LAB RUNTIME / IO REGRESSION CONSOLIDATION
# Scope:  proof-local regression only; no new runtime surface.
#
# Consolidates the ladder:
#   effect_surface_v0_stub -> RuntimeMachine.evaluate_effect
#   -> CapabilityExecutorRegistry -> CapabilityPassport preflight
#   -> StorageCapabilityExecutor -> EffectResult + EffectReceipt
#   -> ServiceResponse envelope
#
# Authority: LAB-ONLY. No real IO, no DB, no SQL, no ORM, no Rack server,
# no HTTP accept loop, no production runtime claim, no Reference Runtime claim.

require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"

WORKSPACE_ROOT = Pathname.new(File.expand_path("../../..", __dir__)).freeze
LAB_ROOT       = WORKSPACE_ROOT / "igniter-lab"
LANG_ROOT      = WORKSPACE_ROOT / "igniter-lang"
LAB_DOCS       = LAB_ROOT / "lab-docs/lang"
LAB_CARDS      = LAB_ROOT / ".agents/work/cards/lang"
LANG_CARDS     = LANG_ROOT / ".agents/work/cards/lang"
PROOFS         = LAB_ROOT / "igniter-view-engine/proofs"

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

def check(label)
  result = yield
  status = result ? "PASS" : "FAIL"
  colour = result ? GREEN : RED
  puts "  #{colour}[#{status}]#{RESET} #{label}"
  RESULTS << { label: label, pass: result }
rescue => e
  puts "  #{RED}[ERROR]#{RESET} #{label}: #{e.class}: #{e.message}"
  RESULTS << { label: label, pass: false }
end

def section(title)
  puts "\n#{CYAN}#{BOLD}-- #{title} --#{RESET}"
end

def read(path)
  path.read
end

def run_proof(label, path)
  ruby = RbConfig.ruby
  stdout, stderr, status = Open3.capture3(ruby, path.to_s, chdir: WORKSPACE_ROOT.to_s)
  { label: label, path: path, stdout: stdout, stderr: stderr, status: status }
end

def parse_count(output, patterns)
  patterns.each do |pattern|
    match = output.match(pattern)
    return match[1].to_i if match
  end
  nil
end

def make_program(program_id:, artifact_hash:, contracts:)
  RuntimeMachineMemoryProof::CompiledProgram.new(
    manifest: {
      "program_id" => program_id,
      "artifact_hash" => artifact_hash,
      "language_version" => "0.1.0",
      "format" => "igapp-v1",
      "contracts" => contracts.keys,
      "schema_version" => "0.0.0"
    },
    semantic_ir: {
      "contracts" => [],
      "boundary_descriptors" => [],
      "dependency_graph" => {}
    },
    classified_ast: {
      "fragment_class" => "escape",
      "oof_count" => 0,
      "generic_templates" => []
    },
    requirements: { "required_tbackend_caps" => {} },
    diagnostics: { "diagnostics" => [] },
    contracts: contracts
  )
end

P5_CONTRACT_ID = "contract/io-storage-read-v0"
P5_EFFECT_NAME = "storage_read"
P5_AUTHORITY   = "authority/proof-p5"
P5_NOW         = "2026-06-14T00:00:00Z"
P5_ARTIFACT    = "sha256:proof-p5-storage-effect-artifact"

P5_STORAGE_CONTRACT = {
  "contract_id" => P5_CONTRACT_ID,
  "name" => "io_storage_read",
  "fragment_class" => "escape",
  "escape_set" => ["io_capability"],
  "lifecycle" => "session",
  "type_signature" => {},
  "input_ports" => [],
  "output_ports" => [],
  "compute_nodes" => [],
  "effect_surface" => {
    "kind" => "effect_surface_v0_stub",
    "capability_bindings" => [
      {
        "capability_name" => "store",
        "capability_type" => "IO.StorageCapability",
        "effect_name" => P5_EFFECT_NAME
      }
    ],
    "affects_scope" => "external",
    "affects_target" => "IO.StorageCapability",
    "authority_ref" => nil,
    "idempotency_mode" => "none",
    "idempotency_key_expr" => nil,
    "receipt_type" => nil,
    "failure_type" => nil
  },
  "escape_boundaries" => [
    {
      "kind" => "io_capability",
      "name" => P5_EFFECT_NAME,
      "required_caps" => ["IO.StorageCapability"],
      "capability_name" => "store",
      "capability_type" => "IO.StorageCapability"
    }
  ]
}.freeze

P5_PURE_CONTRACT = {
  "contract_id" => "contract/pure-v0",
  "name" => "pure_contract",
  "fragment_class" => "pure",
  "escape_set" => [],
  "lifecycle" => "session",
  "type_signature" => {},
  "input_ports" => [],
  "output_ports" => [],
  "compute_nodes" => []
}.freeze

P5_PROGRAM = make_program(
  program_id: "io-runtime-p5",
  artifact_hash: P5_ARTIFACT,
  contracts: { P5_CONTRACT_ID => P5_STORAGE_CONTRACT }
)

P5_PURE_PROGRAM = make_program(
  program_id: "io-runtime-p5-pure",
  artifact_hash: "sha256:proof-p5-pure-artifact",
  contracts: { "contract/pure-v0" => P5_PURE_CONTRACT }
)

def passport(fields = {}, overrides = {})
  CapabilityPassport.new(
    capability_id: overrides.fetch(:capability_id, "storage-read-users-v0"),
    family: overrides.fetch(:family, "storage"),
    authority_ref: overrides.fetch(:authority_ref, P5_AUTHORITY),
    granted_at: overrides.fetch(:granted_at, "2026-01-01T00:00:00Z"),
    expires_at: overrides.fetch(:expires_at, nil),
    revoked: overrides.fetch(:revoked, false),
    family_fields: {
      "allowed_sources" => ["users"],
      "allowed_ops" => ["read"],
      "read_allowed" => true,
      "row_limit" => 3,
      "allow_include_all" => false
    }.merge(fields)
  )
end

def inputs(table: "users", limit: 2, include_all: false, kind: "select")
  {
    plan: {
      "kind" => kind,
      "source" => { "table" => table },
      "projection" => { "include_all" => include_all },
      "limit" => limit
    }
  }
end

def make_machine(program = P5_PROGRAM, suffix = "p5")
  backend = RuntimeMachineMemoryProof::MemoryTBackend.new
  machine = RuntimeMachineMemoryProof::RuntimeMachine.new(
    machine_id: "machine-#{suffix}",
    session_id: "session-#{suffix}",
    backend: backend
  )
  machine.boot
  load_result = machine.load_program(program)
  [machine, load_result, backend]
end

P5_EXECUTOR = StorageCapabilityExecutor.new
P5_REGISTRY = CapabilityExecutorRegistry.new.register("IO.StorageCapability", P5_EXECUTOR)
P5_EMPTY_REGISTRY = CapabilityExecutorRegistry.new
P5_MACHINE, P5_LOAD, P5_BACKEND = make_machine

def dispatch(machine: P5_MACHINE, contract_id: P5_CONTRACT_ID, effect_name: P5_EFFECT_NAME,
             pass: passport, in_data: inputs, registry: P5_REGISTRY, idem: nil)
  machine.evaluate_effect(
    contract_id: contract_id,
    effect_name: effect_name,
    passport: pass,
    inputs: in_data,
    authority_ref: P5_AUTHORITY,
    executor_registry: registry,
    now_iso8601: P5_NOW,
    idempotency_key: idem,
    deadline_ms: 30_000
  )
end

class P5UnknownExecutor
  include CapabilityExecutor

  def family_id
    "storage"
  end

  def execute(context:, effect_name:, passport:, inputs:, authority_ref:, idempotency_key:, deadline_ms:)
    canonical = JSON.generate(inputs.transform_keys(&:to_s).sort.to_h)
    inputs_hash = "sha256:#{Digest::SHA256.hexdigest(canonical)}"
    receipt = EffectReceipt.new(
      receipt_id: "receipt/sha256:#{Digest::SHA256.hexdigest("#{passport.capability_id}:#{inputs_hash}")}",
      effect_ref: "effect/#{context.contract_ref}/#{effect_name}",
      program_id: context.program_id,
      contract_ref: context.contract_ref,
      capability_id: passport.capability_id,
      family: passport.family,
      authority_ref: passport.authority_ref,
      idempotency_key: idempotency_key,
      idempotency_used: !idempotency_key.nil?,
      inputs_hash: inputs_hash,
      outcome: "unknown_external_state",
      substrate: "storage",
      emitted_at: StorageCapabilityExecutor::PROOF_LOCAL_TIMESTAMP,
      evidence_refs: []
    )
    EffectResult.unknown_external_state(receipt: receipt, sent_at: P5_NOW, last_known: nil)
  end
end

P5_UNKNOWN_REGISTRY = CapabilityExecutorRegistry.new.register("IO.StorageCapability", P5UnknownExecutor.new)

module P5ServiceEnvelope
  def self.process(request, machine:, registry:)
    unless request[:contract_id] == P5_CONTRACT_ID
      return refusal(request, "effect.unknown_contract")
    end
    unless request[:artifact_digest] == P5_ARTIFACT
      return refusal(request, "effect.artifact_digest_mismatch")
    end
    if request[:authority_ref].to_s.empty?
      return refusal(request, "effect.authority_missing")
    end

    receipts = []
    outcomes = {}
    output = nil

    request[:effect_names].each do |effect_name|
      dispatch_result = machine.evaluate_effect(
        contract_id: request[:contract_id],
        effect_name: effect_name,
        passport: request[:capability_passports][:storage],
        inputs: request[:input],
        authority_ref: request[:authority_ref],
        executor_registry: registry,
        now_iso8601: P5_NOW,
        idempotency_key: request[:idempotency_key],
        deadline_ms: 30_000
      )

      if dispatch_result[:status] == "refused"
        return refusal(request, dispatch_result[:refusal].reason_code)
      end

      effect_result = dispatch_result[:effect_result]
      outcome = effect_result.fetch("outcome")
      runtime_receipt = effect_result.fetch("receipt")
      receipts << {
        receipt_id: runtime_receipt.fetch("receipt_id"),
        effect_name: effect_name,
        capability_id: runtime_receipt.fetch("capability_id"),
        family: runtime_receipt.fetch("family"),
        authority_ref: runtime_receipt.fetch("authority_ref"),
        idempotency_key: request[:idempotency_key],
        idempotency_key_used: !request[:idempotency_key].nil?,
        inputs_hash: runtime_receipt.fetch("inputs_hash"),
        outcome: outcome,
        substrate: runtime_receipt.fetch("substrate"),
        emitted_at: runtime_receipt.fetch("emitted_at"),
        evidence_refs: runtime_receipt.fetch("evidence_refs"),
        runtime_receipt: runtime_receipt,
        denial_gate: effect_result["gate"],
        denial_reason: effect_result["reason"]
      }
      outcomes[effect_name] = outcome
      output = effect_result["value"] if outcome == "succeeded"
    end

    kind = if outcomes.values.all? { |o| o == "succeeded" }
             "ok"
           elsif outcomes.values.all? { |o| o == "denied" }
             "denied"
           else
             "effect_failure"
           end

    response(request, kind: kind, output: output, receipts: receipts, outcomes: outcomes)
  end

  def self.refusal(request, reason_code)
    response(
      request,
      kind: "runtime_refusal",
      output: nil,
      receipts: [],
      outcomes: {},
      diagnostics: [{ reason_code: reason_code }]
    )
  end

  def self.response(request, kind:, output:, receipts:, outcomes:, diagnostics: [])
    refs = receipts.map { |r| r[:receipt_id] }
    evidence_digest = "sha256:#{Digest::SHA256.hexdigest(JSON.generate({ refs: refs, output: output, kind: kind }))}"
    {
      correlation_id: request[:correlation_id],
      contract_id: request[:contract_id],
      kind: kind,
      output: output,
      diagnostics: diagnostics,
      receipts: receipts,
      effect_outcomes: outcomes,
      response_observation: {
        kind: "response_observation",
        correlation_id: request[:correlation_id],
        outcome_kind: kind,
        receipt_refs: refs,
        evidence_digest: evidence_digest,
        observed_at: P5_NOW
      }
    }
  end
end

def request(correlation_id:, pass: passport, in_data: inputs, idem: nil, artifact: P5_ARTIFACT,
            authority: P5_AUTHORITY, substrate: "http")
  {
    correlation_id: correlation_id,
    contract_id: P5_CONTRACT_ID,
    effect_names: [P5_EFFECT_NAME],
    input: in_data,
    authority_ref: authority,
    capability_passports: { storage: pass },
    idempotency_key: idem,
    ingress_substrate: substrate,
    ingress_timestamp: P5_NOW,
    artifact_digest: artifact,
    profile_ids: []
  }
end

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-IO-RUNTIME-P5 Regression Consolidation#{RESET}"
puts "No real IO. No new runtime surface."

UPSTREAMS = {
  "LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3" => {
    path: LANG_ROOT / "experiments/effect_surface_runtime_bridge_proof/verify_effect_surface_runtime_bridge_p3.rb",
    expected: 65,
    pass_patterns: [/Total:\s+(\d+)\s+\|.*PASS:/m],
    fail_patterns: [/FAIL:\s+(\d+)/]
  },
  "LAB-IGNITER-LANG-IO-RUNTIME-P3" => {
    path: PROOFS / "verify_lab_igniter_lang_io_runtime_p3.rb",
    expected: 129,
    pass_patterns: [/PASS:\s+(\d+)\/\d+/],
    fail_patterns: [/FAIL:\s+\d+\/\d+/]
  },
  "LAB-IGNITER-LANG-IO-RUNTIME-P4" => {
    path: PROOFS / "verify_lab_igniter_lang_io_runtime_p4.rb",
    expected: 104,
    pass_patterns: [/PASS:\s+(\d+)/],
    fail_patterns: [/FAIL:\s+(\d+)/]
  },
  "LAB-IGNITER-LANG-MICROSERVICE-P3" => {
    path: PROOFS / "verify_lab_igniter_lang_microservice_p3.rb",
    expected: 90,
    pass_patterns: [/RESULT.*?(\d+)\/\d+\s+PASS/m],
    fail_patterns: [/FAIL(?:ED CHECKS)?/]
  }
}.freeze

UPSTREAM_RESULTS = UPSTREAMS.transform_values { |spec| run_proof(spec[:path].basename.to_s, spec[:path]) }

section "A: Upstream Proof Runners"
UPSTREAMS.each do |name, spec|
  result = UPSTREAM_RESULTS.fetch(name)
  output = result[:stdout] + result[:stderr]
  pass_count = parse_count(output, spec[:pass_patterns])
  check("A #{name}: runner exits successfully") { result[:status].success? }
  check("A #{name}: expected PASS count #{spec[:expected]}") { pass_count == spec[:expected] }
  check("A #{name}: output does not contain runtime exception") { !output.include?("[ERROR]") && !output.include?("Traceback") }
  check("A #{name}: proof file remains present") { spec[:path].file? }
end

section "B: Dependency Cards And Docs"
dependency_cards = {
  "LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3" => [LANG_CARDS / "LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3.md", "65/65"],
  "LANG-IO-CAPABILITY-EXECUTOR-P1" => [LANG_CARDS / "LANG-IO-CAPABILITY-EXECUTOR-P1.md", "80/80"],
  "LANG-IO-CAPABILITY-EXECUTOR-P2" => [LANG_CARDS / "LANG-IO-CAPABILITY-EXECUTOR-P2.md", "86/86"],
  "LAB-IGNITER-LANG-IO-RUNTIME-P3" => [LAB_CARDS / "LAB-IGNITER-LANG-IO-RUNTIME-P3.md", "129/129"],
  "LAB-IGNITER-LANG-IO-RUNTIME-P4" => [LAB_CARDS / "LAB-IGNITER-LANG-IO-RUNTIME-P4.md", "104/104"],
  "LAB-IGNITER-LANG-MICROSERVICE-P3" => [LAB_CARDS / "LAB-IGNITER-LANG-MICROSERVICE-P3.md", "90/90"]
}
dependency_cards.each do |name, (path, marker)|
  content = path.file? ? read(path) : ""
  check("B #{name}: card exists") { path.file? }
  check("B #{name}: card is closed") { content.include?("CLOSED") }
  check("B #{name}: expected marker #{marker}") { content.include?(marker) }
end
[
  "lab-igniter-lang-io-runtime-p3-storage-executor-proof-v0.md",
  "lab-igniter-lang-io-runtime-p4-runtime-wiring-proof-v0.md",
  "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md"
].each do |doc|
  path = LAB_DOCS / doc
  check("B doc #{doc}: exists") { path.file? }
end

section "C: Effect Surface Stub Shape"
surface = P5_STORAGE_CONTRACT.fetch("effect_surface")
binding = surface.fetch("capability_bindings").first
boundary = P5_STORAGE_CONTRACT.fetch("escape_boundaries").first
check("C-01: effect_surface kind remains effect_surface_v0_stub") { surface["kind"] == "effect_surface_v0_stub" }
check("C-02: effect_surface is not full effect_surface_v0") { surface["kind"] != "effect_surface_v0" }
check("C-03: capability_bindings is one-entry Array") { surface["capability_bindings"].is_a?(Array) && surface["capability_bindings"].length == 1 }
check("C-04: binding effect_name matches storage_read") { binding["effect_name"] == P5_EFFECT_NAME }
check("C-05: binding capability_type is IO.StorageCapability") { binding["capability_type"] == "IO.StorageCapability" }
check("C-06: binding capability_name is store") { binding["capability_name"] == "store" }
check("C-07: affects_scope is external") { surface["affects_scope"] == "external" }
check("C-08: pending authority fields stay nil/none") { surface["authority_ref"].nil? && surface["idempotency_mode"] == "none" && surface["receipt_type"].nil? }
check("C-09: escape boundary kind is io_capability") { boundary["kind"] == "io_capability" }
check("C-10: escape boundary required_caps names IO.StorageCapability") { boundary["required_caps"] == ["IO.StorageCapability"] }
check("C-11: CompiledProgram validates") { P5_PROGRAM.validate!; true }
check("C-12: program carries contract id") { P5_PROGRAM.contracts.key?(P5_CONTRACT_ID) }

section "D: Runtime Wiring Source Shape"
runtime_src = read(LANG_ROOT / "experiments/io_capability_executor/runtime_machine_io_extension.rb")
executor_src = read(LANG_ROOT / "experiments/io_capability_executor/capability_executor_runtime.rb")
check("D-01: RuntimeMachine has evaluate_effect") { RuntimeMachineMemoryProof::RuntimeMachine.method_defined?(:evaluate_effect) }
check("D-02: runtime source looks up effect_surface") { runtime_src.include?("effect_surface") }
check("D-03: runtime source fetches capability_bindings") { runtime_src.include?("capability_bindings") }
check("D-04: runtime source uses executor_registry.fetch") { runtime_src.include?("executor_registry.fetch") }
check("D-05: runtime source checks missing passport") { runtime_src.include?("effect.missing_passport") }
check("D-06: runtime source checks revoked passport") { runtime_src.include?("effect.passport_revoked") }
check("D-07: runtime source checks expired passport") { runtime_src.include?("effect.passport_expired") }
check("D-08: runtime source checks family mismatch") { runtime_src.include?("effect.passport_family_mismatch") }
check("D-09: runtime source builds ExecutionContext") { runtime_src.include?("ExecutionContext.new") }
check("D-10: runtime source appends platform_observation") { runtime_src.include?("platform_observation") && runtime_src.include?("@backend.append") }
check("D-11: executor source has StorageCapabilityExecutor") { executor_src.include?("class StorageCapabilityExecutor") }
check("D-12: executor source states proof-local no real DB") { executor_src.include?("No real DB") || executor_src.include?("no real DB") }

section "E: Runtime Preflight Refusals"
pure_machine, = make_machine(P5_PURE_PROGRAM, "pure")
ref_no_executor = dispatch(registry: P5_EMPTY_REGISTRY)
ref_missing = dispatch(pass: nil)
ref_revoked = dispatch(pass: passport({}, revoked: true, capability_id: "revoked"))
ref_expired = dispatch(pass: passport({}, expires_at: "2025-01-01T00:00:00Z", capability_id: "expired"))
ref_family = dispatch(pass: passport({}, family: "file", capability_id: "file-read"))
ref_unknown_contract = dispatch(contract_id: "contract/unknown-v0")
ref_unknown_effect = dispatch(effect_name: "unknown_effect")
ref_no_surface = dispatch(machine: pure_machine, contract_id: "contract/pure-v0")
preflight_cases = {
  "no executor" => [ref_no_executor, "effect.no_executor"],
  "missing passport" => [ref_missing, "effect.missing_passport"],
  "revoked passport" => [ref_revoked, "effect.passport_revoked"],
  "expired passport" => [ref_expired, "effect.passport_expired"],
  "family mismatch" => [ref_family, "effect.passport_family_mismatch"],
  "unknown contract" => [ref_unknown_contract, "effect.unknown_contract"],
  "unknown effect" => [ref_unknown_effect, "effect.unknown_effect_name"],
  "no effect surface" => [ref_no_surface, "effect.no_effect_surface"]
}
preflight_cases.each do |label, (result, code)|
  check("E #{label}: status refused") { result[:status] == "refused" }
  check("E #{label}: reason #{code}") { result[:refusal].reason_code == code }
  check("E #{label}: no effect_result receipt") { !result.key?(:effect_result) }
end

section "F: Executor Outcomes"
ok = dispatch(idem: "idem-ok")
g1 = dispatch(in_data: inputs(table: "secrets"))
g2 = dispatch(pass: passport("allowed_ops" => ["write"]))
g3 = dispatch(pass: passport("read_allowed" => false))
g4 = dispatch(pass: passport("row_limit" => 1), in_data: inputs(limit: 20))
g5 = dispatch(pass: passport("allow_include_all" => false), in_data: inputs(include_all: true))
g6 = dispatch(in_data: inputs(kind: "error_trigger"))
unknown = dispatch(registry: P5_UNKNOWN_REGISTRY)
check("F-01: success returns status ok") { ok[:status] == "ok" }
check("F-02: success outcome succeeded") { ok[:effect_result]["outcome"] == "succeeded" }
check("F-03: success value has mocked rows") { ok[:effect_result]["value"]["rows"].length == 2 }
check("F-04: G1 denial status ok") { g1[:status] == "ok" }
check("F-05: G1 denial is data outcome") { g1[:effect_result]["outcome"] == "denied" && g1[:effect_result]["gate"] == "G1" }
check("F-06: G2 denial gate") { g2[:effect_result]["outcome"] == "denied" && g2[:effect_result]["gate"] == "G2" }
check("F-07: G3 denial gate") { g3[:effect_result]["outcome"] == "denied" && g3[:effect_result]["gate"] == "G3" }
check("F-08: denials all carry receipts") { [g1, g2, g3].all? { |r| r[:effect_result]["receipt"].is_a?(Hash) } }
check("F-09: G4 clamp succeeds") { g4[:effect_result]["outcome"] == "succeeded" }
check("F-10: G4 effective limit is passport row limit") { g4[:effect_result]["value"]["effective_limit"] == 1 }
check("F-11: G4 row_limit_clamped true") { g4[:effect_result]["value"]["row_limit_clamped"] == true }
check("F-12: G5 include_all returns failed") { g5[:effect_result]["outcome"] == "failed" }
check("F-13: G5 error_kind query_error") { g5[:effect_result]["error_kind"] == "query_error" }
check("F-14: G6 error trigger returns failed") { g6[:effect_result]["outcome"] == "failed" }
check("F-15: G6 error_kind system_error") { g6[:effect_result]["error_kind"] == "system_error" }
check("F-16: unknown executor outcome unknown_external_state") { unknown[:effect_result]["outcome"] == "unknown_external_state" }
check("F-17: P15 helper classifies unknown external") { EffectResult.unknown_external_outcome?(unknown[:effect_result]) }
check("F-18: P15 helper does not classify denied as unknown external") { !EffectResult.unknown_external_outcome?(g1[:effect_result]) }

section "G: Receipt And Replay Evidence"
executor_results = [ok, g1, g2, g3, g4, g5, g6, unknown]
check("G-01: every executor result has receipt") { executor_results.all? { |r| r[:effect_result]["receipt"].is_a?(Hash) } }
check("G-02: every receipt id is content addressed") { executor_results.all? { |r| r[:effect_result]["receipt"]["receipt_id"].start_with?("receipt/sha256:") } }
check("G-03: every inputs_hash is sha256") { executor_results.all? { |r| r[:effect_result]["receipt"]["inputs_hash"].start_with?("sha256:") } }
check("G-04: every receipt family storage") { executor_results.all? { |r| r[:effect_result]["receipt"]["family"] == "storage" } }
check("G-05: every receipt substrate storage") { executor_results.all? { |r| r[:effect_result]["receipt"]["substrate"] == "storage" } }
check("G-06: every receipt emitted_at proof timestamp") { executor_results.all? { |r| r[:effect_result]["receipt"]["emitted_at"] == StorageCapabilityExecutor::PROOF_LOCAL_TIMESTAMP } }
check("G-07: success idempotency key is threaded") { ok[:effect_result]["receipt"]["idempotency_key"] == "idem-ok" }
check("G-08: success idempotency_used true") { ok[:effect_result]["receipt"]["idempotency_used"] == true }
same_a = dispatch(in_data: inputs(limit: 2))
same_b = dispatch(in_data: inputs(limit: 2))
diff = dispatch(in_data: inputs(limit: 3))
check("G-09: same inputs produce same inputs_hash") { same_a[:effect_result]["receipt"]["inputs_hash"] == same_b[:effect_result]["receipt"]["inputs_hash"] }
check("G-10: different inputs produce different inputs_hash") { same_a[:effect_result]["receipt"]["inputs_hash"] != diff[:effect_result]["receipt"]["inputs_hash"] }
check("G-11: RuntimeRefusal remains receipt-free") { preflight_cases.values.all? { |(r, _)| !r.key?(:effect_result) } }
check("G-12: backend observations only exist for executor outcomes") { ok[:effect_obs].kind == "platform_observation" && !ref_missing.key?(:effect_obs) }

section "H: ServiceResponse Envelope"
env_ok = P5ServiceEnvelope.process(request(correlation_id: "req-ok", idem: "idem-env"), machine: P5_MACHINE, registry: P5_REGISTRY)
env_denied = P5ServiceEnvelope.process(request(correlation_id: "req-denied", pass: passport("allowed_sources" => [])), machine: P5_MACHINE, registry: P5_REGISTRY)
env_refused = P5ServiceEnvelope.process(request(correlation_id: "req-refused", pass: passport({}, revoked: true)), machine: P5_MACHINE, registry: P5_REGISTRY)
env_unknown = P5ServiceEnvelope.process(request(correlation_id: "req-unknown"), machine: P5_MACHINE, registry: P5_UNKNOWN_REGISTRY)
env_artifact = P5ServiceEnvelope.process(request(correlation_id: "req-artifact", artifact: "sha256:wrong"), machine: P5_MACHINE, registry: P5_REGISTRY)
env_queue = P5ServiceEnvelope.process(request(correlation_id: "req-queue", substrate: "queue"), machine: P5_MACHINE, registry: P5_REGISTRY)
check("H-01: success maps to ServiceResponse kind ok") { env_ok[:kind] == "ok" }
check("H-02: success response has one receipt") { env_ok[:receipts].length == 1 }
check("H-03: success output carries rows") { env_ok[:output]["rows"].length == 2 }
check("H-04: success effect_outcomes stores succeeded") { env_ok[:effect_outcomes][P5_EFFECT_NAME] == "succeeded" }
check("H-05: success idempotency_key_used true") { env_ok[:receipts][0][:idempotency_key_used] == true }
check("H-06: denial maps to ServiceResponse kind denied") { env_denied[:kind] == "denied" }
check("H-07: denial keeps one receipt") { env_denied[:receipts].length == 1 }
check("H-08: denial receipt outcome denied") { env_denied[:receipts][0][:outcome] == "denied" }
check("H-09: denial gate threads from EffectResult") { env_denied[:receipts][0][:denial_gate] == "G1" }
check("H-10: runtime refusal maps to runtime_refusal") { env_refused[:kind] == "runtime_refusal" }
check("H-11: runtime refusal has no receipts") { env_refused[:receipts].empty? }
check("H-12: runtime refusal has diagnostic reason") { env_refused[:diagnostics][0][:reason_code] == "effect.passport_revoked" }
check("H-13: unknown external maps to effect_failure") { env_unknown[:kind] == "effect_failure" }
check("H-14: unknown external receipt outcome preserved") { env_unknown[:receipts][0][:outcome] == "unknown_external_state" }
check("H-15: artifact mismatch refuses before runtime receipt") { env_artifact[:kind] == "runtime_refusal" && env_artifact[:receipts].empty? }
check("H-16: queue substrate uses same dispatch result") { env_queue[:kind] == "ok" && env_queue[:output]["rows"].length == 2 }
check("H-17: response observation has evidence digest") { env_ok[:response_observation][:evidence_digest].start_with?("sha256:") }
check("H-18: same envelope response digest is deterministic") do
  again = P5ServiceEnvelope.process(request(correlation_id: "req-ok", idem: "idem-env"), machine: P5_MACHINE, registry: P5_REGISTRY)
  env_ok[:response_observation][:evidence_digest] == again[:response_observation][:evidence_digest]
end

section "I: Closed Surfaces"
new_runner_src = read(Pathname.new(__FILE__))
runner_executable_src = new_runner_src.lines.reject { |line| line.lstrip.start_with?("check(\"I-") }.join
p4_doc = read(LAB_DOCS / "lab-igniter-lang-io-runtime-p4-runtime-wiring-proof-v0.md")
ms_doc = read(LAB_DOCS / "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md")
closed_surface_sources = [new_runner_src, p4_doc, ms_doc, runtime_src, executor_src].join("\n")
check("I-01: P5 runner does not require rack") { !runner_executable_src.include?("require \"rack\"") && !runner_executable_src.include?("require 'rack'") }
check("I-02: P5 runner does not require active_record") { !runner_executable_src.include?("active_record") }
check("I-03: P5 runner does not create TCP server") { !runner_executable_src.include?("TCPServer") }
check("I-04: P5 runner does not open files except source reads") { !runner_executable_src.include?("File.open") }
check("I-05: P5 runner does not use Net::HTTP") { !runner_executable_src.include?("Net::HTTP") }
check("I-06: P5 runner does not invoke system commands except Ruby subprocess proofs") { !runner_executable_src.include?("system(") && !runner_executable_src.include?("`") }
check("I-07: docs mention no real DB") { closed_surface_sources.include?("no real DB") || closed_surface_sources.include?("No real DB") }
check("I-08: docs mention no Rack or HTTP server boundary") { closed_surface_sources.include?("No Rack") || closed_surface_sources.include?("no Rack") || closed_surface_sources.include?("no HTTP server") }
check("I-09: docs mention no production runtime claim") { closed_surface_sources.include?("production runtime claim") || closed_surface_sources.include?("production runtime") }
check("I-10: P5 remains outside lib/igniter_lang") { !Pathname.new(__FILE__).to_s.include?("/lib/igniter_lang/") }
check("I-11: no storage write family is modeled") { !runner_executable_src.include?("storage_write") && !runner_executable_src.include?("write_family") }
check("I-12: runner describes proof-local regression only") { new_runner_src.include?("proof-local regression only") }

pass_count = RESULTS.count { |r| r[:pass] }
fail_count = RESULTS.count { |r| !r[:pass] }
total = RESULTS.length

puts "\n#{BOLD}RESULT#{RESET}: #{pass_count}/#{total} PASS"

if fail_count.positive?
  puts "#{RED}FAILED CHECKS:#{RESET}"
  RESULTS.select { |r| !r[:pass] }.each { |r| puts "  - #{r[:label]}" }
  exit 1
end

puts "#{GREEN}#{BOLD}PASS#{RESET} - LAB-IGNITER-LANG-IO-RUNTIME-P5 regression complete"
