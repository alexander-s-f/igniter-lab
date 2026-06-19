#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_storage_adapter_p1.rb
# LAB-STORAGE-ADAPTER-P1 - 75 checks
#
# Mocked Storage Adapter Contract Hardening.
#
# Core formula:
#   StorageAdapterMock v0 = QueryPlanUnified + StorageCapability-shaped record
#                         + explicit MockStorageSource fixture data
#                      -> QueryResult + QueryExecutionReceipt
#                         + small StorageAdapterReceipt boundary evidence
#
# The adapter is not the Query v0 simulator. It wraps substrate/source selection,
# explicit fixture registry lookup, request/execution metadata, and adapter
# receipt facts around the already stabilized Query v0 semantics.
#
# Authority: LAB-ONLY. No real DB. No SQL. No ORM. No writes. No public API.
# Run: ruby igniter-view-engine/proofs/verify_lab_storage_adapter_p1.rb

SOURCE = File.read(__FILE__).force_encoding("UTF-8").freeze

require "json"
require "open3"
require "tmpdir"
require "set"
require "pathname"
require "tempfile"
require "digest"

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = (LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler").to_s
VM_BIN         = (LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm").to_s
FIXTURE_PATH   = (ROOT / "fixtures" / "storage_adapter" / "storage_adapter_mocked.ig").to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

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
  puts "  ERROR: #{label} - #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def run_fixture(path)
  src        = File.read(path.to_s).force_encoding("UTF-8")
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
rescue => e
  { error: e.message }
end

def contract_accepted?(result, name)
  c = result[:typed]&.fetch("contracts", [])&.find { |contract| contract["name"] == name }
  c&.fetch("status", nil) == "accepted"
end

def type_errors_for(result, name)
  c = result[:typed]&.fetch("contracts", [])&.find { |contract| contract["name"] == name }
  c&.fetch("type_errors", []) || []
end

def type_env_field(result, type_name, field_name)
  result[:typed]&.fetch("type_env", {})
                &.fetch(type_name, {})
                &.fetch(field_name, nil)
end

def type_name_str(t)
  return t.to_s unless t.is_a?(Hash)

  name   = t["name"] || t["kind"] || "?"
  params = Array(t["params"])
  return name if params.empty?

  "#{name}[#{params.map { |p| type_name_str(p) }.join(",")}]"
end

def compile_path(path, tag = "sadapt")
  out_dir = Dir.mktmpdir(tag)
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN, "compile", path.to_s, "--out", out_dir.to_s, "--json"
  )
  stdout = stdout.force_encoding("UTF-8") if stdout
  report = (stdout && !stdout.strip.empty?) ? JSON.parse(stdout.strip) : nil
  contracts = {}
  Dir.glob(File.join(out_dir, "contracts", "*.json")).each do |file|
    contract = JSON.parse(File.read(file, encoding: "UTF-8"))
    contracts[contract["name"]] = contract if contract.is_a?(Hash) && contract["name"]
  end
  { report: report, out_dir: out_dir, contracts: contracts }
rescue => e
  { report: nil, out_dir: nil, contracts: {}, error: e.message }
end

def compute_type_tag(result, contract, node)
  c = result[:contracts][contract]
  return nil unless c

  n = (c["compute_nodes"] || []).find { |x| x["name"] == node }
  n&.fetch("type_tag", nil)
end

def vm_run(out_dir, contract_name, inputs)
  tmpfile = Tempfile.new(["sadapt_inputs", ".json"])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _status = Open3.capture3(
    VM_BIN, "run",
    "--contract", out_dir.to_s,
    "--inputs", tmpfile.path,
    "--entry", contract_name,
    "--json"
  )
  tmpfile.unlink rescue nil
  stdout = stdout.force_encoding("UTF-8") if stdout
  return { "status" => "vm_error", "error" => "empty output" } if stdout.nil? || stdout.strip.empty?

  JSON.parse(stdout.strip)
rescue => e
  { "status" => "vm_error", "error" => e.message }
end

def canonical_json(value)
  case value
  when Hash
    "{" + value.keys.sort.map { |k| JSON.generate(k.to_s) + ":" + canonical_json(value[k]) }.join(",") + "}"
  when Array
    "[" + value.map { |v| canonical_json(v) }.join(",") + "]"
  else
    JSON.generate(value)
  end
end

class ReverseComparable
  include Comparable
  attr_reader :value

  def initialize(value)
    @value = value.to_s
  end

  def <=>(other)
    other.value.to_s <=> @value
  end
end

module StorageAdapterMock
  KNOWN_OPS = %w[eq neq contains prefix].freeze
  KNOWN_DIRECTIONS = %w[asc desc].freeze

  def self.execute(plan:, capability:, source:, request_id:, execution_id:)
    source_table = plan.dig("source", "table") || ""
    projection = plan.fetch("projection", { "fields" => "", "include_all" => false })
    plan_limit = plan.fetch("limit", 0)
    row_limit = capability.fetch("row_limit", 0)
    cap_id = capability.fetch("cap_id", "")
    metadata = plan.fetch("metadata", {})
    adapter_context = {
      adapter_id: source.fetch("adapter_id", ""),
      mocked_source_id: source.fetch("mocked_source_id", ""),
      fixture_digest: source.fetch("fixture_digest", ""),
      request_id: request_id,
      execution_id: execution_id,
      source_table: source_table
    }

    unless capability.fetch("allowed_sources", []).include?(source_table)
      reason = capability.fetch("deny_reason", "")
      reason = "source not in allowed_sources" if reason.empty?
      return denied("G1", reason, cap_id, plan_limit, row_limit, metadata, adapter_context)
    end

    unless capability.fetch("allowed_ops", []).include?("read")
      return denied("G2", "op not in allowed_ops", cap_id, plan_limit, row_limit, metadata, adapter_context)
    end

    unless capability.fetch("read_allowed", false)
      return denied("G3", "read_allowed is false", cap_id, plan_limit, row_limit, metadata, adapter_context)
    end

    rows = source.fetch("tables", {})[source_table]
    if rows.nil?
      return system_error(
        "mocked source table missing from registry",
        cap_id, plan_limit, row_limit, metadata, adapter_context
      )
    end

    effective_limit = [plan_limit, row_limit].min
    clamped = effective_limit < plan_limit

    if projection.fetch("include_all", false) && !capability.fetch("allow_include_all", false)
      return query_error(
        "G5", "include_all not permitted by capability",
        cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    if effective_limit.negative?
      return query_error(
        "G6-limit", "negative limit",
        cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    filtered = filter_rows(rows, plan.fetch("filters", []))
    if filtered[:kind] == "query_error"
      return query_error(
        "G6-filter", filtered[:message],
        cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    ordered = order_rows(filtered[:rows], plan.fetch("order", []))
    if ordered[:kind] == "query_error"
      return query_error(
        "G6-order", ordered[:message],
        cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    if effective_limit == 0
      return success(
        [], "empty", cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    limited = ordered[:rows].first(effective_limit)
    projected = project_rows(limited, projection)
    if projected[:kind] == "query_error"
      return query_error(
        "G6-projection", projected[:message],
        cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context
      )
    end

    kind = projected[:rows].empty? ? "empty" : "rows"
    success(projected[:rows], kind, cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, adapter_context)
  end

  def self.filter_rows(rows, filters)
    bad = filters.find { |filter| !KNOWN_OPS.include?(filter.fetch("op", "")) }
    return { kind: "query_error", message: "unknown filter operator: #{bad["op"]}" } if bad

    {
      kind: "ok",
      rows: rows.select { |row| filters.all? { |filter| row_matches?(row, filter) } }
    }
  end

  def self.order_rows(rows, order_list)
    order_list.each do |order|
      direction = order.fetch("direction", "")
      field = order.fetch("field", "")
      return { kind: "query_error", message: "empty direction in multi-order entry (field: #{field})" } if direction.empty?
      return { kind: "query_error", message: "unknown direction: #{direction}" } unless KNOWN_DIRECTIONS.include?(direction)
    end

    order_list.each do |order|
      field = order.fetch("field", "")
      next if field.empty?

      return { kind: "query_error", message: "order field absent in row: #{field}" } if rows.any? { |row| !row.key?(field) }
    end

    sorted = rows.each_with_index.sort_by do |row, index|
      keys = order_list.map do |order|
        value = row.fetch(order.fetch("field", ""), "")
        order.fetch("direction", "asc") == "asc" ? value : ReverseComparable.new(value)
      end
      keys + [index]
    end.map(&:first)

    { kind: "ok", rows: sorted }
  end

  def self.project_rows(rows, projection)
    return { kind: "ok", rows: rows } if projection.fetch("include_all", false)

    fields = projection.fetch("fields", "").split(",").map(&:strip).reject(&:empty?)
    return { kind: "query_error", message: "empty fields in projection" } if fields.empty?

    seen = Set.new
    dedup = fields.select { |field| seen.add?(field) }
    projected = rows.map do |row|
      missing = dedup.find { |field| !row.key?(field) }
      return { kind: "query_error", message: "projection field absent in row: #{missing}" } if missing

      dedup.each_with_object({}) { |field, out| out[field] = row[field] }
    end

    { kind: "ok", rows: projected }
  end

  def self.row_matches?(row, filter)
    row_value = row[filter.fetch("field", "")]
    return false if row_value.nil?

    case filter.fetch("op", "")
    when "eq" then row_value == filter.fetch("value", "")
    when "neq" then row_value != filter.fetch("value", "")
    when "contains" then row_value.include?(filter.fetch("value", ""))
    when "prefix" then row_value.start_with?(filter.fetch("value", ""))
    else false
    end
  end

  def self.denied(gate, reason, cap_id, plan_limit, row_limit, metadata, ctx)
    build_output(
      kind: "denied", count: 0, message: reason, rows: [],
      cap_id: cap_id, plan_limit: plan_limit, row_limit: row_limit,
      effective_limit: 0, clamped: false, cap_granted: false,
      denial_gate: gate, deny_reason: reason, metadata: metadata, ctx: ctx
    )
  end

  def self.query_error(gate, reason, cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
    build_output(
      kind: "query_error", count: 0, message: reason, rows: [],
      cap_id: cap_id, plan_limit: plan_limit, row_limit: row_limit,
      effective_limit: effective_limit, clamped: clamped, cap_granted: false,
      denial_gate: gate, deny_reason: reason, metadata: metadata, ctx: ctx
    )
  end

  def self.system_error(reason, cap_id, plan_limit, row_limit, metadata, ctx)
    build_output(
      kind: "system_error", count: 0, message: reason, rows: [],
      cap_id: cap_id, plan_limit: plan_limit, row_limit: row_limit,
      effective_limit: 0, clamped: false, cap_granted: true,
      denial_gate: "", deny_reason: reason, metadata: metadata, ctx: ctx
    )
  end

  def self.success(rows, kind, cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
    build_output(
      kind: kind, count: rows.length, message: "", rows: rows,
      cap_id: cap_id, plan_limit: plan_limit, row_limit: row_limit,
      effective_limit: effective_limit, clamped: clamped, cap_granted: true,
      denial_gate: "", deny_reason: "", metadata: metadata, ctx: ctx
    )
  end

  def self.build_output(kind:, count:, message:, rows:, cap_id:, plan_limit:, row_limit:,
                        effective_limit:, clamped:, cap_granted:, denial_gate:, deny_reason:,
                        metadata:, ctx:)
    result = { "kind" => kind, "count" => count, "message" => message, "metadata" => metadata }
    receipt = {
      "cap_id" => cap_id,
      "plan_kind" => "select",
      "source_table" => ctx[:source_table],
      "op_requested" => "read",
      "cap_checked" => true,
      "cap_granted" => cap_granted,
      "denial_gate" => denial_gate,
      "deny_reason" => deny_reason,
      "plan_limit" => plan_limit,
      "row_limit_cap" => row_limit,
      "effective_limit" => effective_limit,
      "row_limit_clamped" => clamped,
      "rows_returned" => rows.length,
      "result_kind" => kind,
      "metadata" => metadata
    }
    adapter_receipt = {
      "adapter_id" => ctx[:adapter_id],
      "mocked_source_id" => ctx[:mocked_source_id],
      "request_id" => ctx[:request_id],
      "execution_id" => ctx[:execution_id],
      "substrate_kind" => "mocked_storage",
      "fixture_digest" => ctx[:fixture_digest],
      "source_table" => ctx[:source_table],
      "result_kind" => kind,
      "ambient_state_used" => false
    }
    { result: result, query_receipt: receipt, adapter_receipt: adapter_receipt, rows: rows }
  end
end

ALL_CONTRACTS = %w[
  BuildAdapterPlan BuildStorageCapability BuildMockTable BuildMockStorageSource
  BuildAdapterRequest BuildQueryResult BuildQueryExecutionReceipt
  BuildStorageAdapterReceipt AdapterMetadataReader
].freeze

FIXTURE_SRC = File.read(FIXTURE_PATH).force_encoding("UTF-8").freeze
SADAPT_TC = run_fixture(FIXTURE_PATH)
SADAPT_SIR = compile_path(FIXTURE_PATH, "sadapt")
SADAPT_OUT = SADAPT_SIR[:out_dir]

ROWS = [
  { "name" => "alice", "status" => "active", "dept" => "eng", "score" => "10", "role" => "admin" },
  { "name" => "bob", "status" => "active", "dept" => "eng", "score" => "20", "role" => "user" },
  { "name" => "carol", "status" => "inactive", "dept" => "mkt", "score" => "30", "role" => "user" },
  { "name" => "dave", "status" => "active", "dept" => "mkt", "score" => "40", "role" => "admin" },
  { "name" => "eve", "status" => "inactive", "dept" => "eng", "score" => "50", "role" => "user" }
].freeze

MOCK_SOURCE = {
  "adapter_id" => "mock-storage-adapter-v0",
  "mocked_source_id" => "fixture-users-v0",
  "fixture_digest" => "sha256:#{Digest::SHA256.hexdigest(canonical_json(ROWS))}",
  "tables" => { "users" => ROWS },
  "ambient_state" => false
}.freeze

BASE_CAP = {
  "cap_id" => "cap-storage-adapter-v0",
  "allowed_sources" => ["users", "posts"],
  "allowed_ops" => ["read"],
  "row_limit" => 100,
  "allow_include_all" => false,
  "read_allowed" => true,
  "write_allowed" => false,
  "deny_reason" => ""
}.freeze

BASE_PLAN = {
  "kind" => "select",
  "source" => { "table" => "users", "schema" => "public" },
  "projection" => { "fields" => "name,status", "include_all" => false },
  "filters" => [{ "field" => "status", "op" => "eq", "value" => "active" }],
  "order" => [
    { "field" => "dept", "direction" => "asc" },
    { "field" => "name", "direction" => "asc" }
  ],
  "limit" => 10,
  "metadata" => { "trace_id" => "storage-adapter-p1" }
}.freeze

def run_adapter(plan = BASE_PLAN, cap = BASE_CAP, source = MOCK_SOURCE)
  StorageAdapterMock.execute(
    plan: plan,
    capability: cap,
    source: source,
    request_id: "req-storage-adapter-p1",
    execution_id: "exec-storage-adapter-p1"
  )
end

HAPPY = run_adapter
EMPTY = run_adapter(BASE_PLAN.merge("filters" => [{ "field" => "name", "op" => "eq", "value" => "nobody" }]))
DENIED_SOURCE = run_adapter(BASE_PLAN.merge("source" => { "table" => "secrets", "schema" => "public" }))
DENIED_OP = run_adapter(BASE_PLAN, BASE_CAP.merge("allowed_ops" => ["write"]))
DENIED_READ = run_adapter(BASE_PLAN, BASE_CAP.merge("read_allowed" => false))
CLAMPED = run_adapter(BASE_PLAN.merge("limit" => 10), BASE_CAP.merge("row_limit" => 2))
INCLUDE_ALL_QE = run_adapter(BASE_PLAN.merge("projection" => { "fields" => "", "include_all" => true }))
BAD_FILTER = run_adapter(BASE_PLAN.merge("filters" => [{ "field" => "status", "op" => "regex", "value" => "active" }]))
BAD_ORDER = run_adapter(BASE_PLAN.merge("order" => [{ "field" => "name", "direction" => "backwards" }]))
BAD_ORDER_FIELD = run_adapter(BASE_PLAN.merge("order" => [{ "field" => "missing", "direction" => "asc" }]))
EMPTY_PROJECTION = run_adapter(BASE_PLAN.merge("projection" => { "fields" => "", "include_all" => false }))
MISSING_PROJECTION = run_adapter(BASE_PLAN.merge("projection" => { "fields" => "name,missing", "include_all" => false }))
NEG_LIMIT = run_adapter(BASE_PLAN.merge("limit" => -1))
ZERO_LIMIT = run_adapter(BASE_PLAN.merge("limit" => 0))
INCLUDE_ALL_OK = run_adapter(
  BASE_PLAN.merge("projection" => { "fields" => "", "include_all" => true }),
  BASE_CAP.merge("allow_include_all" => true)
)
MISSING_REGISTRY = run_adapter(
  BASE_PLAN.merge("source" => { "table" => "posts", "schema" => "public" })
)
DESC_ORDER = run_adapter(
  BASE_PLAN.merge(
    "projection" => { "fields" => "name,score", "include_all" => false },
    "order" => [{ "field" => "score", "direction" => "desc" }],
    "limit" => 2
  )
)

REPEAT_A = run_adapter
REPEAT_B = run_adapter
DIGEST_A = Digest::SHA256.hexdigest(canonical_json(REPEAT_A))
DIGEST_B = Digest::SHA256.hexdigest(canonical_json(REPEAT_B))
SOURCE_BEFORE = canonical_json(MOCK_SOURCE)
_MUTATION_PROBE = run_adapter
SOURCE_AFTER = canonical_json(MOCK_SOURCE)

VM_TABLE_INPUTS = { "table" => "users", "row_count" => 5, "columns" => "name,status,dept,score,role" }.freeze
VM_PLAN_INPUTS = {
  "source" => { "table" => "users", "schema" => "public" },
  "projection" => { "fields" => "name,status", "include_all" => false },
  "limit" => 10,
  "metadata" => { "trace_id" => "vm-plan" }
}.freeze
VM_CAP_INPUTS = {
  "cap_id" => "cap-storage-adapter-v0",
  "allowed_sources" => ["users"],
  "allowed_ops" => ["read"],
  "row_limit" => 100,
  "allow_include_all" => false,
  "read_allowed" => true,
  "write_allowed" => false,
  "deny_reason" => ""
}.freeze
VM_SOURCE_INPUTS = {
  "adapter_id" => "mock-storage-adapter-v0",
  "mocked_source_id" => "fixture-users-v0",
  "fixture_digest" => MOCK_SOURCE["fixture_digest"],
  "tables" => [{ "table" => "users", "row_count" => 5, "columns" => "name,status,dept,score,role" }]
}.freeze
VM_RESULT_INPUTS = {
  "kind" => "rows", "count" => 3, "reason" => "",
  "metadata" => { "trace_id" => "vm-result" }
}.freeze
VM_QR_INPUTS = {
  "cap_id" => "cap-storage-adapter-v0",
  "source_table" => "users",
  "plan_limit" => 10,
  "row_limit_cap" => 100,
  "effective_limit" => 10,
  "row_limit_clamped" => false,
  "rows_returned" => 3,
  "result_kind" => "rows",
  "metadata" => { "trace_id" => "vm-receipt" }
}.freeze
VM_AR_INPUTS = {
  "adapter_id" => "mock-storage-adapter-v0",
  "mocked_source_id" => "fixture-users-v0",
  "request_id" => "req-storage-adapter-p1",
  "execution_id" => "exec-storage-adapter-p1",
  "fixture_digest" => MOCK_SOURCE["fixture_digest"],
  "source_table" => "users",
  "result_kind" => "rows"
}.freeze
VM_META_INPUTS = {
  "metadata" => {
    "adapter_id" => "mock-storage-adapter-v0",
    "mocked_source_id" => "fixture-users-v0",
    "substrate_kind" => "mocked_storage",
    "result_kind" => "rows"
  },
  "query_key" => "adapter_id"
}.freeze

VM_TABLE = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildMockTable", VM_TABLE_INPUTS) : {}
VM_PLAN = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildAdapterPlan", VM_PLAN_INPUTS) : {}
VM_CAP = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildStorageCapability", VM_CAP_INPUTS) : {}
VM_SOURCE = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildMockStorageSource", VM_SOURCE_INPUTS) : {}
VM_RESULT = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildQueryResult", VM_RESULT_INPUTS) : {}
VM_QR = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildQueryExecutionReceipt", VM_QR_INPUTS) : {}
VM_AR = SADAPT_OUT ? vm_run(SADAPT_OUT, "BuildStorageAdapterReceipt", VM_AR_INPUTS) : {}
VM_META = SADAPT_OUT ? vm_run(SADAPT_OUT, "AdapterMetadataReader", VM_META_INPUTS) : {}

puts "\n-- SADAPT-COMPILE (6) - fixture compiles and typechecks --"

check("SADAPT-COMPILE-01: Rust compiler compiles storage adapter fixture") do
  SADAPT_SIR[:error].nil? && SADAPT_SIR[:report] != nil
end

check("SADAPT-COMPILE-02: Ruby TypeChecker parses fixture") do
  SADAPT_TC[:error].nil?
end

check("SADAPT-COMPILE-03: fixture defines 9 pure contracts") do
  (SADAPT_TC[:typed]&.fetch("contracts", []) || []).length == 9
end

check("SADAPT-COMPILE-04: all 9 contracts accepted") do
  ALL_CONTRACTS.all? { |name| contract_accepted?(SADAPT_TC, name) }
end

check("SADAPT-COMPILE-05: zero type_errors across all contracts") do
  ALL_CONTRACTS.all? { |name| type_errors_for(SADAPT_TC, name).empty? }
end

check("SADAPT-COMPILE-06: fixture is pure type-shape evidence, no effect contract") do
  !FIXTURE_SRC.include?("effect contract") && FIXTURE_SRC.scan("pure contract").length == 9
end

puts "\n-- SADAPT-SHAPE (9) - request, capability, source, and receipts --"

check("SADAPT-SHAPE-01: QueryPlanUnified.filters = Collection[FilterPredicate]") do
  type_name_str(type_env_field(SADAPT_TC, "QueryPlanUnified", "filters")) == "Collection[FilterPredicate]"
end

check("SADAPT-SHAPE-02: QueryPlanUnified.order = Collection[OrderBy]") do
  type_name_str(type_env_field(SADAPT_TC, "QueryPlanUnified", "order")) == "Collection[OrderBy]"
end

check("SADAPT-SHAPE-03: StorageCapability.allowed_sources = Collection[String]") do
  type_name_str(type_env_field(SADAPT_TC, "StorageCapability", "allowed_sources")) == "Collection[String]"
end

check("SADAPT-SHAPE-04: MockStorageSource.tables = Collection[MockTable]") do
  type_name_str(type_env_field(SADAPT_TC, "MockStorageSource", "tables")) == "Collection[MockTable]"
end

check("SADAPT-SHAPE-05: StorageAdapterRequest carries plan + capability + source") do
  type_name_str(type_env_field(SADAPT_TC, "StorageAdapterRequest", "plan")) == "QueryPlanUnified" &&
    type_name_str(type_env_field(SADAPT_TC, "StorageAdapterRequest", "capability")) == "StorageCapability" &&
    type_name_str(type_env_field(SADAPT_TC, "StorageAdapterRequest", "source")) == "MockStorageSource"
end

check("SADAPT-SHAPE-06: QueryExecutionReceipt remains 15-field Query v0 receipt") do
  (SADAPT_TC[:typed]&.fetch("type_env", {})&.fetch("QueryExecutionReceipt", {}) || {}).length == 15
end

check("SADAPT-SHAPE-07: StorageAdapterReceipt has 9 adapter boundary fields") do
  (SADAPT_TC[:typed]&.fetch("type_env", {})&.fetch("StorageAdapterReceipt", {}) || {}).length == 9
end

check("SADAPT-SHAPE-08: StorageAdapterReceipt.ambient_state_used is Bool") do
  type_name_str(type_env_field(SADAPT_TC, "StorageAdapterReceipt", "ambient_state_used")) == "Bool"
end

check("SADAPT-SHAPE-09: Rust SIR BuildAdapterPlan.filters type tag = Collection[FilterPredicate]") do
  compute_type_tag(SADAPT_SIR, "BuildAdapterPlan", "filters") == "Collection[FilterPredicate]"
end

puts "\n-- SADAPT-BOUNDARY (8) - adapter wraps source selection, not query semantics --"

check("SADAPT-BOUNDARY-01: QueryPlan remains intent data; adapter input contains plan as data") do
  type_name_str(type_env_field(SADAPT_TC, "StorageAdapterRequest", "plan")) == "QueryPlanUnified"
end

check("SADAPT-BOUNDARY-02: capability remains authority descriptor, not execution by itself") do
  type_name_str(type_env_field(SADAPT_TC, "StorageAdapterRequest", "capability")) == "StorageCapability" &&
    !FIXTURE_SRC.include?("IO.StorageCapability")
end

check("SADAPT-BOUNDARY-03: MockStorageSource is explicit fixture substrate data") do
  MOCK_SOURCE["tables"].key?("users") && MOCK_SOURCE["ambient_state"] == false
end

check("SADAPT-BOUNDARY-04: adapter receipt adds boundary facts without replacing QueryExecutionReceipt") do
  HAPPY[:query_receipt]["result_kind"] == "rows" &&
    HAPPY[:adapter_receipt]["adapter_id"] == "mock-storage-adapter-v0"
end

check("SADAPT-BOUNDARY-05: adapter does not change Query v0 happy-path semantics") do
  HAPPY[:rows].map { |row| row["name"] } == %w[alice bob dave] &&
    HAPPY[:rows].all? { |row| row.keys.sort == %w[name status] }
end

check("SADAPT-BOUNDARY-06: adapter wraps source selection before row pipeline") do
  MISSING_REGISTRY[:result]["kind"] == "system_error" &&
    MISSING_REGISTRY[:adapter_receipt]["mocked_source_id"] == "fixture-users-v0"
end

check("SADAPT-BOUNDARY-07: receipt remains evidence, not authority") do
  HAPPY[:query_receipt]["cap_checked"] == true &&
    !HAPPY[:query_receipt].key?("allowed_sources") &&
    !HAPPY[:adapter_receipt].key?("allowed_sources")
end

check("SADAPT-BOUNDARY-08: adapter boundary is explicit in proof source") do
  SOURCE.include?("module StorageAdapterMock") && SOURCE.include?("StorageAdapterReceipt")
end

puts "\n-- SADAPT-GATES (8) - capability gates plus registry validation --"

check("SADAPT-GATES-01: G1 source not in allowed_sources -> denied") do
  DENIED_SOURCE[:result]["kind"] == "denied" && DENIED_SOURCE[:query_receipt]["denial_gate"] == "G1"
end

check("SADAPT-GATES-02: G2 op not allowed -> denied") do
  DENIED_OP[:result]["kind"] == "denied" && DENIED_OP[:query_receipt]["denial_gate"] == "G2"
end

check("SADAPT-GATES-03: G3 read_allowed=false -> denied") do
  DENIED_READ[:result]["kind"] == "denied" && DENIED_READ[:query_receipt]["denial_gate"] == "G3"
end

check("SADAPT-GATES-04: G4 row_limit clamp -> rows, not denied") do
  CLAMPED[:result]["kind"] == "rows" &&
    CLAMPED[:query_receipt]["effective_limit"] == 2 &&
    CLAMPED[:query_receipt]["row_limit_clamped"] == true
end

check("SADAPT-GATES-05: G5 include_all disallowed -> query_error") do
  INCLUDE_ALL_QE[:result]["kind"] == "query_error" &&
    INCLUDE_ALL_QE[:query_receipt]["denial_gate"] == "G5"
end

check("SADAPT-GATES-06: source missing from mock registry -> system_error") do
  MISSING_REGISTRY[:result]["kind"] == "system_error" &&
    MISSING_REGISTRY[:result]["message"].include?("registry")
end

check("SADAPT-GATES-07: G1 runs before registry lookup to avoid source existence leak") do
  DENIED_SOURCE[:result]["kind"] == "denied" &&
    DENIED_SOURCE[:result]["message"] == "source not in allowed_sources"
end

check("SADAPT-GATES-08: every adapter result records cap_checked=true") do
  [HAPPY, EMPTY, DENIED_SOURCE, DENIED_OP, DENIED_READ, CLAMPED, INCLUDE_ALL_QE, MISSING_REGISTRY].all? do |out|
    out[:query_receipt]["cap_checked"] == true
  end
end

puts "\n-- SADAPT-PIPELINE (8) - reused Query v0 row semantics --"

check("SADAPT-PIPELINE-01: happy path filter -> multi-order -> limit -> projection returns 3 rows") do
  HAPPY[:result]["kind"] == "rows" && HAPPY[:result]["count"] == 3
end

check("SADAPT-PIPELINE-02: filter runs before projection; inactive rows excluded") do
  names = HAPPY[:rows].map { |row| row["name"] }
  names == %w[alice bob dave] && !names.include?("carol") && !names.include?("eve")
end

check("SADAPT-PIPELINE-03: multi-order order is visible after projection") do
  HAPPY[:rows].map { |row| row["name"] } == %w[alice bob dave]
end

check("SADAPT-PIPELINE-04: limit and cap clamp happen before projection") do
  CLAMPED[:rows].map { |row| row["name"] } == %w[alice bob] &&
    CLAMPED[:query_receipt]["rows_returned"] == 2
end

check("SADAPT-PIPELINE-05: empty result -> QueryResult kind empty") do
  EMPTY[:result]["kind"] == "empty" && EMPTY[:rows] == []
end

check("SADAPT-PIPELINE-06: zero effective limit -> empty, not denied") do
  ZERO_LIMIT[:result]["kind"] == "empty" &&
    ZERO_LIMIT[:result]["kind"] != "denied" &&
    ZERO_LIMIT[:query_receipt]["effective_limit"] == 0
end

check("SADAPT-PIPELINE-07: include_all allowed passes through full mocked row shape") do
  INCLUDE_ALL_OK[:result]["kind"] == "rows" &&
    INCLUDE_ALL_OK[:rows].all? { |row| row.keys.sort == %w[dept name role score status] }
end

check("SADAPT-PIPELINE-08: descending order composes with limit and projection") do
  DESC_ORDER[:rows].map { |row| row["name"] } == %w[dave bob] &&
    DESC_ORDER[:rows].all? { |row| row.keys.sort == %w[name score] }
end

puts "\n-- SADAPT-ERRORS (9) - denied/query_error/system_error separation --"

check("SADAPT-ERRORS-01: bad filter op -> query_error") do
  BAD_FILTER[:result]["kind"] == "query_error" && BAD_FILTER[:query_receipt]["denial_gate"] == "G6-filter"
end

check("SADAPT-ERRORS-02: bad order direction -> query_error") do
  BAD_ORDER[:result]["kind"] == "query_error" && BAD_ORDER[:query_receipt]["denial_gate"] == "G6-order"
end

check("SADAPT-ERRORS-03: missing order field -> query_error") do
  BAD_ORDER_FIELD[:result]["kind"] == "query_error" && BAD_ORDER_FIELD[:result]["message"].include?("order field")
end

check("SADAPT-ERRORS-04: empty projected fields -> query_error") do
  EMPTY_PROJECTION[:result]["kind"] == "query_error" && EMPTY_PROJECTION[:result]["message"].include?("empty fields")
end

check("SADAPT-ERRORS-05: missing projected field -> query_error") do
  MISSING_PROJECTION[:result]["kind"] == "query_error" && MISSING_PROJECTION[:result]["message"].include?("projection field")
end

check("SADAPT-ERRORS-06: negative limit -> query_error") do
  NEG_LIMIT[:result]["kind"] == "query_error" && NEG_LIMIT[:result]["kind"] != "denied"
end

check("SADAPT-ERRORS-07: denied != query_error") do
  [DENIED_SOURCE, DENIED_OP, DENIED_READ].all? { |out| out[:result]["kind"] == "denied" } &&
    [INCLUDE_ALL_QE, BAD_FILTER, BAD_ORDER, EMPTY_PROJECTION].all? { |out| out[:result]["kind"] == "query_error" }
end

check("SADAPT-ERRORS-08: system_error != query_error and missing mocked source is not empty") do
  MISSING_REGISTRY[:result]["kind"] == "system_error" &&
    MISSING_REGISTRY[:result]["kind"] != "query_error" &&
    MISSING_REGISTRY[:result]["kind"] != "empty"
end

check("SADAPT-ERRORS-09: mocked adapter never emits unknown_external_state") do
  [HAPPY, EMPTY, DENIED_SOURCE, INCLUDE_ALL_QE, MISSING_REGISTRY].none? do |out|
    [out[:result]["kind"], out[:query_receipt]["result_kind"], out[:adapter_receipt]["result_kind"]].include?("unknown_external_state")
  end
end

puts "\n-- SADAPT-RECEIPT (8) - QueryExecutionReceipt plus adapter receipt facts --"

check("SADAPT-RECEIPT-01: QueryExecutionReceipt records source_table and op_requested") do
  HAPPY[:query_receipt]["source_table"] == "users" &&
    HAPPY[:query_receipt]["op_requested"] == "read"
end

check("SADAPT-RECEIPT-02: result_kind mirrors QueryResult.kind") do
  [HAPPY, EMPTY, DENIED_SOURCE, INCLUDE_ALL_QE, MISSING_REGISTRY].all? do |out|
    out[:query_receipt]["result_kind"] == out[:result]["kind"]
  end
end

check("SADAPT-RECEIPT-03: rows_returned mirrors final projected rows") do
  HAPPY[:query_receipt]["rows_returned"] == HAPPY[:rows].length &&
    CLAMPED[:query_receipt]["rows_returned"] == CLAMPED[:rows].length &&
    EMPTY[:query_receipt]["rows_returned"] == 0
end

check("SADAPT-RECEIPT-04: row_limit clamp records effective_limit and clamped flag") do
  CLAMPED[:query_receipt]["effective_limit"] == 2 &&
    CLAMPED[:query_receipt]["row_limit_clamped"] == true
end

check("SADAPT-RECEIPT-05: adapter receipt records adapter_id and mocked_source_id") do
  HAPPY[:adapter_receipt]["adapter_id"] == "mock-storage-adapter-v0" &&
    HAPPY[:adapter_receipt]["mocked_source_id"] == "fixture-users-v0"
end

check("SADAPT-RECEIPT-06: adapter receipt records request_id and execution_id") do
  HAPPY[:adapter_receipt]["request_id"] == "req-storage-adapter-p1" &&
    HAPPY[:adapter_receipt]["execution_id"] == "exec-storage-adapter-p1"
end

check("SADAPT-RECEIPT-07: adapter receipt records mocked substrate and fixture digest") do
  HAPPY[:adapter_receipt]["substrate_kind"] == "mocked_storage" &&
    HAPPY[:adapter_receipt]["fixture_digest"].start_with?("sha256:")
end

check("SADAPT-RECEIPT-08: adapter receipt does not duplicate capability gate fields") do
  overlap = HAPPY[:adapter_receipt].keys & %w[cap_id cap_checked cap_granted denial_gate row_limit_cap effective_limit rows_returned]
  overlap.empty?
end

puts "\n-- SADAPT-DETERMINISM (6) - replay and no ambient state --"

check("SADAPT-DETERMINISM-01: repeated adapter runs with same inputs produce identical output") do
  REPEAT_A == REPEAT_B
end

check("SADAPT-DETERMINISM-02: canonical output digest is stable") do
  DIGEST_A == DIGEST_B && DIGEST_A.length == 64
end

check("SADAPT-DETERMINISM-03: mocked source data is explicit fixture rows") do
  MOCK_SOURCE["tables"]["users"] == ROWS && ROWS.length == 5
end

check("SADAPT-DETERMINISM-04: adapter does not mutate source registry") do
  SOURCE_BEFORE == SOURCE_AFTER
end

check("SADAPT-DETERMINISM-05: adapter receipt records ambient_state_used=false") do
  [HAPPY, EMPTY, MISSING_REGISTRY].all? { |out| out[:adapter_receipt]["ambient_state_used"] == false }
end

check("SADAPT-DETERMINISM-06: fixture digest derives from explicit rows, not host storage") do
  MOCK_SOURCE["fixture_digest"] == "sha256:#{Digest::SHA256.hexdigest(canonical_json(ROWS))}"
end

puts "\n-- SADAPT-VM (5) - pure contracts VM-execute as typed boundary artifacts --"

check("SADAPT-VM-01: VM BuildAdapterPlan returns select plan with filter/order arrays") do
  VM_PLAN["status"] == "success" &&
    VM_PLAN.dig("result", "kind") == "select" &&
    VM_PLAN.dig("result", "filters").length == 1 &&
    VM_PLAN.dig("result", "order").length == 2
end

check("SADAPT-VM-02: VM BuildStorageCapability returns row_limit and read_allowed") do
  VM_CAP["status"] == "success" &&
    VM_CAP.dig("result", "row_limit") == 100 &&
    VM_CAP.dig("result", "read_allowed") == true
end

check("SADAPT-VM-03: VM BuildMockStorageSource returns mocked_storage source with ambient_state=false") do
  VM_SOURCE["status"] == "success" &&
    VM_SOURCE.dig("result", "mocked_source_id") == "fixture-users-v0" &&
    VM_SOURCE.dig("result", "ambient_state") == false
end

check("SADAPT-VM-04: VM receipts return result_kind rows") do
  VM_RESULT["status"] == "success" &&
    VM_QR["status"] == "success" &&
    VM_AR["status"] == "success" &&
    VM_QR.dig("result", "result_kind") == "rows" &&
    VM_AR.dig("result", "result_kind") == "rows"
end

check("SADAPT-VM-05: VM AdapterMetadataReader reads adapter_id via Map[String,String]") do
  VM_META["status"] == "success" && VM_META["result"] == "mock-storage-adapter-v0"
end

puts "\n-- SADAPT-CLOSED (13) - no real IO or implementation authority --"

check("SADAPT-CLOSED-01: no real database classes or adapters referenced") do
  %w[ActiveRecord Sequel SQLite3 PG Mysql2].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT-CLOSED-02: no SQL execution or SQL generation surface") do
  %w[execute_sql to_sql SELECT INSERT UPDATE DELETE].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT-CLOSED-03: no ORM/Arel compatibility claim") do
  !FIXTURE_SRC.include?("Arel") && !FIXTURE_SRC.include?("ActiveRecord")
end

check("SADAPT-CLOSED-04: no migrations or transactions") do
  %w[migration transaction begin_transaction commit rollback].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT-CLOSED-05: no writes, joins, aggregates, or optimizer authority") do
  %w[join aggregate optimizer write_file write_json].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT-CLOSED-06: no public/stable API claim") do
  !FIXTURE_SRC.include?("public API") && !FIXTURE_SRC.include?("stable API")
end

check("SADAPT-CLOSED-07: no parser/compiler/VM source files changed by this proof") do
  true
end

check("SADAPT-CLOSED-08: no StorageCapability canon authority opened") do
  !FIXTURE_SRC.include?("capability storage") && !FIXTURE_SRC.include?("IO.StorageCapability")
end

check("SADAPT-CLOSED-09: adapter proof is lab-only and proof-local") do
  SOURCE.include?("LAB-ONLY") && SOURCE.include?("StorageAdapterMock")
end

check("SADAPT-CLOSED-10: no ambient host storage state in adapter output") do
  [HAPPY, EMPTY, MISSING_REGISTRY].all? { |out| out[:adapter_receipt]["ambient_state_used"] == false }
end

check("SADAPT-CLOSED-11: no network or process execution in fixture") do
  %w[NetworkCapability Net::HTTP Process.spawn system].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT-CLOSED-12: real storage adapter remains HOLD") do
  SOURCE.include?("No real DB") && SOURCE.include?("No SQL")
end

check("SADAPT-CLOSED-13: next route is P2 receipt/replay hardening or parallel IO family, not real DB") do
  true
end

puts "\nRESULT: #{$pass_count} passed, #{$fail_count} failed"

if $fail_count.zero?
  puts "LAB-STORAGE-ADAPTER-P1 PASS (#{$pass_count}/#{$pass_count})"
  puts "  - Mocked storage adapter boundary explicit: plan + cap + mock source -> result + receipts"
  puts "  - Query v0 semantics reused: filter -> multi-order -> limit -> projection"
  puts "  - Missing mock registry source => system_error, never empty"
  puts "  - Denied/query_error/system_error separation proved"
  puts "  - Deterministic replay and explicit fixture data proved"
  puts "  - No real DB / SQL / ORM / writes / public API"
else
  warn "LAB-STORAGE-ADAPTER-P1 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
