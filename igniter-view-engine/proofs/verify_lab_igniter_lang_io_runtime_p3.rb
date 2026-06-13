# frozen_string_literal: true
#
# verify_lab_igniter_lang_io_runtime_p3.rb
#
# Proof: LAB-IGNITER-LANG-IO-RUNTIME-P3
# Route: LAB RUNTIME / MOCKED STORAGE EXECUTOR IMPLEMENTATION
# Authority: proof-local only; no real DB / no SQL / no ORM
#            no production runtime claim / no Reference Runtime claim
#
# Requires capability_executor_runtime.rb from igniter-lang/experiments/
# Uses require_relative cross-repo path only.

require "digest"
require "json"
require_relative "../../../igniter-lang/experiments/io_capability_executor/capability_executor_runtime"

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

puts "=== verify_lab_igniter_lang_io_runtime_p3 ==="
puts

# ─── Section A: Module + Constants ────────────────────────────────────────────
puts "A: Module + constants"

check("A-01: CapabilityExecutorRuntime module defined") do
  defined?(CapabilityExecutorRuntime) == "constant"
end

check("A-02: CapabilityPassport Struct defined") do
  CapabilityPassport.is_a?(Class) && CapabilityPassport.ancestors.include?(Struct)
end

check("A-03: EffectReceipt Struct defined") do
  EffectReceipt.is_a?(Class) && EffectReceipt.ancestors.include?(Struct)
end

check("A-04: ExecutionContext Struct defined") do
  ExecutionContext.is_a?(Class) && ExecutionContext.ancestors.include?(Struct)
end

check("A-05: RuntimeRefusal Struct defined") do
  RuntimeRefusal.is_a?(Class) && RuntimeRefusal.ancestors.include?(Struct)
end

check("A-06: EffectResult module defined") do
  defined?(EffectResult) == "constant" && EffectResult.is_a?(Module)
end

check("A-07: CapabilityExecutor module defined") do
  defined?(CapabilityExecutor) == "constant" && CapabilityExecutor.is_a?(Module)
end

check("A-08: CapabilityExecutorRegistry class defined") do
  defined?(CapabilityExecutorRegistry) == "constant" && CapabilityExecutorRegistry.is_a?(Class)
end

check("A-09: StorageCapabilityExecutor class defined") do
  defined?(StorageCapabilityExecutor) == "constant" && StorageCapabilityExecutor.is_a?(Class)
end

check("A-10: EffectResult::OUTCOMES has exactly 7 entries") do
  EffectResult::OUTCOMES.length == 7
end

check("A-11: OUTCOMES contains all 7 required strings") do
  required = %w[succeeded denied failed partial timed_out unknown_external_state cancelled]
  required.all? { |o| EffectResult::OUTCOMES.include?(o) }
end

check("A-12: StorageCapabilityExecutor::MOCKED_ROWS is frozen Array") do
  StorageCapabilityExecutor::MOCKED_ROWS.is_a?(Array) &&
    StorageCapabilityExecutor::MOCKED_ROWS.frozen?
end

check("A-13: MOCKED_ROWS has 3 rows") do
  StorageCapabilityExecutor::MOCKED_ROWS.length == 3
end

puts

# ─── Section B: CapabilityPassport ────────────────────────────────────────────
puts "B: CapabilityPassport"

PASSPORT_FIELDS = %i[capability_id family authority_ref granted_at expires_at revoked family_fields].freeze

PASSPORT_FIELDS.each_with_index do |field, i|
  check("B-#{(i + 1).to_s.rjust(2, '0')}: CapabilityPassport has field :#{field}") do
    CapabilityPassport.members.include?(field)
  end
end

check("B-08: CapabilityPassport#expired? returns false when expires_at is nil") do
  p = CapabilityPassport.new(
    capability_id: "x", family: "storage", authority_ref: "test",
    granted_at: "2026-01-01T00:00:00Z", expires_at: nil, revoked: false, family_fields: {}
  )
  !p.expired?("2026-06-01T00:00:00Z")
end

check("B-09: CapabilityPassport#expired? returns false when not yet expired") do
  p = CapabilityPassport.new(
    capability_id: "x", family: "storage", authority_ref: "test",
    granted_at: "2026-01-01T00:00:00Z", expires_at: "2027-01-01T00:00:00Z",
    revoked: false, family_fields: {}
  )
  !p.expired?("2026-06-01T00:00:00Z")
end

check("B-10: CapabilityPassport#expired? returns true when past expiry") do
  p = CapabilityPassport.new(
    capability_id: "x", family: "storage", authority_ref: "test",
    granted_at: "2026-01-01T00:00:00Z", expires_at: "2025-01-01T00:00:00Z",
    revoked: false, family_fields: {}
  )
  p.expired?("2026-06-01T00:00:00Z")
end

check("B-11: CapabilityPassport#valid_family? returns true on match") do
  p = CapabilityPassport.new(
    capability_id: "x", family: "storage", authority_ref: "test",
    granted_at: "2026-01-01T00:00:00Z", expires_at: nil, revoked: false, family_fields: {}
  )
  p.valid_family?("storage")
end

check("B-12: CapabilityPassport#valid_family? returns false on mismatch") do
  p = CapabilityPassport.new(
    capability_id: "x", family: "storage", authority_ref: "test",
    granted_at: "2026-01-01T00:00:00Z", expires_at: nil, revoked: false, family_fields: {}
  )
  !p.valid_family?("network")
end

puts

# ─── Section C: EffectReceipt ──────────────────────────────────────────────────
puts "C: EffectReceipt"

RECEIPT_FIELDS = %i[
  receipt_id effect_ref program_id contract_ref capability_id family
  authority_ref idempotency_key idempotency_used inputs_hash outcome
  substrate emitted_at evidence_refs
].freeze

RECEIPT_FIELDS.each_with_index do |field, i|
  check("C-#{(i + 1).to_s.rjust(2, '0')}: EffectReceipt has field :#{field}") do
    EffectReceipt.members.include?(field)
  end
end

check("C-15: EffectReceipt has exactly 14 fields") do
  EffectReceipt.members.length == 14
end

check("C-16: EffectReceipt#to_h returns string-keyed Hash") do
  r = EffectReceipt.new(
    receipt_id: "r1", effect_ref: "e1", program_id: "p1", contract_ref: "c1",
    capability_id: "cap1", family: "storage", authority_ref: "auth1",
    idempotency_key: nil, idempotency_used: false, inputs_hash: "sha256:abc",
    outcome: "succeeded", substrate: "storage", emitted_at: "2026-06-13T00:00:00Z",
    evidence_refs: []
  )
  h = r.to_h
  h.is_a?(Hash) && h.keys.all? { |k| k.is_a?(String) }
end

puts

# ─── Section D: RuntimeRefusal ────────────────────────────────────────────────
puts "D: RuntimeRefusal"

REFUSAL_FIELDS = %i[reason_code effect_ref contract_ref detail].freeze

REFUSAL_FIELDS.each_with_index do |field, i|
  check("D-#{(i + 1).to_s.rjust(2, '0')}: RuntimeRefusal has field :#{field}") do
    RuntimeRefusal.members.include?(field)
  end
end

check("D-05: RuntimeRefusal#to_h returns string-keyed Hash") do
  r = RuntimeRefusal.new(
    reason_code: "effect.missing_passport",
    effect_ref: "effect/contracts/read_users/query_users",
    contract_ref: "contracts/read_users",
    detail: "no passport injected"
  )
  h = r.to_h
  h.is_a?(Hash) && h.keys.all? { |k| k.is_a?(String) }
end

check("D-06: RuntimeRefusal is distinct from EffectResult.denied") do
  RuntimeRefusal.is_a?(Class) && !RuntimeRefusal.ancestors.include?(EffectResult)
end

puts

# ─── Section E: EffectResult factory methods ──────────────────────────────────
puts "E: EffectResult factories"

def dummy_receipt
  EffectReceipt.new(
    receipt_id: "test-receipt", effect_ref: "e", program_id: "p", contract_ref: "c",
    capability_id: "cap", family: "storage", authority_ref: "auth",
    idempotency_key: nil, idempotency_used: false, inputs_hash: "sha256:0",
    outcome: "succeeded", substrate: "storage", emitted_at: "2026-06-13T00:00:00Z",
    evidence_refs: []
  )
end

check("E-01: EffectResult.succeeded returns outcome=succeeded") do
  r = EffectResult.succeeded(receipt: dummy_receipt, value: { "rows" => [] })
  r["outcome"] == "succeeded"
end

check("E-02: EffectResult.succeeded includes receipt hash") do
  r = EffectResult.succeeded(receipt: dummy_receipt)
  r["receipt"].is_a?(Hash)
end

check("E-03: EffectResult.denied returns outcome=denied") do
  r = EffectResult.denied(receipt: dummy_receipt, gate: "G1", reason: "source-not-allowed")
  r["outcome"] == "denied"
end

check("E-04: EffectResult.denied includes gate") do
  r = EffectResult.denied(receipt: dummy_receipt, gate: "G2", reason: "read-op-not-in-allowed-ops")
  r["gate"] == "G2"
end

check("E-05: EffectResult.failed returns outcome=failed") do
  r = EffectResult.failed(receipt: dummy_receipt, error_kind: "query_error", message: "fail")
  r["outcome"] == "failed"
end

check("E-06: EffectResult.partial returns outcome=partial") do
  r = EffectResult.partial(receipt: dummy_receipt, completed: [], pending: [])
  r["outcome"] == "partial"
end

check("E-07: EffectResult.timed_out returns outcome=timed_out") do
  r = EffectResult.timed_out(receipt: dummy_receipt, after_ms: 5000)
  r["outcome"] == "timed_out"
end

check("E-08: EffectResult.unknown_external_state returns outcome=unknown_external_state") do
  r = EffectResult.unknown_external_state(receipt: dummy_receipt, sent_at: "2026-06-13T00:00:00Z")
  r["outcome"] == "unknown_external_state"
end

check("E-09: EffectResult.cancelled returns outcome=cancelled") do
  r = EffectResult.cancelled(receipt: dummy_receipt, reason: "operator-cancel")
  r["outcome"] == "cancelled"
end

check("E-10: EffectResult.outcome_of extracts outcome string") do
  r = EffectResult.succeeded(receipt: dummy_receipt)
  EffectResult.outcome_of(r) == "succeeded"
end

check("E-11: EffectResult.denied? returns true for denied") do
  r = EffectResult.denied(receipt: dummy_receipt, gate: "G1", reason: "x")
  EffectResult.denied?(r)
end

check("E-12: EffectResult.denied? returns false for succeeded") do
  r = EffectResult.succeeded(receipt: dummy_receipt)
  !EffectResult.denied?(r)
end

check("E-13: EffectResult.succeeded? returns true for succeeded") do
  r = EffectResult.succeeded(receipt: dummy_receipt)
  EffectResult.succeeded?(r)
end

check("E-14: EffectResult.unknown_external_outcome? returns true for timed_out") do
  r = EffectResult.timed_out(receipt: dummy_receipt, after_ms: 1000)
  EffectResult.unknown_external_outcome?(r)
end

check("E-15: EffectResult.unknown_external_outcome? returns true for unknown_external_state") do
  r = EffectResult.unknown_external_state(receipt: dummy_receipt, sent_at: "2026-06-13T00:00:00Z")
  EffectResult.unknown_external_outcome?(r)
end

check("E-16: EffectResult.unknown_external_outcome? returns false for failed") do
  r = EffectResult.failed(receipt: dummy_receipt, error_kind: "x", message: "y")
  !EffectResult.unknown_external_outcome?(r)
end

puts

# ─── Section F: CapabilityExecutorRegistry ────────────────────────────────────
puts "F: CapabilityExecutorRegistry"

check("F-01: registry#register accepts capability class + executor") do
  reg = CapabilityExecutorRegistry.new
  executor = StorageCapabilityExecutor.new
  reg.register("IO.StorageCapability", executor)
  true
end

check("F-02: registry#supports? returns true after registration") do
  reg = CapabilityExecutorRegistry.new
  executor = StorageCapabilityExecutor.new
  reg.register("IO.StorageCapability", executor)
  reg.supports?("IO.StorageCapability")
end

check("F-03: registry#supports? returns false for unregistered family") do
  reg = CapabilityExecutorRegistry.new
  !reg.supports?("IO.NetworkCapability")
end

check("F-04: registry#fetch returns executor after registration") do
  reg = CapabilityExecutorRegistry.new
  executor = StorageCapabilityExecutor.new
  reg.register("IO.StorageCapability", executor)
  reg.fetch("IO.StorageCapability") == executor
end

check("F-05: registry#fetch returns nil for unregistered family") do
  reg = CapabilityExecutorRegistry.new
  reg.fetch("IO.SomethingElse").nil?
end

check("F-06: registry#registered_families lists registered names") do
  reg = CapabilityExecutorRegistry.new
  reg.register("IO.StorageCapability", StorageCapabilityExecutor.new)
  reg.registered_families.include?("IO.StorageCapability")
end

check("F-07: registry#register returns self (chainable)") do
  reg = CapabilityExecutorRegistry.new
  result = reg.register("IO.StorageCapability", StorageCapabilityExecutor.new)
  result == reg
end

check("F-08: registry is empty on init") do
  reg = CapabilityExecutorRegistry.new
  reg.registered_families.empty?
end

puts

# ─── Section G: StorageCapabilityExecutor interface ───────────────────────────
puts "G: StorageCapabilityExecutor interface"

EXECUTOR = StorageCapabilityExecutor.new

check("G-01: StorageCapabilityExecutor#family_id returns 'storage'") do
  EXECUTOR.family_id == "storage"
end

check("G-02: StorageCapabilityExecutor includes CapabilityExecutor module") do
  StorageCapabilityExecutor.ancestors.include?(CapabilityExecutor)
end

check("G-03: StorageCapabilityExecutor responds to #execute") do
  EXECUTOR.respond_to?(:execute)
end

check("G-04: StorageCapabilityExecutor has 7-arg execute signature") do
  method = EXECUTOR.method(:execute)
  params = method.parameters
  keyword_args = params.select { |type, _| [:key, :keyreq].include?(type) }
  keyword_args.map { |_, name| name }.sort ==
    %i[authority_ref context deadline_ms effect_name idempotency_key inputs passport].sort
end

puts

# ─── Section H: Helpers + receipt generation ──────────────────────────────────
puts "H: receipt generation"

def base_passport(overrides = {})
  CapabilityPassport.new(
    capability_id: "storage-read-users-v0",
    family: "storage",
    authority_ref: "igniter-gov/auth/storage-read-grant",
    granted_at: "2026-06-01T00:00:00Z",
    expires_at: nil,
    revoked: false,
    family_fields: {
      "allowed_sources" => ["users"],
      "allowed_ops"     => ["read"],
      "read_allowed"    => true,
      "row_limit"       => 10,
      "allow_include_all" => false
    }.merge(overrides.fetch(:family_fields, {}))
  ).tap { |p| overrides.delete(:family_fields) }
end

def base_context
  ExecutionContext.new(
    program_id: "igniter-view-engine",
    contract_ref: "contracts/read_users",
    effect_ref: "effect/contracts/read_users/query_users",
    session_id: "test-session-001"
  )
end

def base_plan
  {
    source: { table: "users" },
    limit: 5,
    projection: { include_all: false }
  }
end

check("H-01: successful execute returns receipt with receipt_id") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"].is_a?(Hash) && result["receipt"]["receipt_id"].is_a?(String)
end

check("H-02: receipt_id is content-addressed (sha256 prefix)") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["receipt_id"].start_with?("receipt/sha256:")
end

check("H-03: inputs_hash has sha256: prefix") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["inputs_hash"].start_with?("sha256:")
end

check("H-04: receipt emitted_at is fixed proof-local timestamp") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["emitted_at"] == StorageCapabilityExecutor::PROOF_LOCAL_TIMESTAMP
end

check("H-05: receipt substrate is 'storage'") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["substrate"] == "storage"
end

check("H-06: receipt family is 'storage'") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["family"] == "storage"
end

check("H-07: receipt capability_id matches passport") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["capability_id"] == "storage-read-users-v0"
end

check("H-08: receipt evidence_refs is empty Array") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["evidence_refs"] == []
end

puts

# ─── Section I: G1 — source_table allowlist gate ──────────────────────────────
puts "I: G1 — source_table allowlist gate"

check("I-01: G1 passes when source_table in allowed_sources") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

check("I-02: G1 denies when source_table not in allowed_sources") do
  bad_plan = { source: { table: "admin_secrets" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: bad_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "denied" && result["gate"] == "G1"
end

check("I-03: G1 denies with empty allowed_sources (fail-closed)") do
  passport = base_passport(family_fields: { "allowed_sources" => [] })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "denied" && result["gate"] == "G1"
end

check("I-04: G1 denial reason is non-empty string") do
  bad_plan = { source: { table: "illegal" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: bad_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["reason"].is_a?(String) && !result["reason"].empty?
end

check("I-05: G1 denial receipt outcome is 'denied'") do
  bad_plan = { source: { table: "other" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: bad_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["outcome"] == "denied"
end

puts

# ─── Section J: G2 — allowed_ops gate ────────────────────────────────────────
puts "J: G2 — allowed_ops gate"

check("J-01: G2 denies when 'read' not in allowed_ops") do
  passport = base_passport(family_fields: { "allowed_ops" => ["write"] })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "denied" && result["gate"] == "G2"
end

check("J-02: G2 denies when allowed_ops empty") do
  passport = base_passport(family_fields: { "allowed_ops" => [] })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "denied" && result["gate"] == "G2"
end

check("J-03: G2 denial reason non-empty") do
  passport = base_passport(family_fields: { "allowed_ops" => ["write"] })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["reason"].is_a?(String) && !result["reason"].empty?
end

check("J-04: G2 passes when allowed_ops includes 'read'") do
  passport = base_passport(family_fields: { "allowed_ops" => ["read", "list"] })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

puts

# ─── Section K: G3 — read_allowed master gate ─────────────────────────────────
puts "K: G3 — read_allowed master gate"

check("K-01: G3 denies when read_allowed=false") do
  passport = base_passport(family_fields: { "read_allowed" => false })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "denied" && result["gate"] == "G3"
end

check("K-02: G3 denial has gate='G3'") do
  passport = base_passport(family_fields: { "read_allowed" => false })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["gate"] == "G3"
end

check("K-03: G3 passes when read_allowed=true (baseline)") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

puts

# ─── Section L: G4 — row limit clamp ─────────────────────────────────────────
puts "L: G4 — row limit clamp"

check("L-01: rows clamped to row_limit when plan_limit exceeds it") do
  passport = base_passport(family_fields: { "row_limit" => 2 })
  plan = { source: { table: "users" }, limit: 10, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["count"] <= 2
end

check("L-02: clamped flag is true when plan_limit > row_limit") do
  passport = base_passport(family_fields: { "row_limit" => 1 })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["row_limit_clamped"] == true
end

check("L-03: clamped flag is false when plan_limit <= row_limit") do
  passport = base_passport(family_fields: { "row_limit" => 10 })
  plan = { source: { table: "users" }, limit: 3, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["row_limit_clamped"] == false
end

check("L-04: G4 clamp is not a denial (outcome=succeeded)") do
  passport = base_passport(family_fields: { "row_limit" => 1 })
  plan = { source: { table: "users" }, limit: 50, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

check("L-05: effective_limit in value matches clamped limit") do
  passport = base_passport(family_fields: { "row_limit" => 2 })
  plan = { source: { table: "users" }, limit: 50, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["effective_limit"] == 2
end

puts

# ─── Section M: G5 — include_all policy gate ──────────────────────────────────
puts "M: G5 — include_all policy gate"

check("M-01: G5 fails when include_all=true and allow_include_all=false") do
  passport = base_passport(family_fields: { "allow_include_all" => false })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: true } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "failed" && result["error_kind"] == "query_error"
end

check("M-02: G5 failure is not denial (not 'denied')") do
  passport = base_passport(family_fields: { "allow_include_all" => false })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: true } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] != "denied"
end

check("M-03: G5 passes when include_all=false") do
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

check("M-04: G5 passes when include_all=true and allow_include_all=true") do
  passport = base_passport(family_fields: { "allow_include_all" => true })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: true } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "succeeded"
end

check("M-05: G5 error_kind is 'query_error' (not 'denied')") do
  passport = base_passport(family_fields: { "allow_include_all" => false })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: true } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["error_kind"] == "query_error"
end

puts

# ─── Section N: G6 — mocked execution ────────────────────────────────────────
puts "N: G6 — mocked execution"

check("N-01: G6 returns mocked rows on success") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["rows"].is_a?(Array)
end

check("N-02: G6 value includes count key") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"].key?("count")
end

check("N-03: G6 value includes source_table key") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["source_table"] == "users"
end

check("N-04: G6 value kind is 'rows' when rows returned") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["kind"] == "rows"
end

check("N-05: G6 value kind is 'empty' when limit=0") do
  plan = { source: { table: "users" }, limit: 0, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["value"]["kind"] == "empty"
end

check("N-06: G6 returns system_error on error_trigger plan") do
  plan = { kind: "error_trigger", source: { table: "users" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["outcome"] == "failed" && result["error_kind"] == "system_error"
end

check("N-07: G6 rows only from MOCKED_ROWS (no DB access)") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  rows = result["value"]["rows"]
  rows.all? { |r| StorageCapabilityExecutor::MOCKED_ROWS.include?(r) }
end

check("N-08: G6 receipts exist on all 3 MOCKED_ROWS names") do
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport,
    inputs: { plan: { source: { table: "users" }, limit: 100, projection: { include_all: false } } },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  names = result["value"]["rows"].map { |r| r["name"] }
  (names & ["Alice", "Bob", "Carol"]).length == 3
end

puts

# ─── Section O: denial-as-data vs RuntimeRefusal boundary ─────────────────────
puts "O: denial-as-data vs RuntimeRefusal boundary"

check("O-01: G1 denial returns EffectResult Hash (not RuntimeRefusal)") do
  bad_plan = { source: { table: "not_allowed" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: bad_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result.is_a?(Hash) && result.key?("outcome") && !result.is_a?(RuntimeRefusal)
end

check("O-02: G1 denial includes receipt (evidence always emitted)") do
  bad_plan = { source: { table: "not_allowed" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: bad_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"].is_a?(Hash)
end

check("O-03: RuntimeRefusal is a separate Struct class") do
  RuntimeRefusal.is_a?(Class) && RuntimeRefusal.ancestors.include?(Struct)
end

check("O-04: RuntimeRefusal can be constructed without executing") do
  r = RuntimeRefusal.new(
    reason_code: "effect.missing_passport",
    effect_ref: "effect/contracts/read_users/query_users",
    contract_ref: "contracts/read_users",
    detail: "no passport"
  )
  r.reason_code == "effect.missing_passport"
end

check("O-05: RuntimeRefusal.to_h returns string-keyed Hash") do
  r = RuntimeRefusal.new(
    reason_code: "effect.expired_passport",
    effect_ref: "effect/c/e",
    contract_ref: "c",
    detail: "expired"
  )
  h = r.to_h
  h.is_a?(Hash) && h.keys.all? { |k| k.is_a?(String) }
end

check("O-06: denial outcome does NOT raise exception") do
  bad_plan = { source: { table: "forbidden" }, limit: 5, projection: { include_all: false } }
  raised = false
  begin
    EXECUTOR.execute(
      context: base_context, effect_name: "query_users",
      passport: base_passport, inputs: { plan: bad_plan },
      authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
    )
  rescue => _
    raised = true
  end
  !raised
end

puts

# ─── Section P: Covenant P15 + outcome semantics ─────────────────────────────
puts "P: Covenant P15 + outcome semantics"

check("P-01: timed_out is unknown_external_outcome (not failed)") do
  r = EffectResult.timed_out(receipt: dummy_receipt, after_ms: 3000)
  EffectResult.unknown_external_outcome?(r) && r["outcome"] != "failed"
end

check("P-02: unknown_external_state is unknown_external_outcome") do
  r = EffectResult.unknown_external_state(receipt: dummy_receipt, sent_at: "2026-06-13T00:00:00Z")
  EffectResult.unknown_external_outcome?(r)
end

check("P-03: failed is NOT unknown_external_outcome") do
  r = EffectResult.failed(receipt: dummy_receipt, error_kind: "system_error", message: "x")
  !EffectResult.unknown_external_outcome?(r)
end

check("P-04: denied is NOT unknown_external_outcome") do
  r = EffectResult.denied(receipt: dummy_receipt, gate: "G1", reason: "x")
  !EffectResult.unknown_external_outcome?(r)
end

check("P-05: all 7 outcomes in EffectResult::OUTCOMES are distinct") do
  EffectResult::OUTCOMES.uniq.length == 7
end

check("P-06: timed_out result includes after_ms field") do
  r = EffectResult.timed_out(receipt: dummy_receipt, after_ms: 5000)
  r["after_ms"] == 5000
end

check("P-07: unknown_external_state includes sent_at field") do
  r = EffectResult.unknown_external_state(receipt: dummy_receipt, sent_at: "2026-06-13T00:00:00Z")
  r["sent_at"] == "2026-06-13T00:00:00Z"
end

check("P-08: receipt always present on G3 denial") do
  passport = base_passport(family_fields: { "read_allowed" => false })
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: base_plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"].is_a?(Hash) && !result["receipt"]["receipt_id"].nil?
end

check("P-09: receipt outcome on G5 failure is 'failed'") do
  passport = base_passport(family_fields: { "allow_include_all" => false })
  plan = { source: { table: "users" }, limit: 5, projection: { include_all: true } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["outcome"] == "failed"
end

check("P-10: receipt outcome on G6 system_error is 'failed'") do
  plan = { kind: "error_trigger", source: { table: "users" }, limit: 5, projection: { include_all: false } }
  result = EXECUTOR.execute(
    context: base_context, effect_name: "query_users",
    passport: base_passport, inputs: { plan: plan },
    authority_ref: "auth", idempotency_key: nil, deadline_ms: 5000
  )
  result["receipt"]["outcome"] == "failed"
end

puts

# ─── Summary ──────────────────────────────────────────────────────────────────

total = PASS.length + FAIL.length
puts "=== SUMMARY ==="
puts "PASS: #{PASS.length}/#{total}"
puts "FAIL: #{FAIL.length}/#{total}"
puts
if FAIL.empty?
  puts "ALL CHECKS PASSED"
else
  puts "FAILING:"
  FAIL.each { |f| puts "  - #{f}" }
  exit 1
end
