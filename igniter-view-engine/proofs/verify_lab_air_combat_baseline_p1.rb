#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_air_combat_baseline_p1.rb
# LAB-AIR-COMBAT-BASELINE-P1 — freeze air_combat as a dual-toolchain
# positive baseline and register its app-pressure surfaces.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, IO, guidance,
# or game loops implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
LANG_ROOT = LAB_ROOT.parent / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "air_combat"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[
  types.ig vec.ig kalman.ig guidance.ig strategy.ig swarm.ig engine.ig example.ig
].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_CONTRACTS = %w[
  BuildSwarmStats CombinedDoctrine DoctrineDispatcher EngageSwarm EvadeVelocity
  EvasionDoctrine LeadPoint MakePlane MakeStrategy MarkKilled MaxSpeed
  PursueVelocity PursuitDoctrine RunBattle3 RunDuel SwarmAlive SwarmCentroid
  SwarmStep SwarmThreat TrackBogey TrackFold3 TrackPredict TrackStep
  TrackUpdate VAdd VClampSpeed VDist2 VMag2 VScale VSub WorldTick
].sort.freeze

EXPECTED_TYPES = %w[
  Vec2 Plane Track Strategy Swarm Player World SwarmStats Measurement
].sort.freeze

EXPECTED_SOURCE_UNITS = %w[
  AirCombatEngine AirCombatExample AirCombatGuidance AirCombatKalman
  AirCombatStrategy AirCombatSwarm AirCombatTypes AirCombatVec
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

def read_source(name)
  File.read(APP_DIR / name, encoding: "UTF-8")
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| read_source(name) }.join("\n")
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

TMP = Dir.mktmpdir("air_combat_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "air_combat_#{label}.igapp")
  # Use fresh --out path as requested and do not pipe to head
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus }
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "air_combat_ruby_#{label}.igapp")
  script = <<~EOS
    require "json"
    require "igniter_lang/compiler_orchestrator"
    paths = #{SOURCE_FILES.inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: #{out.inspect})
    puts JSON.generate(result)
  EOS
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / "lib"}", "-e", script)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status.exitstatus }
  [parsed, out]
end

rust1, rust_out1 = run_rust_compile("one")
rust2, = run_rust_compile("two")
ruby1, ruby_out1 = run_ruby_compile("one")
ruby2, = run_ruby_compile("two")

# Extract manifest / SIR
manifest_p = File.join(rust_out1, "manifest.json")
sir_p = File.join(rust_out1, "semantic_ir_program.json")
sourcemap_p = File.join(rust_out1, "sourcemap.json")

$manifest = File.exist?(manifest_p) ? JSON.parse(File.read(manifest_p, encoding: "UTF-8")) : nil
$sir = File.exist?(sir_p) ? JSON.parse(File.read(sir_p, encoding: "UTF-8")) : nil
$sourcemap = File.exist?(sourcemap_p) ? JSON.parse(File.read(sourcemap_p, encoding: "UTF-8")) : nil

metrics = {
  files: SOURCE_FILES.size,
  contracts: all_source.scan(/^contract\s+/).size + all_source.scan(/^pure\s+contract\s+/).size,
  types: all_source.scan(/^type\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  fold: all_source.scan(/\bfold\(/).size,
  map: all_source.scan(/\bmap\(/).size,
  filter: all_source.scan(/\bfilter\(/).size,
  concat: all_source.scan(/\bconcat\(/).size
}

puts
puts "Section A — Preconditions"
check("A-01: app directory exists") { APP_DIR.directory? }
check("A-02: rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03: igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format("%02d", idx + 4)}: source exists — #{name}") { File.exist?(APP_DIR / name) }
end
check("A-12: pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-13: report doc exists") { File.exist?(APP_DIR / "report.md") }

puts
puts "Section B — Compilation Status"
check("B-01: Rust compile returns status ok") { rust1["status"] == "ok" }
check("B-02: Rust diagnostics list empty") { Array(rust1["diagnostics"]).empty? }
check("B-03: Rust warnings list empty") { Array(rust1["warnings"]).empty? }
check("B-04: Ruby compile returns status ok") { (ruby1["status"] || ruby1.dig("result", "status")) == "ok" }
check("B-05: Ruby diagnostics list empty") { Array(ruby1["diagnostics"] || ruby1.dig("result", "diagnostics")).empty? }
check("B-06: Ruby and Rust compile status parity") { rust1["status"] == (ruby1["status"] || ruby1.dig("result", "status")) }

puts
puts "Section C — Pipeline Stages"
stages = rust1["stages"] || {}
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("C-#{format("%02d", idx + 1)}: Rust stage #{stage} is ok") { stages[stage] == "ok" }
end
check("C-06: exactly 5 stages present in Rust") { stages.size == 5 }

puts
puts "Section D — Source Units"
manifest_units = ($manifest || {})["source_units"] || []
unit_modules = manifest_units.map { |u| u["module"] }.sort
check("D-01: manifest has exactly 8 source_units") { manifest_units.size == 8 }
check("D-02: source_unit modules match expected set") { unit_modules == EXPECTED_SOURCE_UNITS }
EXPECTED_SOURCE_UNITS.each_with_index do |mod, idx|
  check("D-#{format("%02d", idx + 3)}: module #{mod} present in manifest") { unit_modules.include?(mod) }
end

puts
puts "Section E — Contracts"
result_contracts = Array(rust1["contracts"]).sort
manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort
check("E-01: exactly 31 contracts in result") { result_contracts.size == 31 }
check("E-02: exactly 31 contracts in manifest") { manifest_contracts.size == 31 }
check("E-03: result contracts match expected set") { result_contracts == EXPECTED_CONTRACTS }
check("E-04: manifest contracts match expected set") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-05: result and manifest contract lists agree") { result_contracts == manifest_contracts }
check("E-06: SIR contracts count is 31") { sir_contracts.size == 31 }
check("E-07: SIR contracts match expected set") { sir_contracts == EXPECTED_CONTRACTS }
check("E-08: contract_index has 31 entries") { (($manifest || {})["contract_index"] || {}).size == 31 }
check("E-09: CombinedDoctrine present in list") { result_contracts.include?("CombinedDoctrine") }

puts
puts "Section F — Artifact Files"
check("F-01: manifest.json exists and parsed") { !$manifest.nil? }
check("F-02: semantic_ir_program.json exists and parsed") { !$sir.nil? }
check("F-03: sourcemap.json exists and parsed") { !$sourcemap.nil? }
check("F-04: manifest is valid JSON object") { $manifest.is_a?(Hash) }
check("F-05: SIR is valid JSON object") { $sir.is_a?(Hash) }
check("F-06: sourcemap is valid JSON object") { $sourcemap.is_a?(Hash) }
check("F-07: compilation_report.json exists") { File.exist?(File.join(rust_out1, "compilation_report.json")) }
check("F-08: diagnostics.json exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }

puts
puts "Section G — Hash Stability"
rust_source_hash = rust1["source_hash"]
ruby_source_hash = ruby1["source_hash"] || ruby1.dig("result", "source_hash")
check("G-01: Rust source_hash stable across two runs") { rust2["source_hash"] == rust1["source_hash"] }
check("G-02: Ruby source_hash stable across two runs") do
  (ruby2["source_hash"] || ruby2.dig("result", "source_hash")) == ruby_source_hash
end
check("G-03: Ruby and Rust source_hash agree") { ruby_source_hash == rust_source_hash }
check("G-04: Rust source_hash is sha256-prefixed") { rust_source_hash.to_s.start_with?("sha256:") }
check("G-05: Ruby source_hash is sha256-prefixed") { ruby_source_hash.to_s.start_with?("sha256:") }

puts
puts "Section H — Semantic IR"
sir_program_id = ($sir || {})["program_id"]
manifest_sir_ref = ($manifest || {})["semantic_ir_ref"]
check("H-01: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }
check("H-02: SIR program_id present") { !sir_program_id.nil? && !sir_program_id.empty? }
check("H-03: manifest semantic_ir_ref present") { !manifest_sir_ref.nil? && !manifest_sir_ref.empty? }
check("H-04: SIR program_id matches manifest semantic_ir_ref") do
  manifest_sir_ref == sir_program_id ||
    manifest_sir_ref.to_s.end_with?(sir_program_id.to_s.split("/").last.to_s)
end
check("H-05: SIR source_units count is 8") { (($sir || {})["source_units"] || []).size == 8 }
check("H-06: SIR format_version present") { !($sir || {})["format_version"].nil? }

puts
puts "Section I — Sourcemap"
check("I-01: sourcemap.json is present and parsed") { !$sourcemap.nil? }
check("I-02: manifest sourcemap_ref present") { !($manifest || {})["sourcemap_ref"].nil? }
check("I-03: sourcemap has at least one top-level key") { ($sourcemap || {}).keys.size >= 1 }
check("I-04: sourcemap mappings present") { ($sourcemap || {})["nodes"].is_a?(Array) && ($sourcemap || {})["nodes"].size > 0 }

puts
puts "Section J — App Metrics & Language Constructs"
check("J-01: exactly 8 source files") { metrics[:files] == 8 }
check("J-02: exactly 9 types declared") { metrics[:types] == 9 }
check("J-03: exactly 31 contracts declared") { metrics[:contracts] == 31 }
check("J-04: exactly 61 call_contract sites") { metrics[:call_contract] == 61 }
check("J-05: exactly 6 fold sites") { metrics[:fold] == 6 }
check("J-06: exactly 2 map sites") { metrics[:map] == 2 }
check("J-07: exactly 2 filter sites") { metrics[:filter] == 2 }
check("J-08: all call_contract targets are PascalCase string literals") do
  all_source.scan(/call_contract\("([^"]+)"/).flatten.all? { |name| name.match?(/\A[A-Z]/) }
end
check("J-09: found type definitions in types.ig") do
  types_src = read_source("types.ig")
  types_src.include?("type Vec2") && types_src.include?("type Plane") && types_src.include?("type Track")
end
check("J-10: found pure contract declarations in vec.ig") do
  vec_src = read_source("vec.ig")
  vec_src.include?("pure contract VAdd") && vec_src.include?("pure contract VSub")
end

puts
puts "Section K — Preserved Pressures"
check("K-01: report.md covers AC-P01 (fold-to-struct Kalman)") { read_source("report.md").include?("fold-to-struct") && read_source("report.md").include?("Kalman") }
check("K-02: registry matches AC-P01 (Kalman track)") { read_source("PRESSURE_REGISTRY.md").include?("AC-P01") }
check("K-03: report.md covers AC-P02 (fold-to-struct centroid)") { read_source("report.md").include?("SwarmCentroid") }
check("K-04: registry matches AC-P02 (swarm centroid)") { read_source("PRESSURE_REGISTRY.md").include?("AC-P02") }
check("K-05: report.md covers AC-P03 (manual unroll)") { read_source("report.md").include?("RunBattle3") }
check("K-06: registry matches AC-P05 (state threading)") { read_source("PRESSURE_REGISTRY.md").include?("AC-P05") }
check("K-07: report.md covers AC-P06 (dispatch strategy avoidance)") { read_source("report.md").include?("DoctrineDispatcher") }
check("K-08: registry matches AC-P06 (doctrine dispatch)") { read_source("PRESSURE_REGISTRY.md").include?("AC-P06") }
check("K-09: report.md covers AC-P07 (missing math sqrt)") { read_source("report.md").include?("VMag2") && read_source("report.md").include?("sqrt") }
check("K-10: registry matches AC-P08 (IO surface game needs)") { read_source("PRESSURE_REGISTRY.md").include?("AC-P08") }

puts
puts "Section L — Closed Surfaces"
check("L-01: no capability declarations in source") { !all_source.match?(/^\s*capability\s+/) }
check("L-02: no effect declarations in source") { !all_source.match?(/^\s*effect\s+/) }
check("L-03: no stdlib.io imports") { !all_source.include?("stdlib.io") }
check("L-04: no clock / time source access") { !all_source.include?("now()") }
check("L-05: no RNG / random calls in code") { !all_source.include?("random") }
check("L-06: no Rack or HTTP server components") { !all_source.match?(/\b(Rack|HTTP|Socket)\b/) }
check("L-07: no database SQL or ORM terms") { !all_source.match?(/\b(SQL|ORM|ActiveRecord|Database)\b/) }
check("L-08: no write or output IO features used") { !all_source.match?(/\b(write_file|puts|printf)\b/) }

puts
total = $pass_count + $fail_count
puts "=" * 60
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 60
exit($fail_count.zero? ? 0 : 1)
