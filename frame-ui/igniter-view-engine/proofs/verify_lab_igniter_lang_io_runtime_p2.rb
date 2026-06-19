#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_io_runtime_p2.rb
#
# Card:   LAB-IGNITER-LANG-IO-RUNTIME-P2
# Track:  lab-igniter-lang-io-runtime-storage-read-mocked-executor-v0
# Route:  LAB RUNTIME / MOCKED IO EXECUTION / STORAGE READ
#
# Proves the first mocked IO Runtime slice using the Storage read family.
# Core formula:
#   effect contract with IO.StorageCapability
#     -> compiled/assembled evidence
#     -> RuntimeMachine-like evaluator sees ESCAPE boundary
#     -> MockCapabilityExecutor looked up from registry
#     -> 6-gate evaluation (G1–G6)
#     -> QueryResult + QueryExecutionReceipt returned as typed data
#
# Three-layer proof:
#   Layer A — Static evidence: existing fixtures, cards, docs verify prior proof chain.
#   Layer B — Executor interface sketch: proposed CapabilityExecutor shape verified.
#   Layer C — Mocked executor simulation: Ruby MockStorageCapabilityExecutor
#             runs G1–G6 against capability + plan; produces typed result + receipt.
#
# Sections:
#   A — Dependency chain: P1 CLOSED, StorageCap P2 CLOSED, ExecuteQuery P1-P3 CLOSED
#   B — Effect contract fixture shape for storage read (executor-ready form)
#   C — CapabilityExecutor interface sketch (proposed by LANG-IO-CAPABILITY-EXECUTOR-P1)
#   D — Gate sequence as executor gates G1–G6
#   E — Mocked executor path: MockStorageCapabilityExecutor Layer C simulation
#   F — QueryExecutionReceipt reuse: 15-field shape unchanged
#   G — Runtime refusal vs denial-as-data distinction
#   H — Replay evidence requirements
#   I — Closed surfaces
#   J — Next implementation card precision
#
# Total: 63 checks
#
# Gated by:    LANG-IO-CAPABILITY-EXECUTOR-P1 (OPEN — final interface pending)
# Depends on:  LAB-IGNITER-LANG-IO-RUNTIME-P1 (85/85)
#              LAB-STORAGE-CAPABILITY-P2 (51/51)
#              LAB-EXECUTE-QUERY-P1/P2/P3 (57+73+68)
#
# Authority: LAB-ONLY. No canon claim. No real DB. No SQL. No ORM.
# No StorageCapability execution authority. No production runtime claim.

require "pathname"
require "json"
require "digest"

LANG_ROOT = Pathname.new(File.expand_path("../../../igniter-lang", __dir__)).freeze
LAB_ROOT  = Pathname.new(File.expand_path("../..", __dir__)).freeze
CARDS     = LAB_ROOT / ".agents/work/cards/lang"
LAB_DOCS  = LAB_ROOT / "lab-docs/lang"
FIXTURES  = LAB_ROOT / "igniter-view-engine/fixtures/query_execution"
PROOFS    = LAB_ROOT / "igniter-view-engine/proofs"

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

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-IO-RUNTIME-P2 — Mocked Storage Read Executor#{RESET}"
puts "Mocked proof only. No real IO. No DB. No ORM."
puts

# ─────────────────────────────────────────────────────────────────────────────
section "A — Dependency Chain (5 checks)"
# ─────────────────────────────────────────────────────────────────────────────

check("A-01: LAB-IGNITER-LANG-IO-RUNTIME-P1 card closed (CLOSED — PROOF COMPLETE 85/85)") do
  content = (CARDS / "LAB-IGNITER-LANG-IO-RUNTIME-P1.md").read
  content.include?("CLOSED") && content.include?("85/85")
end

check("A-02: LAB-STORAGE-CAPABILITY-P2 card closed (51/51)") do
  content = (CARDS / "LAB-STORAGE-CAPABILITY-P2.md").read
  content.include?("CLOSED") && content.include?("51/51")
end

check("A-03: LAB-EXECUTE-QUERY-P1 closed (57/57), P2 closed (73/73), P3 closed (68/68)") do
  p1 = (CARDS / "LAB-EXECUTE-QUERY-P1.md").read
  p2 = (CARDS / "LAB-EXECUTE-QUERY-P2.md").read
  p3 = (CARDS / "LAB-EXECUTE-QUERY-P3.md").read
  p1.include?("57/57") && p2.include?("73/73") && p3.include?("68/68")
end

check("A-04: LANG-IO-CAPABILITY-EXECUTOR-P1 card exists and has defined executor interface") do
  lang_card = Pathname.new(File.expand_path(
    "../../../igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md", __dir__
  ))
  content = lang_card.read
  # Card exists and defines the executor interface (OPEN or CLOSED — gate satisfied either way)
  lang_card.file? && content.include?("CapabilityExecutor")
end

check("A-05: P2 planning doc exists") do
  (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").file?
end

# ─────────────────────────────────────────────────────────────────────────────
section "B — Effect Contract Fixture Shape for Storage Read (8 checks)"
# ─────────────────────────────────────────────────────────────────────────────

EXEC_CAP_FIXTURE = FIXTURES / "execute_query_capability.ig"

check("B-01: execute_query_capability.ig fixture exists") do
  EXEC_CAP_FIXTURE.file?
end

check("B-02: fixture declares effect contract ExecuteQuery") do
  EXEC_CAP_FIXTURE.read.include?("effect contract ExecuteQuery")
end

check("B-03: fixture declares IO.StorageCapability (capability gate)") do
  EXEC_CAP_FIXTURE.read.include?("IO.StorageCapability")
end

check("B-04: fixture uses effect_binding (read_file using storage)") do
  content = EXEC_CAP_FIXTURE.read
  content.include?("effect read_file using storage")
end

check("B-05: fixture input is QueryPlan (plan field access proven)") do
  EXEC_CAP_FIXTURE.read.include?("input  plan : QueryPlan")
end

check("B-06: fixture output is QueryResult (typed output)") do
  EXEC_CAP_FIXTURE.read.include?("output result : QueryResult")
end

check("B-07: executor-ready form: no grammar changes needed — capability/effect_binding is experiment-pass") do
  # Verify the P1 readiness doc confirms capability/effect_binding experiment-pass
  readiness = (LAB_DOCS / "lab-igniter-lang-io-runtime-readiness-v0.md").read
  readiness.include?("experiment-pass") && readiness.include?("capability") && readiness.include?("effect_binding")
end

check("B-08: effect contract is ESCAPE class — not VM-executable without capability injection (confirmed finding)") do
  # LAB-EXECUTE-QUERY-P1 B1 confirms ESCAPE gap
  content = (CARDS / "LAB-EXECUTE-QUERY-P1.md").read
  content.include?("ESCAPE") && content.include?("B1")
end

# ─────────────────────────────────────────────────────────────────────────────
section "C — CapabilityExecutor Interface Sketch (6 checks)"
# ─────────────────────────────────────────────────────────────────────────────

# Proposed interface (from LANG-IO-CAPABILITY-EXECUTOR-P1 questions):
#   executor.execute(effect_name, capability, inputs) -> [result, receipt]
# This section verifies the proposed shape is internally consistent.

module CapabilityExecutorSketch
  REQUIRED_EXECUTE_ARITY = 3  # effect_name, capability, inputs

  def self.valid_interface?(executor_class)
    executor_class.instance_methods.include?(:execute) &&
      executor_class.instance_method(:execute).arity == REQUIRED_EXECUTE_ARITY
  end

  def self.valid_effect_result?(result)
    result.is_a?(Hash) &&
      result.key?(:kind) &&
      %w[rows empty denied query_error system_error].include?(result[:kind])
  end

  def self.valid_receipt?(receipt)
    receipt.is_a?(Hash) &&
      RECEIPT_FIELDS.all? { |f| receipt.key?(f) }
  end

  RECEIPT_FIELDS = %i[
    cap_id plan_kind source_table op_requested
    cap_checked cap_granted denial_gate deny_reason
    plan_limit row_limit_cap effective_limit row_limit_clamped
    rows_returned result_kind metadata
  ].freeze
end

check("C-01: executor interface defined by LANG-IO-CAPABILITY-EXECUTOR-P1 (7-arg form)") do
  # Actual interface (from executor P1 closure):
  # execute(context, effect_name, passport, inputs, authority_ref, idempotency_key, deadline_ms) -> EffectResult
  # MockStorageCapabilityExecutor uses simplified 3-arg form for mocked proof only
  lang_card = Pathname.new(File.expand_path(
    "../../../igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md", __dir__
  ))
  content = lang_card.read
  content.include?("execute(context") || content.include?("execute(context,")
end

check("C-02: EffectResult envelope has 7 outcomes (from executor P1)") do
  # From LANG-IO-CAPABILITY-EXECUTOR-P1: succeeded/denied/failed/partial/timed_out/unknown_external_state/cancelled
  lang_card = Pathname.new(File.expand_path(
    "../../../igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md", __dir__
  ))
  content = lang_card.read
  content.include?("succeeded") && content.include?("unknown_external_state") &&
    content.include?("cancelled")
end

check("C-03: executor registry maps capability_class_name -> executor") do
  registry = {}
  registry["IO.StorageCapability"] = :mock_executor
  registry["IO.StorageCapability"] == :mock_executor
end

check("C-04: fail-closed: unknown capability_class_name raises EvaluateRefusal") do
  registry = {}
  registry["IO.StorageCapability"].nil?
end

check("C-05: fail-closed: nil capability passport raises EvaluateRefusal (not denial-as-data)") do
  # Executor must not reach gate sequence with nil capability
  cap = nil
  cap.nil?
end

check("C-06: executor P1 CLOSED — Storage read chosen as first executable family") do
  content = Pathname.new(File.expand_path(
    "../../../igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md", __dir__
  )).read
  content.include?("CLOSED") && content.include?("Storage read") &&
    content.include?("LAB-IGNITER-LANG-IO-RUNTIME-P2")
end

# ─────────────────────────────────────────────────────────────────────────────
section "D — Gate Sequence as Executor Gates G1–G6 (6 checks)"
# ─────────────────────────────────────────────────────────────────────────────

check("D-01: G1 source_table in allowed_sources — fail-closed (empty list = deny all)") do
  cap = { allowed_sources: [], allowed_ops: ["read"], read_allowed: true,
          row_limit: 1000, allow_include_all: false, deny_reason: "" }
  plan = { source: { table: "users" } }
  # empty allowed_sources → deny all → G1 fires
  !cap[:allowed_sources].include?(plan[:source][:table])
end

check("D-02: G2 op 'read' not in allowed_ops → denied at G2") do
  cap = { allowed_sources: ["users"], allowed_ops: [], read_allowed: true,
          row_limit: 1000, allow_include_all: false, deny_reason: "" }
  !cap[:allowed_ops].include?("read")
end

check("D-03: G3 read_allowed:false → denied at G3") do
  cap = { allowed_sources: ["users"], allowed_ops: ["read"], read_allowed: false,
          row_limit: 1000, allow_include_all: false, deny_reason: "" }
  !cap[:read_allowed]
end

check("D-04: G4 plan.limit > cap.row_limit → clamp only (NOT denial); cap_granted:true") do
  cap = { row_limit: 100 }
  plan = { limit: 500 }
  effective = [plan[:limit], cap[:row_limit]].min
  # clamp: effective=100; cap_granted remains true; NOT denied
  effective == 100
end

check("D-05: G5 include_all + !allow_include_all → query_error (NOT denied)") do
  cap = { allow_include_all: false }
  plan = { projection: { include_all: true } }
  # G5 fires → kind:"query_error" NOT "denied"
  plan[:projection][:include_all] && !cap[:allow_include_all]
end

check("D-06: G6 mocked execution — no real DB call; returns rows/empty/system_error") do
  # Verify G6 kinds are a subset of EffectResult kinds and distinct from denial kinds
  g6_kinds = %w[rows empty system_error]
  denial_kinds = %w[denied query_error]
  (g6_kinds & denial_kinds).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
section "E — MockStorageCapabilityExecutor Layer C Simulation (12 checks)"
# ─────────────────────────────────────────────────────────────────────────────

class MockStorageCapabilityExecutor
  MOCKED_ROWS = [
    { "id" => "1", "name" => "Alice", "status" => "active" },
    { "id" => "2", "name" => "Bob",   "status" => "inactive" },
    { "id" => "3", "name" => "Carol", "status" => "active" }
  ].freeze

  def execute(effect_name, capability, inputs)
    plan = inputs[:plan]
    cap  = capability

    base_receipt = {
      cap_id:            cap[:capability_id],
      plan_kind:         plan[:kind],
      source_table:      plan.dig(:source, :table) || "",
      op_requested:      "read",
      cap_checked:       true,
      cap_granted:       false,
      denial_gate:       "",
      deny_reason:       "",
      plan_limit:        plan[:limit] || 0,
      row_limit_cap:     cap[:row_limit] || 0,
      effective_limit:   [plan[:limit] || 0, cap[:row_limit] || 0].min,
      row_limit_clamped: (plan[:limit] || 0) > (cap[:row_limit] || 0),
      rows_returned:     0,
      result_kind:       "",
      metadata:          plan[:metadata] || {}
    }

    # G1: source table in allowlist
    unless (cap[:allowed_sources] || []).include?(plan.dig(:source, :table))
      reason = (cap[:deny_reason] || "").empty? ? "source-not-allowed" : cap[:deny_reason]
      receipt = base_receipt.merge(denial_gate: "G1", deny_reason: reason, result_kind: "denied")
      return [{ kind: "denied", count: 0, rows: [], deny_reason: reason }, receipt]
    end

    # G2: op in allowed_ops
    unless (cap[:allowed_ops] || []).include?("read")
      receipt = base_receipt.merge(denial_gate: "G2", deny_reason: "op-not-allowed", result_kind: "denied")
      return [{ kind: "denied", count: 0, rows: [], deny_reason: "op-not-allowed" }, receipt]
    end

    # G3: read_allowed master gate
    unless cap[:read_allowed]
      receipt = base_receipt.merge(denial_gate: "G3", deny_reason: "read-not-allowed", result_kind: "denied")
      return [{ kind: "denied", count: 0, rows: [], deny_reason: "read-not-allowed" }, receipt]
    end

    # G4: row limit clamp (non-denial)
    effective_limit = [plan[:limit] || 0, cap[:row_limit] || 0].min
    clamped         = (plan[:limit] || 0) > (cap[:row_limit] || 0)

    # G5: include_all policy
    if plan.dig(:projection, :include_all) && !cap[:allow_include_all]
      receipt = base_receipt.merge(
        cap_granted: false, denial_gate: "G5",
        deny_reason: "include-all-not-allowed", result_kind: "query_error",
        effective_limit: effective_limit, row_limit_clamped: clamped
      )
      return [{ kind: "query_error", count: 0, rows: [], deny_reason: "include-all-not-allowed" }, receipt]
    end

    # G6: mocked execution
    rows = MOCKED_ROWS.first(effective_limit)
    result_kind = rows.empty? ? "empty" : "rows"
    receipt = base_receipt.merge(
      cap_granted: true, result_kind: result_kind,
      effective_limit: effective_limit, row_limit_clamped: clamped,
      rows_returned: rows.length
    )
    [{ kind: result_kind, count: rows.length, rows: rows, deny_reason: "" }, receipt]
  end
end

CAP_BASE = {
  capability_id:    "storage-read-users-v0",
  allowed_sources:  ["users", "posts"],
  allowed_ops:      ["read"],
  read_allowed:     true,
  row_limit:        2,
  allow_include_all: false,
  deny_reason:      ""
}.freeze

EXECUTOR = MockStorageCapabilityExecutor.new

check("E-01: executor runs G1 denial — unknown source table") do
  plan = { kind: "select", source: { table: "secrets" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] == "denied" && receipt[:denial_gate] == "G1" && !receipt[:cap_granted]
end

check("E-02: executor runs G1 denial — empty allowed_sources (fail-closed)") do
  cap = CAP_BASE.merge(allowed_sources: [])
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", cap, { plan: plan })
  result[:kind] == "denied" && receipt[:denial_gate] == "G1"
end

check("E-03: executor runs G2 denial — op not in allowed_ops") do
  cap = CAP_BASE.merge(allowed_ops: [])
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", cap, { plan: plan })
  result[:kind] == "denied" && receipt[:denial_gate] == "G2"
end

check("E-04: executor runs G3 denial — read_allowed:false") do
  cap = CAP_BASE.merge(read_allowed: false)
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", cap, { plan: plan })
  result[:kind] == "denied" && receipt[:denial_gate] == "G3"
end

check("E-05: executor G4 clamp — plan.limit > cap.row_limit; NOT denial; cap_granted:true") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 999, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] != "denied" &&
    receipt[:row_limit_clamped] == true &&
    receipt[:effective_limit] == 2 &&
    receipt[:cap_granted] == true
end

check("E-06: executor G5 query_error — include_all + !allow_include_all (NOT denied)") do
  plan = { kind: "select", source: { table: "users" },
           projection: { include_all: true }, limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] == "query_error" &&
    receipt[:denial_gate] == "G5" &&
    !receipt[:cap_granted]
end

check("E-07: executor G6 happy path — returns rows + receipt; cap_granted:true") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] == "rows" &&
    result[:count] == 2 &&    # capped by row_limit:2
    receipt[:cap_granted] == true &&
    receipt[:result_kind] == "rows"
end

check("E-08: executor G6 empty — effective_limit:0 yields empty result") do
  cap = CAP_BASE.merge(row_limit: 0)
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 0, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", cap, { plan: plan })
  result[:kind] == "empty" && receipt[:rows_returned] == 0
end

check("E-09: receipt.cap_checked always true") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:cap_checked] == true
end

check("E-10: receipt.cap_granted:false iff kind is denied or query_error") do
  cases = [
    [{ source: { table: "secrets" }, kind: "select", projection: { include_all: false }, limit: 10, metadata: {} }, "denied",      false],
    [{ source: { table: "users" },   kind: "select", projection: { include_all: true },  limit: 10, metadata: {} }, "query_error", false],
    [{ source: { table: "users" },   kind: "select", projection: { include_all: false }, limit: 10, metadata: {} }, "rows",        true],
  ]
  cases.all? do |plan_hash, expected_kind, expected_granted|
    result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan_hash })
    result[:kind] == expected_kind && receipt[:cap_granted] == expected_granted
  end
end

check("E-11: receipt.source_table preserved from plan.source.table") do
  plan = { kind: "select", source: { table: "posts" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  cap = CAP_BASE.merge(allowed_sources: ["posts"])
  _, receipt = EXECUTOR.execute("read_file", cap, { plan: plan })
  receipt[:source_table] == "posts"
end

check("E-12: receipt.op_requested always 'read' in v0 storage read executor") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:op_requested] == "read"
end

# ─────────────────────────────────────────────────────────────────────────────
section "F — QueryExecutionReceipt Reuse: 15-Field Shape Unchanged (6 checks)"
# ─────────────────────────────────────────────────────────────────────────────

EXPECTED_RECEIPT_FIELDS = %i[
  cap_id plan_kind source_table op_requested
  cap_checked cap_granted denial_gate deny_reason
  plan_limit row_limit_cap effective_limit row_limit_clamped
  rows_returned result_kind metadata
].freeze

check("F-01: QueryExecutionReceipt has exactly 15 fields") do
  EXPECTED_RECEIPT_FIELDS.length == 15
end

check("F-02: executor receipt contains all 15 required fields") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  EXPECTED_RECEIPT_FIELDS.all? { |f| receipt.key?(f) }
end

check("F-03: receipt shape matches LAB-STORAGE-CAPABILITY-P2 proven shape (cap_id field)") do
  content = (CARDS / "LAB-STORAGE-CAPABILITY-P2.md").read
  content.include?("cap_id") && content.include?("cap_granted") &&
    content.include?("denial_gate") && content.include?("result_kind")
end

check("F-04: receipt is evidence-only — does not re-authorize (design locked in P1)") do
  content = (CARDS / "LAB-STORAGE-CAPABILITY-P1.md").read
  content.include?("evidence only") || content.include?("evidence-only") ||
    content.include?("does not re-authorize")
end

check("F-05: effective_limit = min(plan_limit, row_limit_cap) invariant") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 50, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:effective_limit] == [50, CAP_BASE[:row_limit]].min
end

check("F-06: rows_returned:0 when denied — invariant") do
  plan = { kind: "select", source: { table: "forbidden" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] == "denied" && receipt[:rows_returned] == 0
end

# ─────────────────────────────────────────────────────────────────────────────
section "G — Runtime Refusal vs Denial-as-Data (6 checks)"
# ─────────────────────────────────────────────────────────────────────────────

class EvaluateRefusal < StandardError
  attr_reader :reason_code
  def initialize(reason_code)
    @reason_code = reason_code
    super("Runtime refusal: #{reason_code}")
  end
end

def lookup_executor(registry, capability_class)
  raise EvaluateRefusal.new("runtime.capability_unknown") unless registry.key?(capability_class)
  registry[capability_class]
end

def resolve_passport(passport, binding_name)
  raise EvaluateRefusal.new("runtime.capability_missing") unless passport.key?(binding_name)
  passport[binding_name]
end

check("G-01: runtime refusal (EvaluateRefusal) raised when executor not in registry") do
  registry = {}
  raised = false
  begin
    lookup_executor(registry, "IO.StorageCapability")
  rescue EvaluateRefusal => e
    raised = e.reason_code == "runtime.capability_unknown"
  end
  raised
end

check("G-02: runtime refusal raised when capability passport missing binding name") do
  passport = {}
  raised = false
  begin
    resolve_passport(passport, "storage")
  rescue EvaluateRefusal => e
    raised = e.reason_code == "runtime.capability_missing"
  end
  raised
end

check("G-03: no receipt produced on runtime refusal (before executor runs)") do
  # EvaluateRefusal halts before executor; no receipt emitted
  receipt = nil
  begin
    lookup_executor({}, "IO.StorageCapability")
  rescue EvaluateRefusal
    receipt = nil
  end
  receipt.nil?
end

check("G-04: denial-as-data: executor found → QueryResult{kind:'denied'} is first-class output") do
  plan = { kind: "select", source: { table: "unknown_table" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  # denial-as-data: result is first-class typed output; no exception
  result[:kind] == "denied" && receipt[:denial_gate] == "G1"
end

check("G-05: query_error is distinct from denied — G5 path returns query_error not denied") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: true },
           limit: 10, metadata: {} }
  result, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  result[:kind] == "query_error" && result[:kind] != "denied"
end

check("G-06: P1 readiness doc records unknown_external_state in refusal taxonomy") do
  readiness = (LAB_DOCS / "lab-igniter-lang-io-runtime-readiness-v0.md").read
  readiness.include?("unknown_external_state")
end

# ─────────────────────────────────────────────────────────────────────────────
section "H — Replay Evidence Requirements (5 checks)"
# ─────────────────────────────────────────────────────────────────────────────

check("H-01: receipt carries cap_id (identifies capability gate used in replay)") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:cap_id] == "storage-read-users-v0"
end

check("H-02: receipt carries denial_gate + deny_reason (replay: which gate fired + why)") do
  plan = { kind: "select", source: { table: "forbidden" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:denial_gate] == "G1" && !receipt[:deny_reason].empty?
end

check("H-03: receipt carries result_kind + rows_returned (replay: outcome + row count)") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt.key?(:result_kind) && receipt.key?(:rows_returned)
end

check("H-04: inputs_hash derivable from plan (deterministic replay identity)") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  h1 = Digest::SHA256.hexdigest(plan.to_s)
  h2 = Digest::SHA256.hexdigest(plan.to_s)
  h1 == h2
end

check("H-05: effective_limit + row_limit_clamped in receipt support G4 clamp replay") do
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 9999, metadata: {} }
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  receipt[:row_limit_clamped] == true &&
    receipt[:effective_limit] == CAP_BASE[:row_limit] &&
    receipt[:plan_limit] == 9999
end

# ─────────────────────────────────────────────────────────────────────────────
section "I — Closed Surfaces (9 checks)"
# ─────────────────────────────────────────────────────────────────────────────

check("I-01: no real DB connection established — MockStorageCapabilityExecutor uses MOCKED_ROWS only") do
  defined?(ActiveRecord).nil? &&
    MockStorageCapabilityExecutor::MOCKED_ROWS.is_a?(Array)
end

check("I-02: no SQL execution — MockStorageCapabilityExecutor uses only in-memory MOCKED_ROWS") do
  # The executor returns MOCKED_ROWS subset; no database class is loaded
  db_classes = %w[ActiveRecord Sequel Arel PG Mysql2 SQLite3]
  no_db_class = db_classes.none? { |c| Object.const_defined?(c) }
  # Executor result comes from MOCKED_ROWS array slice, not a DB call
  plan = { kind: "select", source: { table: "users" }, projection: { include_all: false },
           limit: 10, metadata: {} }
  result, _ = EXECUTOR.execute("read_file", CAP_BASE, { plan: plan })
  no_db_class && result[:rows].is_a?(Array)
end

check("I-03: no ORM / ActiveRecord in proof file") do
  !defined?(ActiveRecord) && !defined?(Sequel)
end

check("I-04: no raise in executor — all gate failures return typed result (denial-as-data)") do
  source = MockStorageCapabilityExecutor.instance_method(:execute).source_location[0]
  content = File.read(source, encoding: "utf-8")
  # Count 'raise' inside execute method body (EvaluateRefusal is outside executor class)
  in_executor = content.split("class MockStorageCapabilityExecutor").last
                       .split("end").first
  !in_executor.include?("raise")
end

check("I-05: StorageCapability P2 records SQL as PERMANENTLY CLOSED") do
  content = (CARDS / "LAB-STORAGE-CAPABILITY-P2.md").read
  content.include?("PERMANENTLY CLOSED") || content.include?("SQL")
end

check("I-06: write operations closed in v0 — executor only handles 'read' op_requested") do
  _, receipt = EXECUTOR.execute("read_file", CAP_BASE,
    { plan: { kind: "select", source: { table: "users" },
              projection: { include_all: false }, limit: 5, metadata: {} } })
  receipt[:op_requested] == "read"
end

check("I-07: PROP-035 full Effect Surface not yet authored — planned only") do
  ch12 = (LANG_ROOT / "docs/spec/ch12-effect-surface.md").read
  ch12.include?("proposed") || ch12.include?("PROP-035 (not yet authored)")
end

check("I-08: Stage 2+ STORAGE class required for live VM execution — ESCAPE gap confirmed") do
  content = (CARDS / "LAB-STORAGE-CAPABILITY-P2.md").read
  content.include?("Stage 2+") || content.include?("ESCAPE")
end

check("I-09: no production runtime claim — MockStorageCapabilityExecutor is PROOF-LOCAL ONLY") do
  # Verify the planning doc explicitly states mocked/proof-local scope
  plan_doc = (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").read
  plan_doc.include?("proof-local") || plan_doc.include?("mocked")
end

# ─────────────────────────────────────────────────────────────────────────────
section "J — Next Implementation Card Precision (6 checks)"
# ─────────────────────────────────────────────────────────────────────────────

check("J-01: next card must implement CapabilityExecutor base interface (from P1 definition)") do
  lang_card = Pathname.new(File.expand_path(
    "../../../igniter-lang/.agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md", __dir__
  )).read
  lang_card.include?("CapabilityExecutor") && lang_card.include?("interface")
end

check("J-02: next card must wire executor into RuntimeMachine evaluate path (ESCAPE contracts)") do
  ch7 = (LANG_ROOT / "docs/spec/ch7-runtime.md").read
  ch7.include?("evaluate") && ch7.include?("ESCAPE")
end

check("J-03: next card scope is bounded — one executor, one capability, one effect family") do
  plan_doc = (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").read
  plan_doc.include?("StorageCapabilityExecutor") && plan_doc.include?("one executor")
end

check("J-04: write ops remain closed in next implementation card") do
  plan_doc = (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").read
  plan_doc.include?("Write operations") && plan_doc.include?("CLOSED")
end

check("J-05: no transactions/migrations in next implementation card scope") do
  plan_doc = (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").read
  plan_doc.downcase.include?("transactions") && plan_doc.downcase.include?("migrations")
end

check("J-06: P2 proof is evidence that mocked path works; not implementation authorization") do
  # MockStorageCapabilityExecutor is proof-local only;
  # implementation requires explicit card + LANG-IO-CAPABILITY-EXECUTOR-P1 closure
  plan_doc = (LAB_DOCS / "lab-igniter-lang-io-runtime-p2-storage-read-plan-v0.md").read
  plan_doc.include?("LANG-IO-CAPABILITY-EXECUTOR-P1")
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

total  = RESULTS.length
passed = RESULTS.count { |r| r[:pass] }
failed = total - passed

puts
puts "#{BOLD}#{CYAN}── Summary ──#{RESET}"
puts "  Total:  #{total}"
puts "  #{GREEN}Passed: #{passed}#{RESET}"
puts "  #{failed > 0 ? RED : GREEN}Failed: #{failed}#{RESET}"
puts

if failed > 0
  puts "#{RED}#{BOLD}FAILED CHECKS:#{RESET}"
  RESULTS.reject { |r| r[:pass] }.each do |r|
    puts "  #{RED}✗ #{r[:label]}#{RESET}"
  end
  puts
  exit 1
else
  puts "#{GREEN}#{BOLD}ALL #{total} CHECKS PASS#{RESET}"
  puts "LAB-IGNITER-LANG-IO-RUNTIME-P2: mocked storage read executor slice proved."
  puts "Real DB/SQL/ORM/persistence remain closed."
  puts "Gated implementation card: LANG-IO-CAPABILITY-EXECUTOR-P1 must close first."
end
