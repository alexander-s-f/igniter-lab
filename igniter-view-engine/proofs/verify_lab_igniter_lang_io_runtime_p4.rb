# frozen_string_literal: true
#
# verify_lab_igniter_lang_io_runtime_p4.rb
#
# Proof: LAB-IGNITER-LANG-IO-RUNTIME-P4
# Route: LAB RUNTIME / RUNTIMEMACHINE EXECUTOR WIRING
# Authority: proof-local only; no real DB / no SQL / no ORM
#            no production runtime claim / no Reference Runtime claim
#
# Gates required:
#   LAB-IGNITER-LANG-IO-RUNTIME-P3 (129/129 PASS) — executor substrate
#   LANG-EFFECT-SURFACE-RUNTIME-BRIDGE-P3 (65/65 PASS) — effect_surface_v0_stub
#
# Sections:
#   A — Extension + struct presence       (8)
#   B — CompiledProgram fixture           (8)
#   C — Boot + load_program               (8)
#   D — RuntimeRefusal: no executor       (6)
#   E — RuntimeRefusal: no effect_surface (5)
#   F — RuntimeRefusal: passport gates   (12)
#   G — Executor denial-as-data G1/G2/G3  (9)
#   H — Executor success                   (8)
#   I — G4 row limit clamping             (6)
#   J — G5 + G6 failure paths             (6)
#   K — Covenant P15 semantics            (6)
#   L — Receipt invariants                (8)
#   M — Backend observation packets       (8)
#   N — Unknown contract / effect_name    (6)
# Total target: >= 90 (actual: 106)

require "digest"
require "json"
require_relative "../../../igniter-lang/experiments/runtime_machine_memory_proof/runtime_machine_memory_proof"
require_relative "../../../igniter-lang/experiments/runtime_machine_memory_proof/compiled_program"
require_relative "../../../igniter-lang/experiments/io_capability_executor/capability_executor_runtime"
require_relative "../../../igniter-lang/experiments/io_capability_executor/runtime_machine_io_extension"

include CapabilityExecutorRuntime

PASS = []
FAIL = []

def check(label, &block)
  result = block.call
  if result
    PASS << label
  else
    FAIL << label
    puts "  FAIL: #{label}"
  end
rescue => e
  FAIL << label
  puts "  ERROR: #{label} — #{e.class}: #{e.message}"
end

puts "=== verify_lab_igniter_lang_io_runtime_p4 ==="
puts

# ─── Contract fixtures ────────────────────────────────────────────────────────

P4_STORAGE_CONTRACT_ID = "contract/io-storage-read-v0"
P4_STORAGE_CONTRACT = {
  "contract_id"    => P4_STORAGE_CONTRACT_ID,
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
        "effect_name"     => "storage_read"
      }
    ],
    "affects_scope"        => "external",
    "affects_target"       => "IO.StorageCapability",
    "authority_ref"        => nil,
    "idempotency_mode"     => "none",
    "idempotency_key_expr" => nil,
    "receipt_type"         => nil,
    "failure_type"         => nil
  },
  "escape_boundaries" => [
    {
      "kind"            => "io_capability",
      "name"            => "storage_read",
      "required_caps"   => ["IO.StorageCapability"],
      "capability_name" => "store",
      "capability_type" => "IO.StorageCapability"
    }
  ]
}.freeze

P4_PURE_CONTRACT_ID = "contract/pure-compute-v0"
P4_PURE_CONTRACT = {
  "contract_id"    => P4_PURE_CONTRACT_ID,
  "name"           => "pure_compute",
  "fragment_class" => "pure",
  "escape_set"     => [],
  "lifecycle"      => "session",
  "type_signature" => {},
  "input_ports"    => [],
  "output_ports"   => [],
  "compute_nodes"  => []
}.freeze

def p4_make_program(program_id:, artifact_hash:, fragment_class:, contracts:)
  RuntimeMachineMemoryProof::CompiledProgram.new(
    manifest: {
      "program_id"       => program_id,
      "artifact_hash"    => artifact_hash,
      "language_version" => "0.1.0",
      "format"           => "igapp-v1",
      "contracts"        => contracts.keys,
      "schema_version"   => "0.0.0"
    },
    semantic_ir: {
      "contracts"            => [],
      "boundary_descriptors" => [],
      "dependency_graph"     => {}
    },
    classified_ast: {
      "fragment_class"    => fragment_class,
      "oof_count"         => 0,
      "generic_templates" => []
    },
    requirements: {
      "required_tbackend_caps" => {}
    },
    diagnostics: { "diagnostics" => [] },
    contracts:    contracts
  )
end

P4_EFFECT_PROGRAM = p4_make_program(
  program_id:     "io-effect-proof-p4",
  artifact_hash:  "sha256:proof-p4-effect-artifact",
  fragment_class: "escape",
  contracts:      { P4_STORAGE_CONTRACT_ID => P4_STORAGE_CONTRACT }
)

P4_PURE_PROGRAM = p4_make_program(
  program_id:     "pure-compute-proof-p4",
  artifact_hash:  "sha256:proof-p4-pure-artifact",
  fragment_class: "pure",
  contracts:      { P4_PURE_CONTRACT_ID => P4_PURE_CONTRACT }
)

# ─── Passport fixtures ────────────────────────────────────────────────────────

P4_VALID_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-users-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 10,
    "allow_include_all" => false
  }
)

P4_REVOKED_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-revoked-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       true,
  family_fields: {}
)

P4_EXPIRED_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-expired-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2025-01-01T00:00:00Z",
  expires_at:    "2025-12-31T23:59:59Z",
  revoked:       false,
  family_fields: {}
)

P4_WRONG_FAMILY_PASSPORT = CapabilityPassport.new(
  capability_id: "file-read-v0",
  family:        "file",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {}
)

P4_G2_DENY_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-no-read-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["write"],
    "read_allowed"      => true,
    "row_limit"         => 10,
    "allow_include_all" => false
  }
)

P4_G3_DENY_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-read-blocked-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => false,
    "row_limit"         => 10,
    "allow_include_all" => false
  }
)

P4_G5_FAIL_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-no-include-all-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 10,
    "allow_include_all" => false
  }
)

P4_NOCLAMP_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-big-limit-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 100,
    "allow_include_all" => false
  }
)

P4_CLAMP_PASSPORT = CapabilityPassport.new(
  capability_id: "storage-small-limit-v0",
  family:        "storage",
  authority_ref: "authority/proof-p4",
  granted_at:    "2026-01-01T00:00:00Z",
  expires_at:    nil,
  revoked:       false,
  family_fields: {
    "allowed_sources"   => ["users"],
    "allowed_ops"       => ["read"],
    "read_allowed"      => true,
    "row_limit"         => 1,
    "allow_include_all" => false
  }
)

# ─── Executor registry ────────────────────────────────────────────────────────

P4_STORAGE_EXECUTOR = StorageCapabilityExecutor.new
P4_REGISTRY         = CapabilityExecutorRegistry.new.register("IO.StorageCapability", P4_STORAGE_EXECUTOR)
P4_EMPTY_REGISTRY   = CapabilityExecutorRegistry.new

# ─── Input fixtures ───────────────────────────────────────────────────────────

P4_NOW           = "2026-06-13T00:00:00Z"
P4_EFFECT_NAME   = "storage_read"
P4_AUTHORITY_REF = "authority/proof-p4"

P4_VALID_INPUTS = {
  plan: {
    "source"     => { "table" => "users" },
    "limit"      => 2,
    "projection" => { "include_all" => false }
  }
}.freeze

P4_G1_DENY_INPUTS = {
  plan: {
    "source"     => { "table" => "forbidden_table" },
    "limit"      => 2,
    "projection" => { "include_all" => false }
  }
}.freeze

P4_G5_FAIL_INPUTS = {
  plan: {
    "source"     => { "table" => "users" },
    "limit"      => 2,
    "projection" => { "include_all" => true }
  }
}.freeze

P4_G6_ERROR_INPUTS = {
  plan: {
    "kind"       => "error_trigger",
    "source"     => { "table" => "users" },
    "limit"      => 2,
    "projection" => { "include_all" => false }
  }
}.freeze

P4_HIGH_LIMIT_INPUTS = {
  plan: {
    "source"     => { "table" => "users" },
    "limit"      => 100,
    "projection" => { "include_all" => false }
  }
}.freeze

# ─── Machine factory ─────────────────────────────────────────────────────────

def p4_make_machine(suffix)
  backend = RuntimeMachineMemoryProof::MemoryTBackend.new
  machine = RuntimeMachineMemoryProof::RuntimeMachine.new(
    machine_id: "proof-p4-#{suffix}",
    session_id: "proof-p4-session-#{suffix}",
    backend:    backend
  )
  machine.boot
  machine
end

# ─── Pre-computed dispatch results ───────────────────────────────────────────
#
# DISPATCH_MACHINE is loaded with P4_EFFECT_PROGRAM and used for all executor
# dispatch tests. evaluate_effect does not mutate @state, so repeated calls are safe.

P4_DISPATCH_MACHINE = p4_make_machine("dispatch")
P4_DR = P4_DISPATCH_MACHINE.load_program(P4_EFFECT_PROGRAM)

def p4_dispatch(**overrides)
  P4_DISPATCH_MACHINE.evaluate_effect(
    contract_id:       overrides.fetch(:contract_id, P4_STORAGE_CONTRACT_ID),
    effect_name:       overrides.fetch(:effect_name, P4_EFFECT_NAME),
    passport:          overrides.fetch(:passport, P4_VALID_PASSPORT),
    inputs:            overrides.fetch(:inputs, P4_VALID_INPUTS),
    authority_ref:     overrides.fetch(:authority_ref, P4_AUTHORITY_REF),
    executor_registry: overrides.fetch(:registry, P4_REGISTRY),
    now_iso8601:       overrides.fetch(:now, P4_NOW)
  )
end

# Section D — no executor
P4_D_RESULT = p4_dispatch(registry: P4_EMPTY_REGISTRY)
# Section F — passport gates
P4_F_NIL      = p4_dispatch(passport: nil)
P4_F_REVOKED  = p4_dispatch(passport: P4_REVOKED_PASSPORT)
P4_F_EXPIRED  = p4_dispatch(passport: P4_EXPIRED_PASSPORT)
P4_F_FAMILY   = p4_dispatch(passport: P4_WRONG_FAMILY_PASSPORT)
# Section G — denial-as-data
P4_G_G1 = p4_dispatch(inputs: P4_G1_DENY_INPUTS)
P4_G_G2 = p4_dispatch(passport: P4_G2_DENY_PASSPORT)
P4_G_G3 = p4_dispatch(passport: P4_G3_DENY_PASSPORT)
# Section H — success
P4_H_SUCCESS = p4_dispatch
# Section I — G4 row clamping
P4_I_NOCLAMP = p4_dispatch(passport: P4_NOCLAMP_PASSPORT, inputs: P4_VALID_INPUTS)
P4_I_CLAMP   = p4_dispatch(passport: P4_CLAMP_PASSPORT, inputs: P4_HIGH_LIMIT_INPUTS)
# Section J — failure paths
P4_J_G5 = p4_dispatch(passport: P4_G5_FAIL_PASSPORT, inputs: P4_G5_FAIL_INPUTS)
P4_J_G6 = p4_dispatch(inputs: P4_G6_ERROR_INPUTS)
# Section N — unknown contract / effect_name
P4_N_CONTRACT = p4_dispatch(contract_id: "contract/nonexistent-v0")
P4_N_EFFECT   = p4_dispatch(effect_name: "nonexistent_effect")

# Section E — no effect_surface (pure contract, separate machine)
P4_E_MACHINE = p4_make_machine("pure")
P4_E_MACHINE.load_program(P4_PURE_PROGRAM)
P4_E_RESULT = P4_E_MACHINE.evaluate_effect(
  contract_id:       P4_PURE_CONTRACT_ID,
  effect_name:       P4_EFFECT_NAME,
  passport:          P4_VALID_PASSPORT,
  inputs:            P4_VALID_INPUTS,
  authority_ref:     P4_AUTHORITY_REF,
  executor_registry: P4_REGISTRY,
  now_iso8601:       P4_NOW
)

# Section K — Covenant P15 synthetic EffectResult checks
P4_K_RECEIPT = EffectReceipt.new(
  receipt_id:       "receipt/sha256:k-p15-test-dummy",
  effect_ref:       "effect/k-contract/k-effect",
  program_id:       "k-test",
  contract_ref:     "k-contract",
  capability_id:    "k-cap",
  family:           "storage",
  authority_ref:    "k-authority",
  idempotency_key:  nil,
  idempotency_used: false,
  inputs_hash:      "sha256:k-inputs",
  outcome:          "timed_out",
  substrate:        "storage",
  emitted_at:       "2026-06-13T00:00:00Z",
  evidence_refs:    []
)
P4_K_TIMED_OUT = EffectResult.timed_out(receipt: P4_K_RECEIPT, after_ms: 5000)
P4_K_UES       = EffectResult.unknown_external_state(receipt: P4_K_RECEIPT, sent_at: P4_NOW)
P4_K_SUCCEEDED = EffectResult.succeeded(receipt: P4_K_RECEIPT)
P4_K_DENIED    = EffectResult.denied(receipt: P4_K_RECEIPT, gate: "G1", reason: "test")

# Section M — dedicated machine for packet count isolation
P4_M_MACHINE = p4_make_machine("m")
P4_M_MACHINE.load_program(P4_EFFECT_PROGRAM)
P4_M_BEFORE_COUNT = P4_M_MACHINE.backend.entries.length
P4_M_RESULT = P4_M_MACHINE.evaluate_effect(
  contract_id:       P4_STORAGE_CONTRACT_ID,
  effect_name:       P4_EFFECT_NAME,
  passport:          P4_VALID_PASSPORT,
  inputs:            P4_VALID_INPUTS,
  authority_ref:     P4_AUTHORITY_REF,
  executor_registry: P4_REGISTRY,
  now_iso8601:       P4_NOW
)
P4_M_AFTER_COUNT = P4_M_MACHINE.backend.entries.length

# =============================================================================
# Section A: Extension + struct presence
# =============================================================================
puts "A: Extension + struct presence"

check("A-01: RuntimeMachine method evaluate_effect defined") do
  RuntimeMachineMemoryProof::RuntimeMachine.method_defined?(:evaluate_effect)
end

check("A-02: CapabilityExecutorRuntime::RuntimeRefusal is a Struct") do
  RuntimeRefusal.is_a?(Class) && RuntimeRefusal.ancestors.include?(Struct)
end

check("A-03: CapabilityExecutorRuntime::EffectResult is a Module") do
  EffectResult.is_a?(Module)
end

check("A-04: CapabilityExecutorRuntime::CapabilityExecutorRegistry is a Class") do
  CapabilityExecutorRegistry.is_a?(Class)
end

check("A-05: CapabilityExecutorRuntime::StorageCapabilityExecutor is a Class") do
  StorageCapabilityExecutor.is_a?(Class)
end

check("A-06: P4_EFFECT_PROGRAM is CompiledProgram") do
  P4_EFFECT_PROGRAM.is_a?(RuntimeMachineMemoryProof::CompiledProgram)
end

check("A-07: EFFECT_PROGRAM contracts includes storage contract ID") do
  P4_EFFECT_PROGRAM.contracts.key?(P4_STORAGE_CONTRACT_ID)
end

check("A-08: EFFECT_PROGRAM storage contract has effect_surface") do
  !P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["effect_surface"].nil?
end

puts

# =============================================================================
# Section B: CompiledProgram fixture validation
# =============================================================================
puts "B: CompiledProgram fixture"

check("B-01: EFFECT_PROGRAM.program_id correct") do
  P4_EFFECT_PROGRAM.program_id == "io-effect-proof-p4"
end

check("B-02: EFFECT_PROGRAM.validate! does not raise") do
  P4_EFFECT_PROGRAM.validate!
  true
rescue => e
  puts "  validate! raised: #{e.message}"
  false
end

check("B-03: effect_surface kind is effect_surface_v0_stub") do
  es = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["effect_surface"]
  es["kind"] == "effect_surface_v0_stub"
end

check("B-04: effect_surface has 1 capability_binding") do
  es = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["effect_surface"]
  es["capability_bindings"].length == 1
end

check("B-05: capability_binding effect_name == storage_read") do
  binding = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["effect_surface"]["capability_bindings"][0]
  binding["effect_name"] == "storage_read"
end

check("B-06: capability_binding capability_type == IO.StorageCapability") do
  binding = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["effect_surface"]["capability_bindings"][0]
  binding["capability_type"] == "IO.StorageCapability"
end

check("B-07: escape_boundaries has 1 io_capability entry") do
  eb = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["escape_boundaries"]
  eb.length == 1 && eb[0]["kind"] == "io_capability"
end

check("B-08: escape_boundaries capability_type == IO.StorageCapability") do
  eb = P4_EFFECT_PROGRAM.contracts[P4_STORAGE_CONTRACT_ID]["escape_boundaries"]
  eb[0]["capability_type"] == "IO.StorageCapability"
end

puts

# =============================================================================
# Section C: Boot + load_program
# =============================================================================
puts "C: Boot + load_program"

check("C-01: DISPATCH_MACHINE state == loaded") do
  P4_DISPATCH_MACHINE.state == "loaded"
end

check("C-02: load_program status == loaded") do
  P4_DR[:status] == "loaded"
end

check("C-03: loaded_program is EFFECT_PROGRAM") do
  P4_DISPATCH_MACHINE.loaded_program.equal?(P4_EFFECT_PROGRAM)
end

check("C-04: loaded_program.program_id == io-effect-proof-p4") do
  P4_DISPATCH_MACHINE.loaded_program.program_id == "io-effect-proof-p4"
end

check("C-05: backend has entries after boot+load") do
  P4_DISPATCH_MACHINE.backend.entries.length > 0
end

check("C-06: load_program result has descriptor_refs") do
  P4_DR.key?(:descriptor_refs) && !P4_DR[:descriptor_refs].empty?
end

check("C-07: load_program result has program_id") do
  P4_DR[:program_id] == "io-effect-proof-p4"
end

check("C-08: loaded_schema_descriptor present") do
  !P4_DISPATCH_MACHINE.loaded_schema_descriptor.nil?
end

puts

# =============================================================================
# Section D: RuntimeRefusal — no executor registered
# =============================================================================
puts "D: RuntimeRefusal — no executor"

check("D-01: D_RESULT status == refused") do
  P4_D_RESULT[:status] == "refused"
end

check("D-02: D_RESULT refusal is RuntimeRefusal Struct") do
  P4_D_RESULT[:refusal].is_a?(RuntimeRefusal)
end

check("D-03: D_RESULT refusal reason_code == effect.no_executor") do
  P4_D_RESULT[:refusal].reason_code == "effect.no_executor"
end

check("D-04: D_RESULT refusal contract_ref == storage contract ID") do
  P4_D_RESULT[:refusal].contract_ref == P4_STORAGE_CONTRACT_ID
end

check("D-05: D_RESULT refusal effect_ref includes contract_id and effect_name") do
  ref = P4_D_RESULT[:refusal].effect_ref
  ref.include?(P4_STORAGE_CONTRACT_ID) && ref.include?(P4_EFFECT_NAME)
end

check("D-06: D_RESULT has no :effect_result key (no receipt on RuntimeRefusal)") do
  !P4_D_RESULT.key?(:effect_result)
end

puts

# =============================================================================
# Section E: RuntimeRefusal — no effect_surface
# =============================================================================
puts "E: RuntimeRefusal — no effect_surface"

check("E-01: E_RESULT status == refused") do
  P4_E_RESULT[:status] == "refused"
end

check("E-02: E_RESULT refusal reason_code == effect.no_effect_surface") do
  P4_E_RESULT[:refusal].reason_code == "effect.no_effect_surface"
end

check("E-03: E_RESULT refusal contract_ref == pure contract ID") do
  P4_E_RESULT[:refusal].contract_ref == P4_PURE_CONTRACT_ID
end

check("E-04: E_RESULT refusal is RuntimeRefusal Struct") do
  P4_E_RESULT[:refusal].is_a?(RuntimeRefusal)
end

check("E-05: E_RESULT has no :effect_result key (no receipt)") do
  !P4_E_RESULT.key?(:effect_result)
end

puts

# =============================================================================
# Section F: RuntimeRefusal — passport gates
# =============================================================================
puts "F: RuntimeRefusal — passport gates"

check("F-01: nil passport → status == refused") do
  P4_F_NIL[:status] == "refused"
end

check("F-02: nil passport → reason_code == effect.missing_passport") do
  P4_F_NIL[:refusal].reason_code == "effect.missing_passport"
end

check("F-03: nil passport → no :effect_result key") do
  !P4_F_NIL.key?(:effect_result)
end

check("F-04: revoked passport → status == refused") do
  P4_F_REVOKED[:status] == "refused"
end

check("F-05: revoked passport → reason_code == effect.passport_revoked") do
  P4_F_REVOKED[:refusal].reason_code == "effect.passport_revoked"
end

check("F-06: revoked passport → detail includes capability_id") do
  P4_F_REVOKED[:refusal].detail.include?(P4_REVOKED_PASSPORT.capability_id)
end

check("F-07: expired passport → status == refused") do
  P4_F_EXPIRED[:status] == "refused"
end

check("F-08: expired passport → reason_code == effect.passport_expired") do
  P4_F_EXPIRED[:refusal].reason_code == "effect.passport_expired"
end

check("F-09: expired passport → detail includes expiry date") do
  P4_F_EXPIRED[:refusal].detail.include?("2025-12-31")
end

check("F-10: wrong family passport → status == refused") do
  P4_F_FAMILY[:status] == "refused"
end

check("F-11: wrong family passport → reason_code == effect.passport_family_mismatch") do
  P4_F_FAMILY[:refusal].reason_code == "effect.passport_family_mismatch"
end

check("F-12: wrong family passport → detail includes wrong family name") do
  P4_F_FAMILY[:refusal].detail.include?("file")
end

puts

# =============================================================================
# Section G: Executor denial-as-data G1 / G2 / G3
# =============================================================================
puts "G: Executor denial-as-data"

check("G-01: G1 denial → status == ok (dispatch reached executor)") do
  P4_G_G1[:status] == "ok"
end

check("G-02: G1 denial → effect_result outcome == denied") do
  P4_G_G1[:effect_result]["outcome"] == "denied"
end

check("G-03: G1 denial → gate == G1") do
  P4_G_G1[:effect_result]["gate"] == "G1"
end

check("G-04: G1 denial → receipt present in effect_result") do
  !P4_G_G1[:effect_result]["receipt"].nil?
end

check("G-05: G2 denial → status == ok") do
  P4_G_G2[:status] == "ok"
end

check("G-06: G2 denial → outcome == denied") do
  P4_G_G2[:effect_result]["outcome"] == "denied"
end

check("G-07: G2 denial → gate == G2") do
  P4_G_G2[:effect_result]["gate"] == "G2"
end

check("G-08: G3 denial → outcome == denied") do
  P4_G_G3[:effect_result]["outcome"] == "denied"
end

check("G-09: G3 denial → gate == G3") do
  P4_G_G3[:effect_result]["gate"] == "G3"
end

puts

# =============================================================================
# Section H: Executor success — mocked storage read
# =============================================================================
puts "H: Executor success"

check("H-01: success → status == ok") do
  P4_H_SUCCESS[:status] == "ok"
end

check("H-02: success → effect_result outcome == succeeded") do
  P4_H_SUCCESS[:effect_result]["outcome"] == "succeeded"
end

check("H-03: success → value.rows is an Array") do
  P4_H_SUCCESS[:effect_result]["value"]["rows"].is_a?(Array)
end

check("H-04: success → rows count == 2 (plan limit == 2, cap limit == 10)") do
  P4_H_SUCCESS[:effect_result]["value"]["rows"].length == 2
end

check("H-05: success → value.source_table == users") do
  P4_H_SUCCESS[:effect_result]["value"]["source_table"] == "users"
end

check("H-06: success → receipt present in effect_result") do
  !P4_H_SUCCESS[:effect_result]["receipt"].nil?
end

check("H-07: success → effect_obs present in result") do
  !P4_H_SUCCESS[:effect_obs].nil?
end

check("H-08: success → effect_obs.kind == platform_observation") do
  P4_H_SUCCESS[:effect_obs].kind == "platform_observation"
end

puts

# =============================================================================
# Section I: G4 row limit clamping
# =============================================================================
puts "I: G4 row limit clamping"

check("I-01: no-clamp path → outcome == succeeded") do
  P4_I_NOCLAMP[:effect_result]["outcome"] == "succeeded"
end

check("I-02: no-clamp path → row_limit_clamped == false (plan_limit=2 <= cap_limit=100)") do
  P4_I_NOCLAMP[:effect_result]["value"]["row_limit_clamped"] == false
end

check("I-03: no-clamp path → effective_limit == 2") do
  P4_I_NOCLAMP[:effect_result]["value"]["effective_limit"] == 2
end

check("I-04: clamp path → outcome == succeeded") do
  P4_I_CLAMP[:effect_result]["outcome"] == "succeeded"
end

check("I-05: clamp path → row_limit_clamped == true (plan_limit=100 > cap_limit=1)") do
  P4_I_CLAMP[:effect_result]["value"]["row_limit_clamped"] == true
end

check("I-06: clamp path → effective_limit == 1 (cap limit wins)") do
  P4_I_CLAMP[:effect_result]["value"]["effective_limit"] == 1
end

puts

# =============================================================================
# Section J: G5 + G6 executor failure paths
# =============================================================================
puts "J: Executor failure paths"

check("J-01: G5 include_all violation → status == ok (dispatch reached executor)") do
  P4_J_G5[:status] == "ok"
end

check("J-02: G5 → outcome == failed (not denied — it is a query_error, not a gate denial)") do
  P4_J_G5[:effect_result]["outcome"] == "failed"
end

check("J-03: G5 → error_kind == query_error") do
  P4_J_G5[:effect_result]["error_kind"] == "query_error"
end

check("J-04: G6 error_trigger → status == ok") do
  P4_J_G6[:status] == "ok"
end

check("J-05: G6 → outcome == failed") do
  P4_J_G6[:effect_result]["outcome"] == "failed"
end

check("J-06: G6 → error_kind == system_error") do
  P4_J_G6[:effect_result]["error_kind"] == "system_error"
end

puts

# =============================================================================
# Section K: Covenant P15 — timed_out and unknown_external_state semantics
# =============================================================================
puts "K: Covenant P15 semantics"

check("K-01: EffectResult.timed_out produces outcome == timed_out") do
  P4_K_TIMED_OUT["outcome"] == "timed_out"
end

check("K-02: EffectResult.unknown_external_state produces outcome == unknown_external_state") do
  P4_K_UES["outcome"] == "unknown_external_state"
end

check("K-03: timed_out → unknown_external_outcome? == true (P15: timed_out = UnknownExternalOutcome)") do
  EffectResult.unknown_external_outcome?(P4_K_TIMED_OUT)
end

check("K-04: unknown_external_state → unknown_external_outcome? == true") do
  EffectResult.unknown_external_outcome?(P4_K_UES)
end

check("K-05: succeeded → unknown_external_outcome? == false") do
  !EffectResult.unknown_external_outcome?(P4_K_SUCCEEDED)
end

check("K-06: denied → unknown_external_outcome? == false") do
  !EffectResult.unknown_external_outcome?(P4_K_DENIED)
end

puts

# =============================================================================
# Section L: Receipt invariants
# =============================================================================
puts "L: Receipt invariants"

check("L-01: succeeded result has receipt in effect_result") do
  !P4_H_SUCCESS[:effect_result]["receipt"].nil?
end

check("L-02: G1 denied result has receipt in effect_result") do
  !P4_G_G1[:effect_result]["receipt"].nil?
end

check("L-03: G5 failed result has receipt in effect_result") do
  !P4_J_G5[:effect_result]["receipt"].nil?
end

check("L-04: G6 failed result has receipt in effect_result") do
  !P4_J_G6[:effect_result]["receipt"].nil?
end

check("L-05: RuntimeRefusal results have no :effect_result (no receipt emitted)") do
  all_refused = [P4_D_RESULT, P4_F_NIL, P4_F_REVOKED, P4_F_EXPIRED, P4_F_FAMILY, P4_E_RESULT]
  all_refused.none? { |r| r.key?(:effect_result) }
end

check("L-06: succeeded receipt outcome == succeeded") do
  P4_H_SUCCESS[:effect_result]["receipt"]["outcome"] == "succeeded"
end

check("L-07: succeeded receipt capability_id matches passport") do
  P4_H_SUCCESS[:effect_result]["receipt"]["capability_id"] == P4_VALID_PASSPORT.capability_id
end

check("L-08: succeeded receipt_id starts with receipt/sha256:") do
  P4_H_SUCCESS[:effect_result]["receipt"]["receipt_id"].start_with?("receipt/sha256:")
end

puts

# =============================================================================
# Section M: Backend observation packets
# =============================================================================
puts "M: Backend observation packets"

check("M-01: M_MACHINE backend has entries before evaluate_effect") do
  P4_M_BEFORE_COUNT > 0
end

check("M-02: evaluate_effect appends exactly 1 entry to backend") do
  P4_M_AFTER_COUNT == P4_M_BEFORE_COUNT + 1
end

check("M-03: M_RESULT status == ok") do
  P4_M_RESULT[:status] == "ok"
end

check("M-04: effect_obs.kind == platform_observation") do
  P4_M_RESULT[:effect_obs].kind == "platform_observation"
end

check("M-05: effect_obs.subject starts with effect://") do
  P4_M_RESULT[:effect_obs].subject.start_with?("effect://")
end

check("M-06: effect_obs payload outcome == succeeded") do
  P4_M_RESULT[:effect_obs].payload["outcome"] == "succeeded"
end

check("M-07: effect_obs payload capability_type == IO.StorageCapability") do
  P4_M_RESULT[:effect_obs].payload["capability_type"] == "IO.StorageCapability"
end

check("M-08: effect_obs payload program_id == io-effect-proof-p4") do
  P4_M_RESULT[:effect_obs].payload["program_id"] == "io-effect-proof-p4"
end

puts

# =============================================================================
# Section N: Unknown contract / effect_name
# =============================================================================
puts "N: Unknown contract / effect_name"

check("N-01: unknown contract_id → status == refused") do
  P4_N_CONTRACT[:status] == "refused"
end

check("N-02: unknown contract_id → reason_code == effect.unknown_contract") do
  P4_N_CONTRACT[:refusal].reason_code == "effect.unknown_contract"
end

check("N-03: unknown contract_id → refusal.contract_ref matches supplied id") do
  P4_N_CONTRACT[:refusal].contract_ref == "contract/nonexistent-v0"
end

check("N-04: unknown effect_name → status == refused") do
  P4_N_EFFECT[:status] == "refused"
end

check("N-05: unknown effect_name → reason_code == effect.unknown_effect_name") do
  P4_N_EFFECT[:refusal].reason_code == "effect.unknown_effect_name"
end

check("N-06: unknown effect_name → detail includes effect_name") do
  P4_N_EFFECT[:refusal].detail.include?("nonexistent_effect")
end

puts

# =============================================================================
# Summary
# =============================================================================
puts "=== RESULTS ==="
puts "PASS: #{PASS.length}"
puts "FAIL: #{FAIL.length}"
puts "TOTAL: #{PASS.length + FAIL.length}"
puts
if FAIL.empty?
  puts "ALL PASS — LAB-IGNITER-LANG-IO-RUNTIME-P4 proof complete"
else
  puts "FAILURES:"
  FAIL.each { |label| puts "  #{label}" }
end
