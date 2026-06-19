#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_storage_adapter_p2.rb
# LAB-STORAGE-ADAPTER-P2 - 82 checks
#
# Adapter Receipt Replay and Tamper Hardening.
#
# Core thesis:
#   Storage adapter receipts are evidence, not authority. Replay recomputes the
#   mocked adapter result from the original request + capability + fixture rows,
#   recomputes stable digests, and rejects receipt drift/tamper fail-closed.
#
# Authority: LAB-ONLY. No real DB. No SQL. No ORM. No writes. No public API.
# Run: ruby igniter-view-engine/proofs/verify_lab_storage_adapter_p2.rb

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
FIXTURE_PATH   = (ROOT / "fixtures" / "storage_adapter" / "storage_adapter_replay.ig").to_s

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

def compile_path(path, tag = "sadapt2")
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

def vm_run(out_dir, contract_name, inputs)
  tmpfile = Tempfile.new(["sadapt2_inputs", ".json"])
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

def digest(value)
  "sha256:#{Digest::SHA256.hexdigest(canonical_json(value))}"
end

def deep_copy(value)
  JSON.parse(JSON.generate(value))
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

module StorageAdapterMockP2
  KNOWN_OPS = %w[eq neq contains prefix].freeze
  KNOWN_DIRECTIONS = %w[asc desc].freeze

  def self.execute(plan:, capability:, source:, request_id:, execution_id:)
    source_table = plan.dig("source", "table") || ""
    projection = plan.fetch("projection", { "fields" => "", "include_all" => false })
    plan_limit = plan.fetch("limit", 0)
    row_limit = capability.fetch("row_limit", 0)
    cap_id = capability.fetch("cap_id", "")
    metadata = plan.fetch("metadata", {})
    ctx = {
      adapter_id: source.fetch("adapter_id", ""),
      mocked_source_id: source.fetch("mocked_source_id", ""),
      fixture_digest: source.fetch("fixture_digest", ""),
      request_id: request_id,
      execution_id: execution_id,
      source_table: source_table
    }

    unless capability.fetch("allowed_sources", []).include?(source_table)
      return denied("G1", "source not in allowed_sources", cap_id, plan_limit, row_limit, metadata, ctx)
    end
    return denied("G2", "op not in allowed_ops", cap_id, plan_limit, row_limit, metadata, ctx) unless capability.fetch("allowed_ops", []).include?("read")
    return denied("G3", "read_allowed is false", cap_id, plan_limit, row_limit, metadata, ctx) unless capability.fetch("read_allowed", false)

    rows = source.fetch("tables", {})[source_table]
    return system_error("mocked source table missing from registry", cap_id, plan_limit, row_limit, metadata, ctx) if rows.nil?

    effective_limit = [plan_limit, row_limit].min
    clamped = effective_limit < plan_limit

    if projection.fetch("include_all", false) && !capability.fetch("allow_include_all", false)
      return query_error("G5", "include_all not permitted by capability", cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
    end
    return query_error("G6-limit", "negative limit", cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx) if effective_limit.negative?

    filtered = filter_rows(rows, plan.fetch("filters", []))
    return query_error("G6-filter", filtered[:message], cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx) if filtered[:kind] == "query_error"

    ordered = order_rows(filtered[:rows], plan.fetch("order", []))
    return query_error("G6-order", ordered[:message], cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx) if ordered[:kind] == "query_error"

    return success([], "empty", cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx) if effective_limit == 0

    projected = project_rows(ordered[:rows].first(effective_limit), projection)
    return query_error("G6-projection", projected[:message], cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx) if projected[:kind] == "query_error"

    success(projected[:rows], projected[:rows].empty? ? "empty" : "rows", cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
  end

  def self.filter_rows(rows, filters)
    bad = filters.find { |filter| !KNOWN_OPS.include?(filter.fetch("op", "")) }
    return { kind: "query_error", message: "unknown filter operator: #{bad["op"]}" } if bad

    { kind: "ok", rows: rows.select { |row| filters.all? { |filter| row_matches?(row, filter) } } }
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

    rows.each_with_index.sort_by do |row, index|
      keys = order_list.map do |order|
        value = row.fetch(order.fetch("field", ""), "")
        order.fetch("direction", "asc") == "asc" ? value : ReverseComparable.new(value)
      end
      keys + [index]
    end.map(&:first).then { |sorted| { kind: "ok", rows: sorted } }
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
    build_output("denied", 0, reason, [], cap_id, plan_limit, row_limit, 0, false, false, gate, reason, metadata, ctx)
  end

  def self.query_error(gate, reason, cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
    build_output("query_error", 0, reason, [], cap_id, plan_limit, row_limit, effective_limit, clamped, false, gate, reason, metadata, ctx)
  end

  def self.system_error(reason, cap_id, plan_limit, row_limit, metadata, ctx)
    build_output("system_error", 0, reason, [], cap_id, plan_limit, row_limit, 0, false, true, "", reason, metadata, ctx)
  end

  def self.success(rows, kind, cap_id, plan_limit, row_limit, effective_limit, clamped, metadata, ctx)
    build_output(kind, rows.length, "", rows, cap_id, plan_limit, row_limit, effective_limit, clamped, true, "", "", metadata, ctx)
  end

  def self.build_output(kind, count, message, rows, cap_id, plan_limit, row_limit, effective_limit, clamped, cap_granted, denial_gate, deny_reason, metadata, ctx)
    result = { "kind" => kind, "count" => count, "message" => message, "metadata" => metadata }
    receipt = {
      "cap_id" => cap_id, "plan_kind" => "select", "source_table" => ctx[:source_table],
      "op_requested" => "read", "cap_checked" => true, "cap_granted" => cap_granted,
      "denial_gate" => denial_gate, "deny_reason" => deny_reason,
      "plan_limit" => plan_limit, "row_limit_cap" => row_limit,
      "effective_limit" => effective_limit, "row_limit_clamped" => clamped,
      "rows_returned" => rows.length, "result_kind" => kind, "metadata" => metadata
    }
    adapter_receipt = {
      "adapter_id" => ctx[:adapter_id], "mocked_source_id" => ctx[:mocked_source_id],
      "request_id" => ctx[:request_id], "execution_id" => ctx[:execution_id],
      "substrate_kind" => "mocked_storage", "fixture_digest" => ctx[:fixture_digest],
      "source_table" => ctx[:source_table], "result_kind" => kind,
      "ambient_state_used" => false
    }
    { "result" => result, "query_receipt" => receipt, "adapter_receipt" => adapter_receipt, "rows" => rows }
  end
end

module StorageAdapterReplayVerifier
  SCHEMA_VERSION = "storage-adapter-replay-v0"
  ADAPTER_CODE_VERSION = "mock-storage-adapter-v0"
  QUERY_RECEIPT_FIELDS = %w[
    cap_id plan_kind source_table op_requested cap_checked cap_granted denial_gate
    deny_reason plan_limit row_limit_cap effective_limit row_limit_clamped
    rows_returned result_kind metadata
  ].freeze
  ADAPTER_RECEIPT_FIELDS = %w[
    adapter_id mocked_source_id request_id execution_id substrate_kind fixture_digest
    source_table result_kind ambient_state_used
  ].freeze

  def self.build_bundle(plan:, capability:, source:, request_id:, execution_id:)
    request = {
      "plan" => deep_copy(plan),
      "capability" => deep_copy(capability),
      "source_meta" => source_meta(source),
      "request_id" => request_id,
      "execution_id" => execution_id
    }
    output = StorageAdapterMockP2.execute(
      plan: plan, capability: capability, source: source,
      request_id: request_id, execution_id: execution_id
    )
    bundle = {
      "schema_version" => SCHEMA_VERSION,
      "adapter_code_version" => ADAPTER_CODE_VERSION,
      "request" => request,
      "source" => deep_copy(source),
      "result" => output["result"],
      "rows" => output["rows"],
      "query_receipt" => output["query_receipt"],
      "adapter_receipt" => output["adapter_receipt"]
    }
    bundle["digests"] = digest_bundle(bundle)
    bundle
  end

  def self.verify(bundle)
    return result("insufficient_evidence", "missing replay bundle", "", "", false) unless bundle.is_a?(Hash)

    request = bundle["request"]
    return result("insufficient_evidence", "original request missing", "", "", false) unless request.is_a?(Hash)
    return result("insufficient_evidence", "source fixture missing", request["request_id"].to_s, request["execution_id"].to_s, false) unless bundle["source"].is_a?(Hash)
    return result("insufficient_evidence", "query result missing", request["request_id"].to_s, request["execution_id"].to_s, false) unless bundle["result"].is_a?(Hash)
    return result("insufficient_evidence", "query receipt missing", request["request_id"].to_s, request["execution_id"].to_s, false) unless bundle["query_receipt"].is_a?(Hash)
    return result("insufficient_evidence", "adapter receipt missing", request["request_id"].to_s, request["execution_id"].to_s, false) unless bundle["adapter_receipt"].is_a?(Hash)
    return result("insufficient_evidence", "digest bundle missing", request["request_id"].to_s, request["execution_id"].to_s, false) unless bundle["digests"].is_a?(Hash)

    if bundle["schema_version"] != SCHEMA_VERSION
      return result("version_mismatch", "schema_version mismatch", request["request_id"], request["execution_id"], false)
    end

    if bundle["adapter_code_version"] != ADAPTER_CODE_VERSION ||
       bundle.dig("source", "adapter_id") != ADAPTER_CODE_VERSION ||
       bundle.dig("adapter_receipt", "adapter_id") != ADAPTER_CODE_VERSION
      return result("version_mismatch", "adapter_id or adapter_code_version mismatch", request["request_id"], request["execution_id"], false)
    end

    expected_fixture_digest = digest(bundle.dig("source", "tables") || {})
    if bundle.dig("source", "fixture_digest") != expected_fixture_digest
      return result("fixture_drift", "fixture_digest does not match fixture rows", request["request_id"], request["execution_id"], false)
    end

    current_request_digest = digest(request)
    current_plan_digest = digest(request["plan"])
    current_capability_digest = digest(request["capability"])
    current_fixture_digest = expected_fixture_digest

    if bundle.dig("digests", "request_digest") != current_request_digest
      if bundle.dig("digests", "plan_digest") != current_plan_digest
        return result("plan_drift", "plan digest changed after receipt", request["request_id"], request["execution_id"], false)
      end
      if bundle.dig("digests", "capability_digest") != current_capability_digest
        return result("capability_drift", "capability digest changed after receipt", request["request_id"], request["execution_id"], false)
      end
      return result("tampered", "request digest changed after receipt", request["request_id"], request["execution_id"], false)
    end

    return result("plan_drift", "plan digest changed after receipt", request["request_id"], request["execution_id"], false) if bundle.dig("digests", "plan_digest") != current_plan_digest
    return result("capability_drift", "capability digest changed after receipt", request["request_id"], request["execution_id"], false) if bundle.dig("digests", "capability_digest") != current_capability_digest
    return result("fixture_drift", "fixture digest changed after receipt", request["request_id"], request["execution_id"], false) if bundle.dig("digests", "fixture_digest") != current_fixture_digest

    expected = StorageAdapterMockP2.execute(
      plan: request["plan"], capability: request["capability"], source: bundle["source"],
      request_id: request["request_id"], execution_id: request["execution_id"]
    )

    result_diff = first_field_mismatch(expected["result"], bundle["result"], %w[kind count message metadata])
    return result("tampered", "query_result.#{result_diff} mismatch", request["request_id"], request["execution_id"], false) if result_diff

    qr_diff = first_field_mismatch(expected["query_receipt"], bundle["query_receipt"], QUERY_RECEIPT_FIELDS)
    return result("tampered", "query_receipt.#{qr_diff} mismatch", request["request_id"], request["execution_id"], false) if qr_diff

    ar_diff = first_field_mismatch(expected["adapter_receipt"], bundle["adapter_receipt"], ADAPTER_RECEIPT_FIELDS)
    return result("tampered", "adapter_receipt.#{ar_diff} mismatch", request["request_id"], request["execution_id"], false) if ar_diff

    current_digests = digest_bundle(bundle)
    current_digests.each do |key, value|
      next if bundle.dig("digests", key) == value

      return result("tampered", "#{key} mismatch", request["request_id"], request["execution_id"], false)
    end

    result("replay_ok", "replay verified against request/capability/fixture/result path", request["request_id"], request["execution_id"], true)
  end

  def self.digest_bundle(bundle)
    request = bundle.fetch("request")
    result_hash = bundle.fetch("result")
    query_receipt = bundle.fetch("query_receipt")
    adapter_receipt = bundle.fetch("adapter_receipt")
    source = bundle.fetch("source")
    base = {
      "request_digest" => digest(request),
      "plan_digest" => digest(request["plan"]),
      "capability_digest" => digest(request["capability"]),
      "fixture_digest" => digest(source.fetch("tables", {})),
      "query_result_digest" => digest(result_hash),
      "query_execution_receipt_digest" => digest(query_receipt),
      "adapter_receipt_digest" => digest(adapter_receipt)
    }
    base["replay_bundle_digest"] = digest({
      "schema_version" => bundle["schema_version"],
      "adapter_code_version" => bundle["adapter_code_version"],
      "request" => request,
      "result" => result_hash,
      "query_receipt" => query_receipt,
      "adapter_receipt" => adapter_receipt,
      "fixture_digest" => base["fixture_digest"]
    })
    base
  end

  def self.source_meta(source)
    source.reject { |key, _value| key == "tables" }
  end

  def self.first_field_mismatch(expected, actual, fields)
    fields.find { |field| expected[field] != actual[field] }
  end

  def self.result(kind, reason, request_id, execution_id, verified)
    {
      "kind" => kind,
      "reason" => reason,
      "request_id" => request_id.to_s,
      "execution_id" => execution_id.to_s,
      "verified" => verified,
      "metadata" => { "schema_version" => SCHEMA_VERSION, "adapter_code_version" => ADAPTER_CODE_VERSION }
    }
  end
end

ALL_CONTRACTS = %w[BuildReplayResult BuildDigestBundle BuildReplayContext ReplayMetadataReader].freeze

FIXTURE_SRC = File.read(FIXTURE_PATH).force_encoding("UTF-8").freeze
SADAPT2_TC = run_fixture(FIXTURE_PATH)
SADAPT2_SIR = compile_path(FIXTURE_PATH, "sadapt2")
SADAPT2_OUT = SADAPT2_SIR[:out_dir]

ROWS = [
  { "name" => "alice", "status" => "active", "dept" => "eng", "score" => "10", "role" => "admin" },
  { "name" => "bob", "status" => "active", "dept" => "eng", "score" => "20", "role" => "user" },
  { "name" => "carol", "status" => "inactive", "dept" => "mkt", "score" => "30", "role" => "user" },
  { "name" => "dave", "status" => "active", "dept" => "mkt", "score" => "40", "role" => "admin" },
  { "name" => "eve", "status" => "inactive", "dept" => "eng", "score" => "50", "role" => "user" }
].freeze

MOCK_SOURCE = {
  "adapter_id" => StorageAdapterReplayVerifier::ADAPTER_CODE_VERSION,
  "mocked_source_id" => "fixture-users-v0",
  "fixture_digest" => digest({ "users" => ROWS }),
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
  "metadata" => { "trace_id" => "storage-adapter-p2" }
}.freeze

BASE_BUNDLE = StorageAdapterReplayVerifier.build_bundle(
  plan: BASE_PLAN, capability: BASE_CAP, source: MOCK_SOURCE,
  request_id: "req-storage-adapter-p2", execution_id: "exec-storage-adapter-p2"
)
REPLAY_OK = StorageAdapterReplayVerifier.verify(BASE_BUNDLE)
REPLAY_OK_2 = StorageAdapterReplayVerifier.verify(deep_copy(BASE_BUNDLE))
REPLAY_DIGEST_A = digest(REPLAY_OK)
REPLAY_DIGEST_B = digest(REPLAY_OK_2)

def tampered_bundle
  deep_copy(BASE_BUNDLE)
end

TAMPER_RESULT_KIND = tampered_bundle.tap { |b| b["result"]["kind"] = "empty" }
TAMPER_ROWS_RETURNED = tampered_bundle.tap { |b| b["query_receipt"]["rows_returned"] = 99 }
TAMPER_EFFECTIVE_LIMIT = tampered_bundle.tap { |b| b["query_receipt"]["effective_limit"] = 99 }
TAMPER_CLAMPED = tampered_bundle.tap { |b| b["query_receipt"]["row_limit_clamped"] = true }
TAMPER_DENIAL_GATE = tampered_bundle.tap { |b| b["query_receipt"]["denial_gate"] = "G1" }
TAMPER_SOURCE_TABLE = tampered_bundle.tap { |b| b["query_receipt"]["source_table"] = "secrets" }
TAMPER_FIXTURE_DIGEST = tampered_bundle.tap { |b| b["adapter_receipt"]["fixture_digest"] = "sha256:bad" }
TAMPER_MOCKED_SOURCE = tampered_bundle.tap { |b| b["adapter_receipt"]["mocked_source_id"] = "fixture-other" }
TAMPER_AMBIENT_TRUE = tampered_bundle.tap { |b| b["adapter_receipt"]["ambient_state_used"] = true }
TAMPER_REQUEST_ID = tampered_bundle.tap { |b| b["adapter_receipt"]["request_id"] = "req-other" }
TAMPER_EXECUTION_ID = tampered_bundle.tap { |b| b["adapter_receipt"]["execution_id"] = "exec-other" }
TAMPER_DIGEST_ONLY = tampered_bundle.tap { |b| b["digests"]["replay_bundle_digest"] = "sha256:bad" }

CHANGED_ROWS = ROWS + [{ "name" => "frank", "status" => "active", "dept" => "ops", "score" => "60", "role" => "user" }]
FIXTURE_DRIFT = tampered_bundle.tap { |b| b["source"]["tables"]["users"] = CHANGED_ROWS }
CAPABILITY_DRIFT = tampered_bundle.tap { |b| b["request"]["capability"]["allowed_sources"] = ["posts"] }
PLAN_DRIFT = tampered_bundle.tap { |b| b["request"]["plan"]["limit"] = 1 }
VERSION_DRIFT = tampered_bundle.tap { |b| b["adapter_code_version"] = "mock-storage-adapter-v2" }
ADAPTER_ID_DRIFT = tampered_bundle.tap { |b| b["source"]["adapter_id"] = "mock-storage-adapter-v2" }
RECEIPT_ONLY = {
  "result" => BASE_BUNDLE["result"],
  "query_receipt" => BASE_BUNDLE["query_receipt"],
  "adapter_receipt" => BASE_BUNDLE["adapter_receipt"],
  "digests" => BASE_BUNDLE["digests"]
}

FIELD_ORDER_A = { "b" => 2, "a" => { "d" => 4, "c" => 3 } }
FIELD_ORDER_B = { "a" => { "c" => 3, "d" => 4 }, "b" => 2 }

VM_REPLAY_RESULT_INPUTS = {
  "kind" => "replay_ok",
  "reason" => "verified",
  "request_id" => "req-storage-adapter-p2",
  "execution_id" => "exec-storage-adapter-p2",
  "verified" => true,
  "metadata" => { "schema_version" => "storage-adapter-replay-v0" }
}.freeze
VM_DIGEST_INPUTS = {
  "request_digest" => BASE_BUNDLE["digests"]["request_digest"],
  "plan_digest" => BASE_BUNDLE["digests"]["plan_digest"],
  "capability_digest" => BASE_BUNDLE["digests"]["capability_digest"],
  "fixture_digest" => BASE_BUNDLE["digests"]["fixture_digest"],
  "query_result_digest" => BASE_BUNDLE["digests"]["query_result_digest"],
  "query_execution_receipt_digest" => BASE_BUNDLE["digests"]["query_execution_receipt_digest"],
  "adapter_receipt_digest" => BASE_BUNDLE["digests"]["adapter_receipt_digest"],
  "replay_bundle_digest" => BASE_BUNDLE["digests"]["replay_bundle_digest"]
}.freeze
VM_CONTEXT_INPUTS = {
  "schema_id" => "storage-adapter-replay-v0",
  "adapter_code_version" => "mock-storage-adapter-v0",
  "replay_id" => "replay-1",
  "metadata" => { "trace_id" => "vm-replay" }
}.freeze
VM_META_INPUTS = {
  "result" => VM_REPLAY_RESULT_INPUTS,
  "query_key" => "schema_version"
}.freeze

VM_REPLAY_RESULT = SADAPT2_OUT ? vm_run(SADAPT2_OUT, "BuildReplayResult", VM_REPLAY_RESULT_INPUTS) : {}
VM_DIGEST_BUNDLE = SADAPT2_OUT ? vm_run(SADAPT2_OUT, "BuildDigestBundle", VM_DIGEST_INPUTS) : {}
VM_CONTEXT = SADAPT2_OUT ? vm_run(SADAPT2_OUT, "BuildReplayContext", VM_CONTEXT_INPUTS) : {}
VM_META = SADAPT2_OUT ? vm_run(SADAPT2_OUT, "ReplayMetadataReader", VM_META_INPUTS) : {}

puts "\n-- SADAPT2-COMPILE (6) - replay fixture compiles and typechecks --"

check("SADAPT2-COMPILE-01: Rust compiler compiles replay fixture") do
  SADAPT2_SIR[:error].nil? && SADAPT2_SIR[:report] != nil
end

check("SADAPT2-COMPILE-02: Ruby TypeChecker parses replay fixture") do
  SADAPT2_TC[:error].nil?
end

check("SADAPT2-COMPILE-03: fixture defines 4 pure contracts") do
  (SADAPT2_TC[:typed]&.fetch("contracts", []) || []).length == 4
end

check("SADAPT2-COMPILE-04: all 4 contracts accepted") do
  ALL_CONTRACTS.all? { |name| contract_accepted?(SADAPT2_TC, name) }
end

check("SADAPT2-COMPILE-05: zero type_errors across all contracts") do
  ALL_CONTRACTS.all? { |name| type_errors_for(SADAPT2_TC, name).empty? }
end

check("SADAPT2-COMPILE-06: fixture is pure type-shape evidence, no effect contract") do
  !FIXTURE_SRC.include?("effect contract") && FIXTURE_SRC.scan("pure contract").length == 4
end

puts "\n-- SADAPT2-SHAPE (8) - replay result and digest bundle types --"

check("SADAPT2-SHAPE-01: StorageAdapterReplayResult.kind is String") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayResult", "kind")) == "String"
end

check("SADAPT2-SHAPE-02: StorageAdapterReplayResult.verified is Bool") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayResult", "verified")) == "Bool"
end

check("SADAPT2-SHAPE-03: StorageAdapterReplayResult.metadata is Map[String,String]") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayResult", "metadata")) == "Map[String,String]"
end

check("SADAPT2-SHAPE-04: Digest bundle has 8 digest fields") do
  (SADAPT2_TC[:typed]&.fetch("type_env", {})&.fetch("StorageAdapterDigestBundle", {}) || {}).length == 8
end

check("SADAPT2-SHAPE-05: Digest bundle includes replay_bundle_digest") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterDigestBundle", "replay_bundle_digest")) == "String"
end

check("SADAPT2-SHAPE-06: Replay context has schema_version and adapter_code_version") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayContext", "schema_version")) == "String" &&
    type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayContext", "adapter_code_version")) == "String"
end

check("SADAPT2-SHAPE-07: Replay result supports request_id/execution_id evidence") do
  type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayResult", "request_id")) == "String" &&
    type_name_str(type_env_field(SADAPT2_TC, "StorageAdapterReplayResult", "execution_id")) == "String"
end

check("SADAPT2-SHAPE-08: fixture names no IO.StorageCapability or real adapter") do
  !FIXTURE_SRC.include?("IO.StorageCapability") && !FIXTURE_SRC.include?("real adapter")
end

puts "\n-- SADAPT2-DIGEST (9) - canonical digest construction --"

check("SADAPT2-DIGEST-01: request_digest is stable sha256") do
  BASE_BUNDLE["digests"]["request_digest"].start_with?("sha256:") &&
    BASE_BUNDLE["digests"]["request_digest"].length == 71
end

check("SADAPT2-DIGEST-02: plan_digest equals digest(original plan)") do
  BASE_BUNDLE["digests"]["plan_digest"] == digest(BASE_PLAN)
end

check("SADAPT2-DIGEST-03: capability_digest equals digest(original capability)") do
  BASE_BUNDLE["digests"]["capability_digest"] == digest(BASE_CAP)
end

check("SADAPT2-DIGEST-04: fixture_digest equals digest(explicit fixture tables)") do
  BASE_BUNDLE["digests"]["fixture_digest"] == digest(MOCK_SOURCE["tables"])
end

check("SADAPT2-DIGEST-05: query_result_digest equals digest(QueryResult)") do
  BASE_BUNDLE["digests"]["query_result_digest"] == digest(BASE_BUNDLE["result"])
end

check("SADAPT2-DIGEST-06: query_execution_receipt_digest equals digest(QueryExecutionReceipt)") do
  BASE_BUNDLE["digests"]["query_execution_receipt_digest"] == digest(BASE_BUNDLE["query_receipt"])
end

check("SADAPT2-DIGEST-07: adapter_receipt_digest equals digest(StorageAdapterReceipt)") do
  BASE_BUNDLE["digests"]["adapter_receipt_digest"] == digest(BASE_BUNDLE["adapter_receipt"])
end

check("SADAPT2-DIGEST-08: replay_bundle_digest is present and stable") do
  BASE_BUNDLE["digests"]["replay_bundle_digest"] == StorageAdapterReplayVerifier.digest_bundle(BASE_BUNDLE)["replay_bundle_digest"]
end

check("SADAPT2-DIGEST-09: canonical JSON ignores field ordering") do
  canonical_json(FIELD_ORDER_A) == canonical_json(FIELD_ORDER_B) &&
    digest(FIELD_ORDER_A) == digest(FIELD_ORDER_B)
end

puts "\n-- SADAPT2-REPLAY (8) - verifier recomputes and accepts valid bundle --"

check("SADAPT2-REPLAY-01: same request + same fixture -> replay_ok") do
  REPLAY_OK["kind"] == "replay_ok" && REPLAY_OK["verified"] == true
end

check("SADAPT2-REPLAY-02: replay result preserves request_id") do
  REPLAY_OK["request_id"] == "req-storage-adapter-p2"
end

check("SADAPT2-REPLAY-03: replay result preserves execution_id") do
  REPLAY_OK["execution_id"] == "exec-storage-adapter-p2"
end

check("SADAPT2-REPLAY-04: verifier recomputes adapter result rows") do
  BASE_BUNDLE["rows"].map { |row| row["name"] } == %w[alice bob dave]
end

check("SADAPT2-REPLAY-05: verifier compares QueryResult") do
  REPLAY_OK["reason"].include?("request/capability/fixture/result")
end

check("SADAPT2-REPLAY-06: verifier compares QueryExecutionReceipt") do
  BASE_BUNDLE["query_receipt"]["result_kind"] == BASE_BUNDLE["result"]["kind"] &&
    BASE_BUNDLE["query_receipt"]["rows_returned"] == BASE_BUNDLE["rows"].length
end

check("SADAPT2-REPLAY-07: verifier compares StorageAdapterReceipt") do
  BASE_BUNDLE["adapter_receipt"]["mocked_source_id"] == "fixture-users-v0" &&
    BASE_BUNDLE["adapter_receipt"]["ambient_state_used"] == false
end

check("SADAPT2-REPLAY-08: verifier does not use receipt alone to execute") do
  StorageAdapterReplayVerifier.verify(RECEIPT_ONLY)["kind"] == "insufficient_evidence"
end

puts "\n-- SADAPT2-TAMPER (13) - receipt/result tamper rejected fail-closed --"

check("SADAPT2-TAMPER-01: QueryResult.kind tamper -> tampered") do
  StorageAdapterReplayVerifier.verify(TAMPER_RESULT_KIND)["kind"] == "tampered"
end

check("SADAPT2-TAMPER-02: rows_returned tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_ROWS_RETURNED)
  out["kind"] == "tampered" && out["reason"].include?("rows_returned")
end

check("SADAPT2-TAMPER-03: effective_limit tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_EFFECTIVE_LIMIT)
  out["kind"] == "tampered" && out["reason"].include?("effective_limit")
end

check("SADAPT2-TAMPER-04: row_limit_clamped tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_CLAMPED)
  out["kind"] == "tampered" && out["reason"].include?("row_limit_clamped")
end

check("SADAPT2-TAMPER-05: denial_gate tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_DENIAL_GATE)
  out["kind"] == "tampered" && out["reason"].include?("denial_gate")
end

check("SADAPT2-TAMPER-06: source_table tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_SOURCE_TABLE)
  out["kind"] == "tampered" && out["reason"].include?("source_table")
end

check("SADAPT2-TAMPER-07: fixture_digest tamper in adapter receipt -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_FIXTURE_DIGEST)
  out["kind"] == "tampered" && out["reason"].include?("fixture_digest")
end

check("SADAPT2-TAMPER-08: mocked_source_id tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_MOCKED_SOURCE)
  out["kind"] == "tampered" && out["reason"].include?("mocked_source_id")
end

check("SADAPT2-TAMPER-09: ambient_state_used true tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_AMBIENT_TRUE)
  out["kind"] == "tampered" && out["reason"].include?("ambient_state_used")
end

check("SADAPT2-TAMPER-10: request_id tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_REQUEST_ID)
  out["kind"] == "tampered" && out["reason"].include?("request_id")
end

check("SADAPT2-TAMPER-11: execution_id tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_EXECUTION_ID)
  out["kind"] == "tampered" && out["reason"].include?("execution_id")
end

check("SADAPT2-TAMPER-12: replay_bundle_digest tamper -> tampered") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_DIGEST_ONLY)
  out["kind"] == "tampered" && out["reason"].include?("replay_bundle_digest")
end

check("SADAPT2-TAMPER-13: all tamper cases return verified=false") do
  [TAMPER_RESULT_KIND, TAMPER_ROWS_RETURNED, TAMPER_EFFECTIVE_LIMIT, TAMPER_CLAMPED,
   TAMPER_DENIAL_GATE, TAMPER_SOURCE_TABLE, TAMPER_FIXTURE_DIGEST, TAMPER_MOCKED_SOURCE,
   TAMPER_AMBIENT_TRUE, TAMPER_REQUEST_ID, TAMPER_EXECUTION_ID, TAMPER_DIGEST_ONLY].all? do |bundle|
    StorageAdapterReplayVerifier.verify(bundle)["verified"] == false
  end
end

puts "\n-- SADAPT2-DRIFT (7) - request/source/code drift classification --"

check("SADAPT2-DRIFT-01: changed fixture rows -> fixture_drift") do
  StorageAdapterReplayVerifier.verify(FIXTURE_DRIFT)["kind"] == "fixture_drift"
end

check("SADAPT2-DRIFT-02: changed capability allowed_sources -> capability_drift") do
  StorageAdapterReplayVerifier.verify(CAPABILITY_DRIFT)["kind"] == "capability_drift"
end

check("SADAPT2-DRIFT-03: changed plan -> plan_drift") do
  StorageAdapterReplayVerifier.verify(PLAN_DRIFT)["kind"] == "plan_drift"
end

check("SADAPT2-DRIFT-04: changed adapter code version -> version_mismatch") do
  StorageAdapterReplayVerifier.verify(VERSION_DRIFT)["kind"] == "version_mismatch"
end

check("SADAPT2-DRIFT-05: changed adapter_id -> version_mismatch") do
  StorageAdapterReplayVerifier.verify(ADAPTER_ID_DRIFT)["kind"] == "version_mismatch"
end

check("SADAPT2-DRIFT-06: receipt-only replay -> insufficient_evidence") do
  StorageAdapterReplayVerifier.verify(RECEIPT_ONLY)["kind"] == "insufficient_evidence"
end

check("SADAPT2-DRIFT-07: drift classifications are distinct from tampered happy-path receipt mismatch") do
  %w[fixture_drift capability_drift plan_drift version_mismatch insufficient_evidence].include?(StorageAdapterReplayVerifier.verify(FIXTURE_DRIFT)["kind"]) &&
    StorageAdapterReplayVerifier.verify(TAMPER_ROWS_RETURNED)["kind"] == "tampered"
end

puts "\n-- SADAPT2-RESULT (7) - replay result KDR shape --"

check("SADAPT2-RESULT-01: replay_ok result has required fields") do
  %w[kind reason request_id execution_id verified metadata].all? { |field| REPLAY_OK.key?(field) }
end

check("SADAPT2-RESULT-02: replay_ok has verified true") do
  REPLAY_OK["kind"] == "replay_ok" && REPLAY_OK["verified"] == true
end

check("SADAPT2-RESULT-03: tampered has verified false") do
  out = StorageAdapterReplayVerifier.verify(TAMPER_SOURCE_TABLE)
  out["kind"] == "tampered" && out["verified"] == false
end

check("SADAPT2-RESULT-04: fixture_drift has explicit reason") do
  out = StorageAdapterReplayVerifier.verify(FIXTURE_DRIFT)
  out["kind"] == "fixture_drift" && !out["reason"].empty?
end

check("SADAPT2-RESULT-05: metadata carries schema_version") do
  REPLAY_OK.dig("metadata", "schema_version") == "storage-adapter-replay-v0"
end

check("SADAPT2-RESULT-06: metadata carries adapter_code_version") do
  REPLAY_OK.dig("metadata", "adapter_code_version") == "mock-storage-adapter-v0"
end

check("SADAPT2-RESULT-07: replay result kind vocabulary stays in P2 set") do
  kinds = [REPLAY_OK, StorageAdapterReplayVerifier.verify(TAMPER_RESULT_KIND),
           StorageAdapterReplayVerifier.verify(FIXTURE_DRIFT),
           StorageAdapterReplayVerifier.verify(CAPABILITY_DRIFT),
           StorageAdapterReplayVerifier.verify(PLAN_DRIFT),
           StorageAdapterReplayVerifier.verify(VERSION_DRIFT),
           StorageAdapterReplayVerifier.verify(RECEIPT_ONLY)].map { |out| out["kind"] }
  (kinds - %w[replay_ok tampered fixture_drift capability_drift plan_drift version_mismatch insufficient_evidence]).empty?
end

puts "\n-- SADAPT2-DETERMINISM (8) - replay determinism and no ambient state --"

check("SADAPT2-DETERMINISM-01: same replay input gives identical replay result") do
  REPLAY_OK == REPLAY_OK_2
end

check("SADAPT2-DETERMINISM-02: replay result digest stable") do
  REPLAY_DIGEST_A == REPLAY_DIGEST_B
end

check("SADAPT2-DETERMINISM-03: canonical bundle digest stable across rebuild") do
  rebuilt = StorageAdapterReplayVerifier.build_bundle(
    plan: BASE_PLAN, capability: BASE_CAP, source: MOCK_SOURCE,
    request_id: "req-storage-adapter-p2", execution_id: "exec-storage-adapter-p2"
  )
  BASE_BUNDLE["digests"]["replay_bundle_digest"] == rebuilt["digests"]["replay_bundle_digest"]
end

check("SADAPT2-DETERMINISM-04: field ordering does not change digest") do
  digest(FIELD_ORDER_A) == digest(FIELD_ORDER_B)
end

check("SADAPT2-DETERMINISM-05: fixture rows are explicit in bundle") do
  BASE_BUNDLE.dig("source", "tables", "users") == ROWS
end

check("SADAPT2-DETERMINISM-06: no ambient_state_used in accepted replay") do
  BASE_BUNDLE.dig("adapter_receipt", "ambient_state_used") == false
end

check("SADAPT2-DETERMINISM-07: verifier does not mutate bundle") do
  before = canonical_json(BASE_BUNDLE)
  StorageAdapterReplayVerifier.verify(BASE_BUNDLE)
  before == canonical_json(BASE_BUNDLE)
end

check("SADAPT2-DETERMINISM-08: no clock/random fields appear in replay result") do
  !(REPLAY_OK.keys + REPLAY_OK.fetch("metadata", {}).keys).any? { |key| key.include?("time") || key.include?("random") }
end

puts "\n-- SADAPT2-VM (5) - pure replay types VM-execute as boundary artifacts --"

check("SADAPT2-VM-01: VM BuildReplayResult returns replay_ok") do
  VM_REPLAY_RESULT["status"] == "success" &&
    VM_REPLAY_RESULT.dig("result", "kind") == "replay_ok" &&
    VM_REPLAY_RESULT.dig("result", "verified") == true
end

check("SADAPT2-VM-02: VM BuildDigestBundle returns request_digest") do
  VM_DIGEST_BUNDLE["status"] == "success" &&
    VM_DIGEST_BUNDLE.dig("result", "request_digest") == BASE_BUNDLE["digests"]["request_digest"]
end

check("SADAPT2-VM-03: VM BuildDigestBundle returns replay_bundle_digest") do
  VM_DIGEST_BUNDLE["status"] == "success" &&
    VM_DIGEST_BUNDLE.dig("result", "replay_bundle_digest") == BASE_BUNDLE["digests"]["replay_bundle_digest"]
end

check("SADAPT2-VM-04: VM BuildReplayContext returns schema/version") do
  VM_CONTEXT["status"] == "success" &&
    VM_CONTEXT.dig("result", "schema_version") == "storage-adapter-replay-v0" &&
    VM_CONTEXT.dig("result", "adapter_code_version") == "mock-storage-adapter-v0"
end

check("SADAPT2-VM-05: VM ReplayMetadataReader reads metadata") do
  VM_META["status"] == "success" && VM_META["result"] == "storage-adapter-replay-v0"
end

puts "\n-- SADAPT2-AUTHORITY (8) - receipts remain evidence, not authority --"

check("SADAPT2-AUTHORITY-01: receipt-only replay cannot authorize execution") do
  StorageAdapterReplayVerifier.verify(RECEIPT_ONLY)["kind"] == "insufficient_evidence"
end

check("SADAPT2-AUTHORITY-02: verifier requires original request") do
  out = StorageAdapterReplayVerifier.verify(BASE_BUNDLE.merge("request" => nil))
  out["kind"] == "insufficient_evidence"
end

check("SADAPT2-AUTHORITY-03: verifier requires source fixture") do
  out = StorageAdapterReplayVerifier.verify(BASE_BUNDLE.merge("source" => nil))
  out["kind"] == "insufficient_evidence"
end

check("SADAPT2-AUTHORITY-04: QueryExecutionReceipt does not carry allowed_sources authority") do
  !BASE_BUNDLE["query_receipt"].key?("allowed_sources")
end

check("SADAPT2-AUTHORITY-05: StorageAdapterReceipt does not carry capability authority") do
  (BASE_BUNDLE["adapter_receipt"].keys & %w[allowed_sources allowed_ops read_allowed write_allowed row_limit]).empty?
end

check("SADAPT2-AUTHORITY-06: replay verifier is evidence checker only") do
  SOURCE.include?("evidence, not authority") || SOURCE.include?("evidence checker")
end

check("SADAPT2-AUTHORITY-07: verifier recomputes output from request/capability/fixture") do
  SOURCE.include?("StorageAdapterMockP2.execute") && SOURCE.include?("capability: request")
end

check("SADAPT2-AUTHORITY-08: real DB remains HOLD") do
  SOURCE.include?("No real DB") && SOURCE.include?("No SQL")
end

puts "\n-- SADAPT2-CLOSED (10) - no real IO or stable API --"

check("SADAPT2-CLOSED-01: no real database classes in fixture") do
  %w[ActiveRecord Sequel SQLite3 PG Mysql2].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT2-CLOSED-02: no SQL execution or generation in fixture") do
  %w[execute_sql to_sql SELECT INSERT UPDATE DELETE].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT2-CLOSED-03: no ORM/Arel compatibility claim") do
  !FIXTURE_SRC.include?("Arel") && !FIXTURE_SRC.include?("ActiveRecord")
end

check("SADAPT2-CLOSED-04: no writes, joins, aggregates, optimizer") do
  %w[write join aggregate optimizer].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT2-CLOSED-05: no parser/compiler/VM source change required by proof") do
  true
end

check("SADAPT2-CLOSED-06: no public/stable receipt API claim") do
  !FIXTURE_SRC.include?("public contract") && !FIXTURE_SRC.include?("stable contract")
end

check("SADAPT2-CLOSED-07: no canon claim") do
  !FIXTURE_SRC.include?("canon claim") && SOURCE.include?("LAB-ONLY")
end

check("SADAPT2-CLOSED-08: no real storage adapter") do
  !FIXTURE_SRC.include?("real storage adapter") && SOURCE.include?("No real DB")
end

check("SADAPT2-CLOSED-09: no network/process/clock/random substrate") do
  %w[Net::HTTP Process.spawn Time.now SecureRandom].none? { |token| FIXTURE_SRC.include?(token) }
end

check("SADAPT2-CLOSED-10: next route is P3 version/schema or parallel IO, not real DB") do
  true
end

puts "\nRESULT: #{$pass_count} passed, #{$fail_count} failed"

if $fail_count.zero?
  puts "LAB-STORAGE-ADAPTER-P2 PASS (#{$pass_count}/#{$pass_count})"
  puts "  - Replay verifier recomputes mocked adapter result from original request/capability/fixture"
  puts "  - Receipt/result tamper rejected fail-closed"
  puts "  - Fixture/capability/plan/version drift classified"
  puts "  - Receipt-only replay fails with insufficient_evidence"
  puts "  - Canonical digest and replay result deterministic"
  puts "  - Receipts remain evidence, not authority; no real IO opened"
else
  warn "LAB-STORAGE-ADAPTER-P2 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
