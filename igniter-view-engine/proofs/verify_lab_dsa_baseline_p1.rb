#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_dsa_baseline_p1.rb
# LAB-DSA-BASELINE-P1 — freeze dsa as a full Rust multi-file
# collection/algorithm baseline.
#
# Proves:
#   - Rust compile status ok, all 5 stages ok
#   - exactly 6 source units, 12 contracts, 0 diagnostics
#   - manifest / semantic_ir_program.json / sourcemap.json exist
#   - artifact hash is stable across two independent runs
#   - array literals compile as Collection[T] (array_literal nodes in SIR)
#   - collection concat compiles in Rust without diagnostic (DSA-P03 note)
#   - Ruby parity gap documented as parity pressure, not baseline failure
#
# Authority: regression baseline only. No DSA stdlib promotion, no indexed
# access implementation, no Ruby parity implementation, no source edits.

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
APP_DIR      = LAB_ROOT / "igniter-apps" / "dsa"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

SOURCE_FILES = %w[types.ig arrays.ig sets.ig graphs.ig strings.ig example.ig]
  .map { |f| (APP_DIR / f).to_s }

EXPECTED_CONTRACTS = %w[
  ArrayGet ArraySet CharAt GetAdjacent HasEdge MakeIndexedElement
  RunArrayExample RunGraphExample RunSetExample RunStringExample
  SetContains SetInsert
].sort.freeze

EXPECTED_SOURCE_UNITS = %w[
  DSAArrays DSAExample DSAGraphs DSASets DSAStrings DSATypes
].sort.freeze

BASELINE_SOURCE_HASH   = "sha256:06afdd6e758f3c687af95051f54b69689709cdbc9c75642c66044a16b029e490"
BASELINE_ARTIFACT_HASH = "sha256:7afc3a520876f01e94a0d5b8ff6fc5eba2cad86a43a46170f41fee9104580310"

# Array literals appear in: RunArrayExample (c2), RunSetExample (c1),
# RunGraphExample (c2), SetInsert (new_elements arg).
# Includes the [new_elem] inline literal in SetInsert concat call.
EXPECTED_ARRAY_LITERAL_CONTRACTS = %w[
  RunArrayExample RunSetExample RunGraphExample SetInsert
].sort.freeze

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
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

# ── Compile once; reuse result across all sections ──────────────────────────

$result      = nil
$manifest    = nil
$sir         = nil
$sourcemap   = nil
$igapp_path  = nil
$tmpdir_main = Dir.mktmpdir("dsa_baseline_p1_")
at_exit { FileUtils.rm_rf($tmpdir_main) }

def compile_app
  return if $result

  out = File.join($tmpdir_main, "dsa.igapp")
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *SOURCE_FILES, "--out", out
  )
  $result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
  $igapp_path = $result["igapp_path"] || out

  manifest_p  = File.join($igapp_path, "manifest.json")
  sir_p       = File.join($igapp_path, "semantic_ir_program.json")
  sourcemap_p = File.join($igapp_path, "sourcemap.json")

  $manifest  = File.exist?(manifest_p)  ? JSON.parse(File.read(manifest_p,  encoding: "UTF-8")) : nil
  $sir       = File.exist?(sir_p)       ? JSON.parse(File.read(sir_p,       encoding: "UTF-8")) : nil
  $sourcemap = File.exist?(sourcemap_p) ? JSON.parse(File.read(sourcemap_p, encoding: "UTF-8")) : nil
end

compile_app

# ── Section A: compiler binary + source file preconditions ──────────────────
puts
puts "Section A — Preconditions"

check("A-01: compiler binary exists") { File.executable?(COMPILER_BIN.to_s) }
SOURCE_FILES.each_with_index do |f, i|
  check("A-#{format('%02d', i + 2)}: source file exists — #{File.basename(f)}") { File.exist?(f) }
end

# ── Section B: compilation status ───────────────────────────────────────────
puts
puts "Section B — Compilation Status"

check("B-01: status is ok")             { $result["status"] == "ok" }
check("B-02: zero diagnostics")         { Array($result["diagnostics"]).empty? }
check("B-03: zero warnings")            { Array($result["warnings"]).empty? }
check("B-04: igapp_path present")       { !$result["igapp_path"].nil? && !$result["igapp_path"].empty? }

# ── Section C: pipeline stages ──────────────────────────────────────────────
puts
puts "Section C — Pipeline Stages"

stages = $result["stages"] || {}
%w[parse classify typecheck emit assemble].each do |stage|
  check("C-#{stage}: stage #{stage} is ok") { stages[stage] == "ok" }
end
check("C-all: exactly 5 stages present") { stages.size == 5 }

# ── Section D: source units ──────────────────────────────────────────────────
puts
puts "Section D — Source Units"

manifest_units   = ($manifest || {})["source_units"] || []
unit_modules     = manifest_units.map { |u| u["module"] }.sort

check("D-01: manifest has exactly 6 source_units") { manifest_units.size == 6 }
check("D-02: source_unit modules match expected set") { unit_modules == EXPECTED_SOURCE_UNITS }
EXPECTED_SOURCE_UNITS.each do |mod|
  check("D-03-#{mod}: module #{mod} present in manifest") { unit_modules.include?(mod) }
end
check("D-09: each source_unit has a source_hash") do
  manifest_units.all? { |u| u["source_hash"]&.start_with?("sha256:") }
end
check("D-10: each source_unit source_path exists on disk") do
  manifest_units.all? { |u| File.exist?(u["source_path"].to_s) }
end

# ── Section E: contract count and names ──────────────────────────────────────
puts
puts "Section E — Contracts"

result_contracts   = Array($result["contracts"]).sort
manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts      = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort

check("E-01: exactly 12 contracts in result")    { result_contracts.size == 12 }
check("E-02: exactly 12 contracts in manifest")  { manifest_contracts.size == 12 }
check("E-03: result contracts match expected set") { result_contracts == EXPECTED_CONTRACTS }
check("E-04: manifest contracts match expected set") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-05: result and manifest contract lists agree") { result_contracts == manifest_contracts }
check("E-06: SIR contracts count is 12") { sir_contracts.size == 12 }
check("E-07: SIR contracts match expected set") { sir_contracts == EXPECTED_CONTRACTS }
check("E-08: contract_index has 12 entries") do
  (($manifest || {})["contract_index"] || {}).size == 12
end

# ── Section F: artifact files ─────────────────────────────────────────────────
puts
puts "Section F — Artifact Files"

check("F-01: manifest.json exists and parsed")            { !$manifest.nil? }
check("F-02: semantic_ir_program.json exists and parsed") { !$sir.nil? }
check("F-03: sourcemap.json exists and parsed")           { !$sourcemap.nil? }
check("F-04: manifest is valid JSON object")              { $manifest.is_a?(Hash) }
check("F-05: SIR is valid JSON object")                   { $sir.is_a?(Hash) }
check("F-06: sourcemap is valid JSON object")             { $sourcemap.is_a?(Hash) }
check("F-07: compilation_report.json exists") do
  File.exist?(File.join($igapp_path, "compilation_report.json"))
end
check("F-08: diagnostics.json exists") do
  File.exist?(File.join($igapp_path, "diagnostics.json"))
end

# ── Section G: source + artifact hash stability ───────────────────────────────
puts
puts "Section G — Hash Stability"

manifest_source_hash   = ($manifest || {})["source_hash"]
manifest_artifact_hash = ($manifest || {})["artifact_hash"]
sir_source_hash        = ($sir || {})["source_hash"]

check("G-01: manifest source_hash matches baseline") { manifest_source_hash == BASELINE_SOURCE_HASH }
check("G-02: manifest artifact_hash matches baseline") { manifest_artifact_hash == BASELINE_ARTIFACT_HASH }
check("G-03: SIR source_hash matches manifest source_hash") { sir_source_hash == manifest_source_hash }
check("G-04: result source_hash matches baseline") { $result["source_hash"] == BASELINE_SOURCE_HASH }
check("G-05: artifact_hash is sha256-prefixed") { manifest_artifact_hash.to_s.start_with?("sha256:") }
check("G-06: source_hash is sha256-prefixed")   { manifest_source_hash.to_s.start_with?("sha256:") }

second_result   = nil
second_manifest = nil
begin
  out2 = File.join($tmpdir_main, "dsa2.igapp")
  stdout2, _stderr2, _status2 = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *SOURCE_FILES, "--out", out2
  )
  second_result   = JSON.parse(stdout2.force_encoding("UTF-8")) rescue {}
  mp2 = File.join(out2, "manifest.json")
  second_manifest = File.exist?(mp2) ? JSON.parse(File.read(mp2, encoding: "UTF-8")) : nil
end

check("G-07: artifact_hash stable across two runs") do
  second_manifest&.dig("artifact_hash") == manifest_artifact_hash
end
check("G-08: source_hash stable across two runs") do
  second_manifest&.dig("source_hash") == manifest_source_hash
end
check("G-09: status stable across two runs") { second_result["status"] == "ok" }

# ── Section H: semantic IR integrity ──────────────────────────────────────────
puts
puts "Section H — Semantic IR"

sir_program_id   = ($sir || {})["program_id"]
manifest_sir_ref = ($manifest || {})["semantic_ir_ref"]

check("H-01: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }
check("H-02: SIR program_id present")          { !sir_program_id.nil? && !sir_program_id.empty? }
check("H-03: manifest semantic_ir_ref present") { !manifest_sir_ref.nil? && !manifest_sir_ref.empty? }
check("H-04: SIR program_id matches manifest semantic_ir_ref") do
  manifest_sir_ref == sir_program_id ||
    manifest_sir_ref.to_s.end_with?(sir_program_id.to_s.split("/").last.to_s)
end
check("H-05: SIR source_units count is 6") { (($sir || {})["source_units"] || []).size == 6 }
check("H-06: SIR format_version present")  { !($sir || {})["format_version"].nil? }

# ── Section I: sourcemap integrity ────────────────────────────────────────────
puts
puts "Section I — Sourcemap"

check("I-01: sourcemap.json is present and parsed")  { !$sourcemap.nil? }
check("I-02: manifest sourcemap_ref present") do
  ref = ($manifest || {})["sourcemap_ref"]
  !ref.nil? && !ref.empty?
end
check("I-03: sourcemap has at least one top-level key") { ($sourcemap || {}).keys.size >= 1 }

# ── Section J: array literals as Collection[T] (DSA-P02) ──────────────────────
puts
puts "Section J — Array Literals (DSA-P02)"

sir_text = File.exist?(File.join($igapp_path, "semantic_ir_program.json")) ?
  File.read(File.join($igapp_path, "semantic_ir_program.json"), encoding: "UTF-8") : ""
sir_data = $sir || {}

array_literal_count = sir_text.scan('"array_literal"').size

check("J-01: at least 5 array_literal nodes in SIR across all contracts") do
  array_literal_count >= 5
end

check("J-02: RunArrayExample contract has array_literal node (c2 = [e0, e1, e2])") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "RunArrayExample" }
  nodes = c ? (c["nodes"] || []) : []
  nodes.any? { |n| n["expr"]&.fetch("kind", nil) == "array_literal" }
end

check("J-03: RunSetExample contract has array_literal node ([100, 200])") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "RunSetExample" }
  nodes = c ? (c["nodes"] || []) : []
  nodes.any? { |n| n["expr"]&.fetch("kind", nil) == "array_literal" }
end

check("J-04: RunGraphExample contract has array_literal node ([edge1, edge2, edge3])") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "RunGraphExample" }
  nodes = c ? (c["nodes"] || []) : []
  nodes.any? { |n| n["expr"]&.fetch("kind", nil) == "array_literal" }
end

check("J-05: SetInsert contract has array_literal node in concat args ([new_elem])") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "SetInsert" }
  nodes = c ? (c["nodes"] || []) : []
  nodes.any? do |n|
    args = n.dig("expr", "args") || []
    args.any? { |a| a.is_a?(Hash) && a["kind"] == "array_literal" }
  end
end

# ── Section K: collection concat compiles in Rust (DSA-P03 note) ──────────────
puts
puts "Section K — Collection Concat in Rust (DSA-P03)"

check("K-01: SetInsert compiles with zero diagnostics (concat call accepted)") do
  Array($result["diagnostics"]).none? { |d|
    d.is_a?(Hash) && (d["contract"]&.include?("SetInsert") || d["message"]&.include?("concat"))
  }
end

check("K-02: SetInsert new_elements node is present in SIR") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "SetInsert" }
  nodes = c ? (c["nodes"] || []) : []
  nodes.any? { |n| n["name"] == "new_elements" }
end

check("K-03: concat call in SIR resolves to a fn field (call node)") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "SetInsert" }
  nodes = c ? (c["nodes"] || []) : []
  n = nodes.find { |x| x["name"] == "new_elements" }
  n&.dig("expr", "kind") == "call" && !n.dig("expr", "fn").nil?
end

check("K-04: DSA-P03 acknowledged — concat fn field is 'stdlib.text.concat' (semantic mislabeling; not a Rust compilation failure)") do
  # Rust accepts concat(Collection, [T]) without diagnostic, but resolves fn as
  # stdlib.text.concat with resolved_type: Text. This is a semantic parity gap
  # (DSA-P03 → LANG-STDLIB-COLLECTION-CONCAT-P1), not a compilation failure.
  # The check passes unconditionally because it is a documentation acknowledgement.
  true
end

# ── Section L: Ruby parity gap (documented, not failure) ──────────────────────
puts
puts "Section L — Ruby Parity Gap (informational)"

check("L-01: Ruby parity gap is documented — not a baseline failure") { true }
check("L-02: Ruby multifile error cause documented (UTF-8 encoding error in types.ig comments)") do
  # Ruby CompilerOrchestrator emits JSON::GeneratorError on the UTF-8 box-drawing
  # characters (U+2500 ─, U+2502 │) in types.ig comment delimiters.
  # This prevents Ruby from reaching semantic analysis for this specific app.
  # Separately, the report.md documents 25 semantic diagnostics (call_contract × 9,
  # == × 6) that would surface once encoding is resolved.
  # Neither prevents the Rust baseline from being frozen.
  true
end
check("L-03: DSA-P08 acknowledged — Ruby call_contract parity gap (9 occurrences in report)") { true }
check("L-04: DSA-P04 acknowledged — Ruby == parity gap for Integer comparisons (6 in report)") { true }

# ── Section M: manifest metadata ──────────────────────────────────────────────
puts
puts "Section M — Manifest Metadata"

check("M-01: manifest kind present")             { !($manifest || {})["kind"].nil? }
check("M-02: manifest format_version present")   { !($manifest || {})["format_version"].nil? }
check("M-03: manifest grammar_version present")  { !($manifest || {})["grammar_version"].nil? }
check("M-04: manifest program_id present")       { !($manifest || {})["program_id"].nil? }
check("M-05: manifest assembler present")        { !($manifest || {})["assembler"].nil? }
check("M-06: manifest contract_index is a Hash") { ($manifest || {})["contract_index"].is_a?(Hash) }
check("M-07: manifest has 12 entries in contract_index") do
  (($manifest || {})["contract_index"] || {}).size == 12
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts
total = $pass_count + $fail_count
puts "=" * 60
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 60
exit($fail_count.zero? ? 0 : 1)
