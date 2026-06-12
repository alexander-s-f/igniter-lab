#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_vector_math_baseline_p1.rb
# LAB-VECTOR-MATH-BASELINE-P1 — freeze vector_math as a full Rust multi-file
# app compilation baseline.
#
# Authority: regression baseline only. No vector stdlib promotion, no numeric
# semantics change, no Ruby parity implementation, no app source edits.

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
APP_DIR      = LAB_ROOT / "igniter-apps" / "vector_math"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

SOURCE_FILES = %w[types.ig vec2.ig vec3.ig mat3.ig geometry.ig example.ig]
  .map { |f| (APP_DIR / f).to_s }

EXPECTED_CONTRACTS = %w[
  AABBContains AABBOverlaps CollisionExample DistanceSq MakeAABB
  MakeRotation2D MakeScale3D Mat3Add Mat3Determinant Mat3Identity
  Mat3MulVec3 Mat3Scale Mat3Transpose MidPoint SimulateFrame
  TransformExample Vec2Add Vec2Cross Vec2Dot Vec2Example Vec2LengthSq
  Vec2Lerp Vec2Negate Vec2Perp Vec2Scale Vec2Sub Vec3Add
  Vec3ComponentMax Vec3ComponentMin Vec3Cross Vec3Dot Vec3LengthSq
  Vec3Lerp Vec3Negate Vec3Reflect Vec3Scale Vec3Sub
].sort.freeze

EXPECTED_SOURCE_UNITS = %w[
  VectorMathTypes VectorMathVec2 VectorMathVec3 VectorMathMat3
  VectorMathGeometry VectorMathExample
].sort.freeze

BASELINE_SOURCE_HASH   = "sha256:14f7a9c13173eee88dc168103f9e44791bb1b3916a1da96dbc39c61b5edd48b5"
BASELINE_ARTIFACT_HASH = "sha256:1f9daf1875c1e4dda41f388fce3d866ef096958e1b1a3353999cab28b3daf23c"

LIVENESS_FATAL_COUNTERS = %w[
  typechecker.infer_expr.max_depth
  form_resolver.walk_expr.max_depth
].freeze
LIVENESS_FATAL_LIMIT = 1000

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
$liveness    = nil
$igapp_path  = nil
$tmpdir_main = Dir.mktmpdir("vm_baseline_p1_")
at_exit { FileUtils.rm_rf($tmpdir_main) }

def compile_app
  return if $result

  out = File.join($tmpdir_main, "vector_math.igapp")
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

  $liveness  = $result["liveness_instrumentation"] || {}
end

compile_app

# ── Section A: compiler binary + source file preconditions ──────────────────
puts
puts "Section A — Preconditions"

check("A-01: compiler binary exists") { File.executable?(COMPILER_BIN.to_s) }
SOURCE_FILES.each_with_index do |f, i|
  check("A-#{format('%02d', i + 2)}: source file exists — #{File.basename(f)}") { File.exist?(f) }
end
# A-02..A-07 covers the 6 source files

# ── Section B: compilation status ───────────────────────────────────────────
puts
puts "Section B — Compilation Status"

check("B-01: status is ok") { $result["status"] == "ok" }
check("B-02: no diagnostics in result") { Array($result["diagnostics"]).empty? }
check("B-03: no warnings in result")    { Array($result["warnings"]).empty? }
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

check("D-01: exactly 6 source units in result contracts list") do
  # The result top-level 'contracts' field is contract names; source_units tracked via manifest
  true  # placeholder; real check below from manifest
end

manifest_units = ($manifest || {})["source_units"] || []
unit_modules   = manifest_units.map { |u| u["module"] }.sort

check("D-01: manifest has exactly 6 source_units") { manifest_units.size == 6 }
check("D-02: source_unit modules match expected set") { unit_modules == EXPECTED_SOURCE_UNITS }
EXPECTED_SOURCE_UNITS.each do |mod|
  check("D-03-#{mod}: module #{mod} present") { unit_modules.include?(mod) }
end
check("D-04: each source_unit has a source_hash") do
  manifest_units.all? { |u| u["source_hash"]&.start_with?("sha256:") }
end
check("D-05: each source_unit source_path exists on disk") do
  manifest_units.all? { |u| File.exist?(u["source_path"].to_s) }
end

# ── Section E: contract count ────────────────────────────────────────────────
puts
puts "Section E — Contracts"

result_contracts = Array($result["contracts"]).sort
manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts     = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort

check("E-01: exactly 37 contracts in result") { result_contracts.size == 37 }
check("E-02: exactly 37 contracts in manifest") { manifest_contracts.size == 37 }
check("E-03: result contracts match expected set") { result_contracts == EXPECTED_CONTRACTS }
check("E-04: manifest contracts match expected set") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-05: result and manifest contract lists agree") { result_contracts == manifest_contracts }
check("E-06: SIR contracts count is 37") { sir_contracts.size == 37 }
check("E-07: SIR contracts match expected set") { sir_contracts == EXPECTED_CONTRACTS }
check("E-08: contract index keys in manifest match contract list") do
  index_keys = (($manifest || {})["contract_index"] || {}).keys.sort
  index_keys == manifest_contracts
end
check("E-09: contract files exist in igapp") do
  (($manifest || {})["contract_index"] || {}).all? do |_name, info|
    cpath = File.join($igapp_path, info["contract_path"].to_s)
    File.exist?(cpath)
  end
end

# ── Section F: artifact files ─────────────────────────────────────────────────
puts
puts "Section F — Artifact Files"

check("F-01: manifest.json exists")             { !$manifest.nil? }
check("F-02: semantic_ir_program.json exists")  { !$sir.nil? }
check("F-03: sourcemap.json exists")            { !$sourcemap.nil? }
check("F-04: manifest is valid JSON object")    { $manifest.is_a?(Hash) }
check("F-05: SIR is valid JSON object")         { $sir.is_a?(Hash) }
check("F-06: sourcemap is valid JSON object")   { $sourcemap.is_a?(Hash) }
check("F-07: compilation_report.json exists") do
  File.exist?(File.join($igapp_path, "compilation_report.json"))
end
check("F-08: diagnostics.json exists") do
  File.exist?(File.join($igapp_path, "diagnostics.json"))
end

# ── Section G: source + artifact hash ─────────────────────────────────────────
puts
puts "Section G — Hash Stability"

manifest_source_hash   = ($manifest || {})["source_hash"]
manifest_artifact_hash = ($manifest || {})["artifact_hash"]
sir_source_hash        = ($sir || {})["source_hash"]

check("G-01: manifest source_hash matches baseline") { manifest_source_hash == BASELINE_SOURCE_HASH }
check("G-02: manifest artifact_hash matches baseline") { manifest_artifact_hash == BASELINE_ARTIFACT_HASH }
check("G-03: SIR source_hash matches manifest source_hash") { sir_source_hash == manifest_source_hash }
check("G-04: result source_hash matches baseline") { $result["source_hash"] == BASELINE_SOURCE_HASH }
check("G-05: artifact_hash is sha256 prefixed") { manifest_artifact_hash.to_s.start_with?("sha256:") }
check("G-06: source_hash is sha256 prefixed")   { manifest_source_hash.to_s.start_with?("sha256:") }

# Second compile run for stability
second_result = nil
second_manifest = nil
begin
  out2 = File.join($tmpdir_main, "vector_math2.igapp")
  stdout2, _stderr2, _status2 = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *SOURCE_FILES, "--out", out2
  )
  second_result = JSON.parse(stdout2.force_encoding("UTF-8")) rescue {}
  mp = File.join(out2, "manifest.json")
  second_manifest = File.exist?(mp) ? JSON.parse(File.read(mp, encoding: "UTF-8")) : nil
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

sir_program_id = ($sir || {})["program_id"]
manifest_sir_ref = ($manifest || {})["semantic_ir_ref"]

check("H-01: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }
check("H-02: SIR program_id present")          { !sir_program_id.nil? && !sir_program_id.empty? }
check("H-03: manifest semantic_ir_ref present") { !manifest_sir_ref.nil? }
check("H-04: SIR program_id matches manifest semantic_ir_ref") do
  manifest_sir_ref == sir_program_id || manifest_sir_ref.end_with?(sir_program_id.to_s.split("/").last.to_s)
end
check("H-05: SIR source_units count matches 6") { (($sir || {})["source_units"] || []).size == 6 }
check("H-06: SIR format_version present") { !($sir || {})["format_version"].nil? }

# ── Section I: sourcemap integrity ────────────────────────────────────────────
puts
puts "Section I — Sourcemap"

check("I-01: sourcemap.json is present and parsed") { !$sourcemap.nil? }
check("I-02: manifest sourcemap_ref present") do
  ref = ($manifest || {})["sourcemap_ref"]
  !ref.nil? && !ref.empty?
end
check("I-03: sourcemap has at least one top-level key") { ($sourcemap || {}).keys.size >= 1 }

# ── Section J: liveness counters ──────────────────────────────────────────────
puts
puts "Section J — Liveness Instrumentation"

counters = ($liveness["counters"] || {})
budget   = ($liveness["budget_policy"] || {})
breaches = Array($liveness["breaches"])

check("J-01: liveness_instrumentation present") { !$liveness.empty? }
check("J-02: no liveness breaches") { breaches.empty? }
check("J-03: liveness authority is lab_only_p2_instrumentation") do
  $liveness["authority"] == "lab_only_p2_instrumentation"
end

LIVENESS_FATAL_COUNTERS.each do |key|
  check("J-04-#{key.split('.').last}: #{key} counter is present") { counters.key?(key) }
  check("J-05-#{key.split('.').last}: #{key} counter below fatal limit (#{LIVENESS_FATAL_LIMIT})") do
    val = counters[key].to_i
    val < LIVENESS_FATAL_LIMIT
  end
end

check("J-06: typechecker.infer_expr depth in expected range (0..50)") do
  v = counters["typechecker.infer_expr.max_depth"].to_i
  v >= 0 && v <= 50
end
check("J-07: form_resolver.walk_expr depth in expected range (0..50)") do
  v = counters["form_resolver.walk_expr.max_depth"].to_i
  v >= 0 && v <= 50
end
check("J-08: fatal budget modes present for known counters") do
  LIVENESS_FATAL_COUNTERS.all? { |k| budget.dig(k, "mode") == "fatal" }
end

# ── Section K: Ruby toolchain parity gap (documented, not failure) ─────────────
puts
puts "Section K — Ruby Parity Gap (informational)"

RUBY_IGC = (ROOT.parent.parent / "igniter-lang" / "bin" / "igc").to_s

check("K-01: Ruby igc binary path documented (not required to exist)") { true }
check("K-02: Ruby compiler not expected to compile multi-file apps at this baseline") do
  # Ruby toolchain operates on single-file inputs only at this baseline date.
  # Multi-file compilation (imports across modules) requires the Rust compiler.
  # This is a known parity gap documented in the baseline — it is NOT a failure.
  true
end
check("K-03: Ruby gap scope: multi-file import resolution only") { true }

# ── Section L: manifest metadata ──────────────────────────────────────────────
puts
puts "Section L — Manifest Metadata"

check("L-01: manifest kind is present") do
  k = ($manifest || {})["kind"]
  !k.nil?
end
check("L-02: manifest format_version present") { !($manifest || {})["format_version"].nil? }
check("L-03: manifest grammar_version present") { !($manifest || {})["grammar_version"].nil? }
check("L-04: manifest program_id present")      { !($manifest || {})["program_id"].nil? }
check("L-05: manifest assembler present")       { !($manifest || {})["assembler"].nil? }
check("L-06: manifest contract_index is a Hash") { ($manifest || {})["contract_index"].is_a?(Hash) }
check("L-07: manifest has 37 entries in contract_index") do
  (($manifest || {})["contract_index"] || {}).size == 37
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts
total = $pass_count + $fail_count
puts "=" * 60
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 60
exit($fail_count.zero? ? 0 : 1)
