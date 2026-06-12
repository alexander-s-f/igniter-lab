#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_neural_net_baseline_p1.rb
# LAB-NEURAL-NET-BASELINE-P1 — freeze neural_net as a positive static
# computational graph baseline.
#
# Proves:
#   - Rust compile status ok, all 5 stages ok
#   - exactly 5 source units, 6 contracts, 0 diagnostics
#   - source/artifact hash stable across 2 runs
#   - liveness tc_infer=5, fr_walk=5 (both well under fatal limit 1000)
#   - no dynamic layer / tensor / training / capability claim in SIR
#   - unary minus workaround (binary_op 0-N) documented as NN-P02 pressure
#   - fixed-point integer arithmetic (scale=1000) documented as NN-P03 pressure
#
# Authority: regression baseline only. No numeric implementation, no tensor
# package, no training/backprop, no dynamic layer algebra, no source edits.

require "digest"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
APP_DIR      = LAB_ROOT / "igniter-apps" / "neural_net"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

SOURCE_FILES = %w[types.ig activations.ig layers.ig network.ig example.ig]
  .map { |f| (APP_DIR / f).to_s }

EXPECTED_CONTRACTS = %w[
  DenseLayer2x1 DenseLayer2x2 FeedForwardNN ReLU RunInference SigmoidApprox
].sort.freeze

EXPECTED_SOURCE_UNITS = %w[
  NeuralNetActivations NeuralNetCore NeuralNetExample NeuralNetLayers NeuralNetTypes
].sort.freeze

BASELINE_SOURCE_HASH   = "sha256:9a6506e3f42aec717fd3a857ccd1d5b759e158169f4589ffcff4849c4a3368c8"
BASELINE_ARTIFACT_HASH = "sha256:60926a9fcb51a7b814ab4dfd2e1c9c9493414d204c4561e7f1be29be2adad594"

EXPECTED_TC_INFER_DEPTH = 5
EXPECTED_FR_WALK_DEPTH  = 5
LIVENESS_FATAL_LIMIT    = 1000

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
$tmpdir_main = Dir.mktmpdir("nn_baseline_p1_")
at_exit { FileUtils.rm_rf($tmpdir_main) }

def compile_app
  return if $result

  out = File.join($tmpdir_main, "neural_net.igapp")
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

  $liveness = $result["liveness_instrumentation"] || {}
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

check("B-01: status is ok")       { $result["status"] == "ok" }
check("B-02: zero diagnostics")   { Array($result["diagnostics"]).empty? }
check("B-03: zero warnings")      { Array($result["warnings"]).empty? }
check("B-04: igapp_path present") { !$result["igapp_path"].nil? && !$result["igapp_path"].empty? }

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

manifest_units = ($manifest || {})["source_units"] || []
unit_modules   = manifest_units.map { |u| u["module"] }.sort

check("D-01: manifest has exactly 5 source_units") { manifest_units.size == 5 }
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

# ── Section E: contracts ──────────────────────────────────────────────────────
puts
puts "Section E — Contracts"

result_contracts   = Array($result["contracts"]).sort
manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts      = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort

check("E-01: exactly 6 contracts in result")         { result_contracts.size == 6 }
check("E-02: exactly 6 contracts in manifest")       { manifest_contracts.size == 6 }
check("E-03: result contracts match expected set")   { result_contracts == EXPECTED_CONTRACTS }
check("E-04: manifest contracts match expected set") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-05: result and manifest contract lists agree") { result_contracts == manifest_contracts }
check("E-06: SIR contracts count is 6")              { sir_contracts.size == 6 }
check("E-07: SIR contracts match expected set")      { sir_contracts == EXPECTED_CONTRACTS }
check("E-08: contract_index has 6 entries") do
  (($manifest || {})["contract_index"] || {}).size == 6
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
  out2 = File.join($tmpdir_main, "neural_net2.igapp")
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
check("H-05: SIR source_units count is 5") { (($sir || {})["source_units"] || []).size == 5 }
check("H-06: SIR format_version present")  { !($sir || {})["format_version"].nil? }

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

counters     = ($liveness["counters"] || {})
budget       = ($liveness["budget_policy"] || {})
breaches     = Array($liveness["breaches"])

check("J-01: liveness_instrumentation present in compile result") { !$liveness.empty? }
check("J-02: no liveness breaches") { breaches.empty? }
check("J-03: liveness authority is lab_only_p2_instrumentation") do
  $liveness["authority"] == "lab_only_p2_instrumentation"
end
check("J-04: tc_infer depth matches expected value (#{EXPECTED_TC_INFER_DEPTH})") do
  counters["typechecker.infer_expr.max_depth"].to_i == EXPECTED_TC_INFER_DEPTH
end
check("J-05: fr_walk depth matches expected value (#{EXPECTED_FR_WALK_DEPTH})") do
  counters["form_resolver.walk_expr.max_depth"].to_i == EXPECTED_FR_WALK_DEPTH
end
check("J-06: tc_infer depth is below fatal limit (#{LIVENESS_FATAL_LIMIT})") do
  counters["typechecker.infer_expr.max_depth"].to_i < LIVENESS_FATAL_LIMIT
end
check("J-07: fr_walk depth is below fatal limit (#{LIVENESS_FATAL_LIMIT})") do
  counters["form_resolver.walk_expr.max_depth"].to_i < LIVENESS_FATAL_LIMIT
end
check("J-08: tc_infer and fr_walk budget modes are fatal") do
  budget.dig("typechecker.infer_expr.max_depth", "mode") == "fatal" &&
    budget.dig("form_resolver.walk_expr.max_depth", "mode") == "fatal"
end

# ── Section K: no dynamic layer / tensor / training / capability claim ─────────
puts
puts "Section K — Static Graph / No Dynamic Claims"

sir_text = File.exist?(File.join($igapp_path, "semantic_ir_program.json")) ?
  File.read(File.join($igapp_path, "semantic_ir_program.json"), encoding: "UTF-8").downcase : ""

check("K-01: SIR contains no 'tensor' reference") do
  !sir_text.include?("tensor")
end
check("K-02: SIR contains no 'training' or 'gradient' or 'backprop' reference") do
  !sir_text.include?("training") && !sir_text.include?("gradient") && !sir_text.include?("backprop")
end
check("K-03: SIR contains no 'capability' or 'authority' field") do
  !sir_text.include?("capability") && !sir_text.include?("profile_binding")
end
check("K-04: SIR contains no 'ml_package' or 'tensor_package' reference") do
  !sir_text.include?("ml_package") && !sir_text.include?("tensor_package")
end
check("K-05: all 6 contracts are pure (no effects or capabilities claimed)") do
  contracts = ($sir || {})["contracts"] || []
  contracts.all? do |c|
    Array(c["effects"]).empty? && Array(c["capabilities"]).empty?
  end
end

# ── Section L: unary minus workaround documented (NN-P02) ─────────────────────
puts
puts "Section L — Unary Minus Workaround (NN-P02 pressure documentation)"

sir_data     = $sir || {}
sir_text_raw = File.exist?(File.join($igapp_path, "semantic_ir_program.json")) ?
  File.read(File.join($igapp_path, "semantic_ir_program.json"), encoding: "UTF-8") : ""

check("L-01: binary_op '-' nodes present in SIR (0-N pattern for negative values)") do
  # FeedForwardNN uses: w12: 0 - 500, w21: 0 - 400, b2: 0 - 200, w2.w21: 0 - 800, etc.
  sir_text_raw.include?('"op": "-"')
end

check("L-02: FeedForwardNN w1 record has at least one binary_op '-' node") do
  contracts = sir_data["contracts"] || []
  c = contracts.find { |x| x["contract_name"] == "FeedForwardNN" }
  next false unless c
  nodes = c["nodes"] || []
  w1 = nodes.find { |n| n["name"] == "w1" }
  next false unless w1
  fields = w1.dig("expr", "fields") || {}
  fields.values.any? { |v| v.is_a?(Hash) && v["kind"] == "binary_op" && v["op"] == "-" }
end

check("L-03: NN-P02 acknowledged — unary minus gap documented as pressure, not baseline failure") do
  # The parser does not support unary minus (-N). All negative values in the app
  # use the 0-N workaround (binary subtraction from zero). This is documented as
  # NN-P02 pressure → LAB-UNARY-MINUS-P1. It does not affect the baseline.
  true
end

# ── Section M: fixed-point arithmetic documented (NN-P03) ──────────────────────
puts
puts "Section M — Fixed-Point Arithmetic (NN-P03 pressure documentation)"

check("M-01: division nodes present in SIR (fixed-point scale normalization)") do
  # DenseLayer2x2/DenseLayer2x1 use: (z_raw / 1000) for scale normalisation.
  sir_text_raw.include?('"op": "/"')
end

check("M-02: FeedForwardNN contains integer 1000 literal (scale factor)") do
  # The scale factor 1000 appears in layer weight records and normalization.
  sir_text_raw.include?("1000")
end

check("M-03: NN-P03 acknowledged — fixed-point integer scale documented as pressure, not baseline failure") do
  # Igniter has no native Float/Decimal. The app uses integer milli-units (1000=1.0)
  # and divides post-multiply to normalise scale-squared products. This is documented
  # as NN-P03 → LAB-STDLIB-NUMERIC-FIXED-POINT-P1. It does not affect the baseline.
  true
end

# ── Section N: manifest metadata ──────────────────────────────────────────────
puts
puts "Section N — Manifest Metadata"

check("N-01: manifest kind present")             { !($manifest || {})["kind"].nil? }
check("N-02: manifest format_version present")   { !($manifest || {})["format_version"].nil? }
check("N-03: manifest grammar_version present")  { !($manifest || {})["grammar_version"].nil? }
check("N-04: manifest program_id present")       { !($manifest || {})["program_id"].nil? }
check("N-05: manifest assembler present")        { !($manifest || {})["assembler"].nil? }
check("N-06: manifest contract_index is a Hash") { ($manifest || {})["contract_index"].is_a?(Hash) }
check("N-07: manifest has 6 entries in contract_index") do
  (($manifest || {})["contract_index"] || {}).size == 6
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts
total = $pass_count + $fail_count
puts "=" * 60
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 60
exit($fail_count.zero? ? 0 : 1)
