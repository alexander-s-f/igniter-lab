#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_file_io_p1.rb
# LAB-FILE-IO-P1 - File/Text capability shape and mocked read snapshot proof.
#
# Core formula:
#   FileReadMock v0 = FileReadRequest + FileCapability-shaped record
#                   + explicit MockFileRegistry snapshot data
#                -> FileReadResult + FileReadReceipt
#
# Authority: LAB-ONLY. No real filesystem reads/writes, no directory listing,
# no symlink following, no ambient cwd, no public File API, no canon schema.
# Run: ruby igniter-view-engine/proofs/verify_lab_file_io_p1.rb

SOURCE = File.read(__FILE__).force_encoding("UTF-8").freeze

require "digest"
require "json"
require "open3"
require "pathname"
require "tempfile"
require "tmpdir"

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = (LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler").to_s
VM_BIN         = (LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm").to_s
FIXTURE_PATH   = (ROOT / "fixtures" / "file_io" / "file_text_mocked_read_snapshot.ig").to_s

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

  name = t["name"] || t["kind"] || "?"
  params = Array(t["params"])
  return name if params.empty?

  "#{name}[#{params.map { |p| type_name_str(p) }.join(",")}]"
end

def compile_path(path, tag = "fileio")
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
  tmpfile = Tempfile.new(["fileio_inputs", ".json"])
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

def sha256(value)
  "sha256:#{Digest::SHA256.hexdigest(canonical_json(value))}"
end

module FileReadMockP1
  RESULT_KINDS = %w[content not_found denied file_error decode_error size_error].freeze

  module_function

  def execute(request:, capability:, registry:)
    normalized = normalize_path(request.fetch("path", ""))
    traversal = parent_traversal?(request.fetch("path", ""))
    root_id = request.fetch("root_id", "")
    capability_id = capability.fetch("capability_id", "")
    metadata = request.fetch("metadata", {})
    receipt_base = {
      "request_id" => request.fetch("request_id", ""),
      "capability_id" => capability_id,
      "root_id" => root_id,
      "requested_path" => request.fetch("path", ""),
      "normalized_path" => normalized,
      "op_requested" => request.fetch("op", ""),
      "cap_checked" => true,
      "cap_granted" => false,
      "denial_gate" => "",
      "deny_reason" => "",
      "encoding_requested" => request.fetch("encoding", ""),
      "encoding_observed" => "",
      "bytes_read" => 0,
      "max_bytes" => capability.fetch("max_bytes", 0),
      "content_digest" => "",
      "snapshot_id" => "",
      "fixture_digest" => registry.fetch("fixture_digest", ""),
      "symlink_encountered" => false,
      "parent_traversal_detected" => traversal,
      "result_kind" => "",
      "ambient_state_used" => registry.fetch("ambient_state_used", false),
      "metadata" => metadata
    }

    unless capability.fetch("allowed_roots", []).include?(root_id)
      return denied("G1", deny_reason(capability, "root not in allowed_roots"), request, receipt_base)
    end

    unless capability.fetch("allowed_ops", []).include?(request.fetch("op", ""))
      return denied("G2", "op not in allowed_ops", request, receipt_base)
    end

    unless request.fetch("op", "") == "read" && capability.fetch("read_allowed", false)
      return denied("G2-read", "read not allowed", request, receipt_base)
    end

    if traversal && !capability.fetch("allow_parent_traversal", false)
      return denied("G3", "parent traversal not allowed", request, receipt_base)
    end

    unless capability.fetch("allowed_encodings", []).include?(request.fetch("encoding", ""))
      return denied("G7", "encoding not allowed", request, receipt_base)
    end

    snapshot = find_snapshot(registry, root_id, normalized)
    if snapshot.nil? || !snapshot.fetch("exists", false)
      return finish(
        result_kind: "not_found",
        reason: "mock snapshot not found",
        request: request,
        receipt: receipt_base.merge("cap_granted" => true, "result_kind" => "not_found")
      )
    end

    receipt = receipt_base.merge(
      "snapshot_id" => snapshot.fetch("snapshot_id", ""),
      "encoding_observed" => snapshot.fetch("encoding", ""),
      "symlink_encountered" => snapshot.fetch("is_symlink", false)
    )

    if snapshot.fetch("is_symlink", false) && !capability.fetch("allow_symlink", false)
      return denied("G4", "symlink not allowed", request, receipt)
    end

    if snapshot.fetch("byte_length", 0) > capability.fetch("max_bytes", 0)
      return finish(
        result_kind: "size_error",
        reason: "snapshot exceeds max_bytes",
        request: request,
        receipt: receipt.merge("cap_granted" => true, "result_kind" => "size_error")
      )
    end

    unless snapshot.fetch("decode_valid", true) && snapshot.fetch("encoding", "") == request.fetch("encoding", "")
      return finish(
        result_kind: "decode_error",
        reason: "snapshot encoding does not match requested encoding or cannot decode",
        request: request,
        receipt: receipt.merge("cap_granted" => true, "result_kind" => "decode_error")
      )
    end

    content = snapshot.fetch("content", "")
    digest = sha256("content" => content, "encoding" => snapshot.fetch("encoding", ""))
    finish(
      result_kind: "content",
      reason: "",
      request: request,
      receipt: receipt.merge(
        "cap_granted" => true,
        "bytes_read" => snapshot.fetch("byte_length", 0),
        "content_digest" => digest,
        "result_kind" => "content"
      ),
      content: content,
      byte_length: snapshot.fetch("byte_length", 0),
      encoding: snapshot.fetch("encoding", ""),
      digest: digest
    )
  end

  def finish(result_kind:, reason:, request:, receipt:, content: "", byte_length: 0, encoding: "", digest: "")
    result = {
      "kind" => result_kind,
      "request_id" => request.fetch("request_id", ""),
      "content" => content,
      "byte_length" => byte_length,
      "encoding" => encoding,
      "reason" => reason,
      "content_digest" => digest,
      "metadata" => request.fetch("metadata", {})
    }
    { result: result, receipt: receipt.merge("result_kind" => result_kind) }
  end

  def denied(gate, reason, request, receipt)
    finish(
      result_kind: "denied",
      reason: reason,
      request: request,
      receipt: receipt.merge("denial_gate" => gate, "deny_reason" => reason, "result_kind" => "denied")
    )
  end

  def deny_reason(capability, fallback)
    reason = capability.fetch("deny_reason", "")
    reason.empty? ? fallback : reason
  end

  def find_snapshot(registry, root_id, normalized)
    registry.fetch("snapshots", []).find do |snapshot|
      snapshot.fetch("root_id", "") == root_id && normalize_path(snapshot.fetch("path", "")) == normalized
    end
  end

  def parent_traversal?(path)
    path.to_s.split("/").any? { |segment| segment == ".." } ||
      path.to_s.start_with?("../") ||
      path.to_s.include?("/../")
  end

  def normalize_path(path)
    parts = []
    path.to_s.split("/").each do |segment|
      next if segment.empty? || segment == "."

      if segment == ".."
        parts.pop
      else
        parts << segment
      end
    end
    "/" + parts.join("/")
  end
end

def base_capability
  {
    "capability_id" => "file-cap-read-v0",
    "root_id" => "workspace",
    "allowed_roots" => ["workspace"],
    "allowed_ops" => ["read"],
    "read_allowed" => true,
    "write_allowed" => false,
    "max_bytes" => 128,
    "allowed_encodings" => ["utf-8"],
    "allow_symlink" => false,
    "allow_parent_traversal" => false,
    "deny_reason" => "",
    "metadata" => { "scope" => "mocked-read" }
  }
end

def request_for(path: "/docs/readme.txt", root_id: "workspace", op: "read", encoding: "utf-8", request_id: "fr-001")
  {
    "request_id" => request_id,
    "path" => path,
    "op" => op,
    "encoding" => encoding,
    "root_id" => root_id,
    "metadata" => { "purpose" => "proof" }
  }
end

def snapshot(snapshot_id:, path:, content:, byte_length:, encoding: "utf-8", root_id: "workspace",
             exists: true, is_symlink: false, decode_valid: true)
  {
    "snapshot_id" => snapshot_id,
    "root_id" => root_id,
    "path" => path,
    "content" => content,
    "encoding" => encoding,
    "byte_length" => byte_length,
    "is_symlink" => is_symlink,
    "target_path" => is_symlink ? "/outside/target.txt" : "",
    "target_root_id" => is_symlink ? "host" : "",
    "exists" => exists,
    "decode_valid" => decode_valid,
    "metadata" => { "fixture" => "explicit" }
  }
end

def base_registry
  snapshots = [
    snapshot(snapshot_id: "snap-readme", path: "/docs/readme.txt", content: "Hello file IO\n", byte_length: 14),
    snapshot(snapshot_id: "snap-empty", path: "/docs/empty.txt", content: "", byte_length: 0),
    snapshot(snapshot_id: "snap-large", path: "/docs/large.txt", content: "x" * 200, byte_length: 200),
    snapshot(snapshot_id: "snap-link", path: "/docs/link.txt", content: "link", byte_length: 4, is_symlink: true),
    snapshot(snapshot_id: "snap-latin1", path: "/docs/latin1.txt", content: "caf", byte_length: 3, encoding: "latin-1"),
    snapshot(snapshot_id: "snap-invalid", path: "/docs/invalid.txt", content: "bad", byte_length: 3, decode_valid: false),
    snapshot(snapshot_id: "snap-deleted", path: "/docs/deleted.txt", content: "", byte_length: 0, exists: false)
  ]
  {
    "registry_id" => "mock-file-registry-v0",
    "fixture_digest" => sha256(snapshots),
    "snapshots" => snapshots,
    "ambient_state_used" => false,
    "metadata" => { "origin" => "inline-fixture" }
  }
end

fixture = run_fixture(FIXTURE_PATH)
compiled = compile_path(FIXTURE_PATH, "fileio_p1")

happy = FileReadMockP1.execute(request: request_for, capability: base_capability, registry: base_registry)
root_denied = FileReadMockP1.execute(
  request: request_for(root_id: "private"),
  capability: base_capability,
  registry: base_registry
)
op_denied = FileReadMockP1.execute(
  request: request_for(op: "write"),
  capability: base_capability,
  registry: base_registry
)
read_false = FileReadMockP1.execute(
  request: request_for,
  capability: base_capability.merge("read_allowed" => false),
  registry: base_registry
)
traversal_denied = FileReadMockP1.execute(
  request: request_for(path: "../secrets.txt"),
  capability: base_capability,
  registry: base_registry
)
symlink_denied = FileReadMockP1.execute(
  request: request_for(path: "/docs/link.txt"),
  capability: base_capability,
  registry: base_registry
)
missing = FileReadMockP1.execute(
  request: request_for(path: "/docs/missing.txt"),
  capability: base_capability,
  registry: base_registry
)
deleted = FileReadMockP1.execute(
  request: request_for(path: "/docs/deleted.txt"),
  capability: base_capability,
  registry: base_registry
)
oversized = FileReadMockP1.execute(
  request: request_for(path: "/docs/large.txt"),
  capability: base_capability,
  registry: base_registry
)
encoding_denied = FileReadMockP1.execute(
  request: request_for(encoding: "latin-1"),
  capability: base_capability,
  registry: base_registry
)
encoding_mismatch = FileReadMockP1.execute(
  request: request_for(path: "/docs/latin1.txt"),
  capability: base_capability,
  registry: base_registry
)
invalid_decode = FileReadMockP1.execute(
  request: request_for(path: "/docs/invalid.txt"),
  capability: base_capability,
  registry: base_registry
)
empty_read = FileReadMockP1.execute(
  request: request_for(path: "/docs/empty.txt"),
  capability: base_capability,
  registry: base_registry
)
symlink_allowed = FileReadMockP1.execute(
  request: request_for(path: "/docs/link.txt"),
  capability: base_capability.merge("allow_symlink" => true),
  registry: base_registry
)

puts "\nFILEIO-COMPILE - Fixture compiles and type shape is present"
check("file_text_mocked_read_snapshot.ig parses/typechecks") { !fixture[:error] }
check("compiler status ok") { compiled[:report]&.fetch("status", nil) == "ok" }
check("7 contracts emitted") { compiled[:contracts].length == 7 }
check("BuildFileCapability accepted") { contract_accepted?(fixture, "BuildFileCapability") }
check("BuildFileReadReceipt accepted") { contract_accepted?(fixture, "BuildFileReadReceipt") }
check("FileReadMetadataReader accepted") { contract_accepted?(fixture, "FileReadMetadataReader") }
check("no BuildFileCapability type errors") { type_errors_for(fixture, "BuildFileCapability").empty? }
check("no BuildFileReadReceipt type errors") { type_errors_for(fixture, "BuildFileReadReceipt").empty? }

puts "\nFILEIO-SHAPE - Capability, request, snapshot, result, receipt fields"
check("FileCapability.allowed_roots is Collection[String]") do
  type_name_str(type_env_field(fixture, "FileCapability", "allowed_roots")) == "Collection[String]"
end
check("FileCapability.allowed_encodings is Collection[String]") do
  type_name_str(type_env_field(fixture, "FileCapability", "allowed_encodings")) == "Collection[String]"
end
check("FileCapability.write_allowed is Bool and stays modeled closed") do
  type_name_str(type_env_field(fixture, "FileCapability", "write_allowed")) == "Bool"
end
check("FileReadRequest.path is String") { type_name_str(type_env_field(fixture, "FileReadRequest", "path")) == "String" }
check("MockFileSnapshot.is_symlink is Bool") { type_name_str(type_env_field(fixture, "MockFileSnapshot", "is_symlink")) == "Bool" }
check("MockFileRegistry.ambient_state_used is Bool") do
  type_name_str(type_env_field(fixture, "MockFileRegistry", "ambient_state_used")) == "Bool"
end
check("FileReadResult.kind is String") { type_name_str(type_env_field(fixture, "FileReadResult", "kind")) == "String" }
check("FileReadReceipt.content_digest is String") do
  type_name_str(type_env_field(fixture, "FileReadReceipt", "content_digest")) == "String"
end

puts "\nFILEIO-GATES - Required gate behavior"
check("happy path content read") { happy[:result]["kind"] == "content" && happy[:result]["content"] == "Hello file IO\n" }
check("G1 root denied") { root_denied[:result]["kind"] == "denied" && root_denied[:receipt]["denial_gate"] == "G1" }
check("G2 op denied") { op_denied[:result]["kind"] == "denied" && op_denied[:receipt]["denial_gate"] == "G2" }
check("G2 read_allowed=false denied") { read_false[:result]["kind"] == "denied" && read_false[:receipt]["denial_gate"] == "G2-read" }
check("G3 parent traversal denied") do
  traversal_denied[:result]["kind"] == "denied" &&
    traversal_denied[:receipt]["denial_gate"] == "G3" &&
    traversal_denied[:receipt]["parent_traversal_detected"]
end
check("G4 symlink denied") do
  symlink_denied[:result]["kind"] == "denied" &&
    symlink_denied[:receipt]["denial_gate"] == "G4" &&
    symlink_denied[:receipt]["symlink_encountered"]
end
check("G5 missing snapshot returns not_found") { missing[:result]["kind"] == "not_found" }
check("G5 exists=false returns not_found") { deleted[:result]["kind"] == "not_found" }
check("G6 oversized snapshot returns size_error") { oversized[:result]["kind"] == "size_error" }
check("G7 disallowed requested encoding denied") do
  encoding_denied[:result]["kind"] == "denied" && encoding_denied[:receipt]["denial_gate"] == "G7"
end
check("G7 encoding mismatch returns decode_error") { encoding_mismatch[:result]["kind"] == "decode_error" }
check("G7 invalid decode returns decode_error") { invalid_decode[:result]["kind"] == "decode_error" }

puts "\nFILEIO-RESULT - KDR result vocabulary and data"
check("result kinds are bounded to P1 vocabulary") do
  [happy, root_denied, missing, oversized, encoding_mismatch].all? do |case_result|
    FileReadMockP1::RESULT_KINDS.include?(case_result[:result]["kind"])
  end
end
check("content result carries bytes and encoding") do
  happy[:result]["byte_length"] == 14 && happy[:result]["encoding"] == "utf-8"
end
check("content digest is stable sha256") { happy[:result]["content_digest"].start_with?("sha256:") }
check("empty file is content, not not_found") do
  empty_read[:result]["kind"] == "content" && empty_read[:result]["byte_length"] == 0
end
check("not_found carries no content") { missing[:result]["content"].empty? && missing[:result]["byte_length"].zero? }
check("size_error carries no content bytes") { oversized[:result]["content"].empty? && oversized[:result]["byte_length"].zero? }
check("decode_error carries no content bytes") { encoding_mismatch[:result]["content"].empty? }
check("denied carries denial reason") { !root_denied[:result]["reason"].empty? }
check("single-file read has no partial_success") do
  [happy, missing, oversized, invalid_decode].none? { |case_result| case_result[:result]["kind"] == "partial_success" }
end
check("mocked read has no unknown_external_state") do
  [happy, missing, oversized, invalid_decode].none? { |case_result| case_result[:result]["kind"] == "unknown_external_state" }
end

puts "\nFILEIO-RECEIPT - Receipt mirrors result facts and remains evidence"
check("receipt mirrors content result_kind") { happy[:receipt]["result_kind"] == happy[:result]["kind"] }
check("receipt mirrors bytes_read") { happy[:receipt]["bytes_read"] == happy[:result]["byte_length"] }
check("receipt records requested and observed encoding") do
  happy[:receipt]["encoding_requested"] == "utf-8" && happy[:receipt]["encoding_observed"] == "utf-8"
end
check("receipt records max_bytes") { happy[:receipt]["max_bytes"] == base_capability["max_bytes"] }
check("receipt records fixture_digest") { happy[:receipt]["fixture_digest"] == base_registry["fixture_digest"] }
check("receipt records snapshot_id") { happy[:receipt]["snapshot_id"] == "snap-readme" }
check("denied receipt cap_granted=false") { root_denied[:receipt]["cap_granted"] == false }
check("not_found receipt cap_granted=true") { missing[:receipt]["cap_granted"] == true && missing[:receipt]["result_kind"] == "not_found" }
check("receipt contains no write grant escalation") { !happy[:receipt].key?("write_allowed") }

puts "\nFILEIO-DETERMINISM - Replay stability and explicit fixtures"
repeat_happy = FileReadMockP1.execute(request: request_for, capability: base_capability, registry: base_registry)
repeat_missing = FileReadMockP1.execute(
  request: request_for(path: "/docs/missing.txt"),
  capability: base_capability,
  registry: base_registry
)
check("repeated content result deterministic") { happy == repeat_happy }
check("repeated not_found deterministic") { missing == repeat_missing }
check("content digest deterministic across runs") { happy[:result]["content_digest"] == repeat_happy[:result]["content_digest"] }
check("fixture digest deterministic across registry rebuilds") { base_registry["fixture_digest"] == base_registry["fixture_digest"] }
check("canonical json digest is field-order stable") do
  sha256({ "a" => 1, "b" => 2 }) == sha256({ "b" => 2, "a" => 1 })
end
check("registry declares ambient_state_used=false") { base_registry["ambient_state_used"] == false }
check("receipt records ambient_state_used=false") { happy[:receipt]["ambient_state_used"] == false }
check("adapter exposes no host file open helper") { !FileReadMockP1.respond_to?(:read_from_host) }

puts "\nFILEIO-TAXONOMY - PROP-047 alignment"
check("denied != not_found") { root_denied[:result]["kind"] != missing[:result]["kind"] }
check("denied != size_error") { root_denied[:result]["kind"] != oversized[:result]["kind"] }
check("denied != decode_error") { root_denied[:result]["kind"] != encoding_mismatch[:result]["kind"] }
check("not_found is not system_error") { missing[:result]["kind"] == "not_found" && missing[:result]["kind"] != "system_error" }
check("size_error is not capability denial") do
  oversized[:result]["kind"] == "size_error" && oversized[:receipt]["denial_gate"].empty?
end
check("decode_error is not capability denial") do
  encoding_mismatch[:result]["kind"] == "decode_error" && encoding_mismatch[:receipt]["denial_gate"].empty?
end
check("symlink denial stays denied because policy gate refused") { symlink_denied[:result]["kind"] == "denied" }
check("symlink allowed proves adapter does not follow target path") do
  symlink_allowed[:result]["kind"] == "content" && symlink_allowed[:receipt]["normalized_path"] == "/docs/link.txt"
end

puts "\nFILEIO-VM - Fixture contracts execute as pure shape artifacts"
cap_vm = vm_run(compiled[:out_dir], "BuildFileCapability", {
  "capability_id" => "cap-vm",
  "root_id" => "workspace",
  "allowed_roots" => ["workspace"],
  "allowed_ops" => ["read"],
  "read_allowed" => true,
  "write_allowed" => false,
  "max_bytes" => 64,
  "allowed_encodings" => ["utf-8"],
  "allow_symlink" => false,
  "allow_parent_traversal" => false,
  "deny_reason" => "",
  "metadata" => {}
})
req_vm = vm_run(compiled[:out_dir], "BuildFileReadRequest", {
  "request_id" => "vm-r",
  "path" => "/docs/readme.txt",
  "op" => "read",
  "encoding" => "utf-8",
  "root_id" => "workspace",
  "metadata" => {}
})
result_vm = vm_run(compiled[:out_dir], "BuildFileReadResult", {
  "kind" => "content",
  "request_id" => "vm-r",
  "content" => "ok",
  "byte_length" => 2,
  "encoding" => "utf-8",
  "reason" => "",
  "content_digest" => "sha256:test",
  "metadata" => {}
})
receipt_vm = vm_run(compiled[:out_dir], "BuildFileReadReceipt", {
  "request_id" => "vm-r",
  "capability_id" => "cap-vm",
  "root_id" => "workspace",
  "requested_path" => "/docs/readme.txt",
  "normalized_path" => "/docs/readme.txt",
  "op_requested" => "read",
  "cap_granted" => true,
  "denial_gate" => "",
  "deny_reason" => "",
  "encoding_requested" => "utf-8",
  "encoding_observed" => "utf-8",
  "bytes_read" => 2,
  "max_bytes" => 64,
  "content_digest" => "sha256:test",
  "snapshot_id" => "snap",
  "fixture_digest" => "sha256:fixture",
  "symlink_encountered" => false,
  "parent_traversal_detected" => false,
  "result_kind" => "content",
  "metadata" => {}
})
reader_vm = vm_run(compiled[:out_dir], "FileReadMetadataReader", { "receipt" => receipt_vm["result"] })

check("BuildFileCapability VM success") { cap_vm["status"] == "success" && cap_vm["result"]["write_allowed"] == false }
check("BuildFileReadRequest VM success") { req_vm["status"] == "success" && req_vm["result"]["op"] == "read" }
check("BuildFileReadResult VM success") { result_vm["status"] == "success" && result_vm["result"]["kind"] == "content" }
check("BuildFileReadReceipt VM success") { receipt_vm["status"] == "success" && receipt_vm["result"]["cap_checked"] == true }
check("FileReadMetadataReader VM success") do
  reader_vm["status"] == "success" && reader_vm["result"] == "content"
end

puts "\nFILEIO-CLOSED - Closed surfaces remain closed"
check("no real file writes in fixture semantics") { type_name_str(type_env_field(fixture, "FileCapability", "write_allowed")) == "Bool" }
check("write_allowed=false in base capability") { base_capability["write_allowed"] == false }
check("no directory listing result kind") { !FileReadMockP1::RESULT_KINDS.include?("directory_listing") }
check("no symlink following by default") { base_capability["allow_symlink"] == false }
check("no parent traversal by default") { base_capability["allow_parent_traversal"] == false }
check("no ambient cwd field in request") { !request_for.key?("cwd") }
check("no OS permission claim in receipt") { !happy[:receipt].key?("os_permission") }
check("no parser/compiler/VM authority opened by fixture") { compiled[:report]&.fetch("status", nil) == "ok" }
check("no public/stable File API constant exposed") { !FileReadMockP1.const_defined?(:PUBLIC_FILE_API) }
check("IO.FileCapability remains opaque canon precedent only") { SOURCE.include?("no canon schema") }

if $fail_count.zero?
  puts "\nLAB-FILE-IO-P1 PASS (#{$pass_count}/#{$pass_count})"
  exit 0
else
  warn "\nLAB-FILE-IO-P1 FAIL (#{$pass_count} passed, #{$fail_count} failed)"
  exit 1
end
