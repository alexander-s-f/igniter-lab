#!/usr/bin/env ruby
# frozen_string_literal: true
#
# LAB-AIR-COMBAT-BASELINE-P2
#
# Rebaseline air_combat after source-level `entrypoint RunDuel`.
# Authority: evidence rebaseline only. No compiler, app-source, runtime, IO,
# ServiceLoop, or rich-entrypoint implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "air_combat"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
CARD_DIR = LAB_ROOT / ".agents" / "work" / "cards" / "governance"
DOC_PATH = LAB_ROOT / "lab-docs" / "governance" / "lab-air-combat-entrypoint-rebaseline-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

SOURCE_NAMES = %w[
  types.ig vec.ig kalman.ig guidance.ig strategy.ig swarm.ig engine.ig example.ig
].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| APP_DIR / name }.freeze
SOURCE_RELATIVE = SOURCE_NAMES.map { |name| File.join("igniter-apps/air_combat", name) }.freeze

EXPECTED_HASH = "sha256:b3c2bdd046475442d1b78705fbcb9bfda55da09b070df93a3d36ff8f825b0c55"
CLAIMED_P2_HASH = "sha256:8b698e66d8635f83306d209c702f7231c8184b1e6ffddb8a63f3a147ed9600f8"
P1_HASH = "sha256:4fc0b4cb4c63a06060017b932f351d9b708db826428f3d2ad94ac9f92c2a4e04"

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
  if yield
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} -- #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue
  ""
end

def read_source(name)
  read(APP_DIR / name)
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| read_source(name) }.join("\n")
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

TMP = Dir.mktmpdir("air_combat_baseline_p2_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "rust_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES.map(&:to_s), "--out", out)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout,
    "_stderr" => stderr,
    "_status" => status.exitstatus
  }
  parsed["_stderr"] = stderr
  parsed["_status"] = status.exitstatus
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    paths = #{SOURCE_FILES.map(&:to_s).inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: #{out.inspect})
    puts JSON.generate(result)
  RUBY
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / "lib"}", "-e", script)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout,
    "_stderr" => stderr,
    "_status" => status.exitstatus
  }
  parsed["_stderr"] = stderr
  parsed["_status"] = status.exitstatus
  [parsed, out]
end

def diagnostics(result)
  Array(result["diagnostics"] || result.dig("result", "diagnostics"))
end

def warnings(result)
  Array(result["warnings"] || result.dig("result", "warnings"))
end

def status(result)
  result["status"] || result.dig("result", "status")
end

def source_hash(result)
  result["source_hash"] || result.dig("result", "source_hash")
end

def json_file(dir, name)
  path = File.join(dir, name)
  File.exist?(path) ? JSON.parse(File.read(path, encoding: "UTF-8")) : nil
end

def source_has_no_ig_diff?
  _stdout, _stderr, status = Open3.capture3(
    "git", "-C", LAB_ROOT.to_s, "diff", "--quiet", "--", *SOURCE_RELATIVE
  )
  status.success?
end

rust1, rust_out1 = run_rust_compile("one")
rust2, rust_out2 = run_rust_compile("two")
ruby1, ruby_out1 = run_ruby_compile("one")
ruby2, ruby_out2 = run_ruby_compile("two")

rust_manifest = json_file(rust_out1, "manifest.json") || {}
rust_sir = json_file(rust_out1, "semantic_ir_program.json") || {}
rust_sourcemap = json_file(rust_out1, "sourcemap.json") || {}
ruby_manifest = json_file(ruby_out1, "manifest.json") || {}
ruby_sir = json_file(ruby_out1, "semantic_ir_program.json") || {}

registry = read(APP_DIR / "PRESSURE_REGISTRY.md")
report = read(APP_DIR / "report.md")
p1_card = read(CARD_DIR / "LAB-AIR-COMBAT-BASELINE-P1.md")
p2_card = read(CARD_DIR / "LAB-AIR-COMBAT-BASELINE-P2.md")
dev_tutorial = read(LANG_ROOT / "docs" / "dev-tutorial.md")
ch13 = read(LANG_ROOT / "docs" / "spec" / "ch13-managed-recursion.md")
covenant = read(LANG_ROOT / "docs" / "language-covenant.md")
runner_source = read(__FILE__)
doc = read(DOC_PATH)
portfolio = read(PORTFOLIO)

metrics = {
  files: SOURCE_FILES.size,
  contracts: all_source.scan(/^contract\s+/).size + all_source.scan(/^pure\s+contract\s+/).size,
  types: all_source.scan(/^type\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  fold: all_source.scan(/\bfold\(/).size,
  map: all_source.scan(/\bmap\(/).size,
  filter: all_source.scan(/\bfilter\(/).size,
  entrypoint: all_source.scan(/^entrypoint\s+/).size
}

puts
puts "Section A -- Preconditions And Required Reads"
check("A-01 app directory exists") { APP_DIR.directory? }
check("A-02 release or debug Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03 igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format("%02d", idx + 4)} source exists -- #{name}") { File.exist?(APP_DIR / name) }
end
check("A-12 P1 card was read and closed") { p1_card.include?("LAB-AIR-COMBAT-BASELINE-P1") && p1_card.include?("CLOSED") }
check("A-13 P2 card was read") { p2_card.include?("LAB-AIR-COMBAT-BASELINE-P2") }
check("A-14 pressure registry present") { registry.include?("# Air Combat Pressure Registry") }
check("A-15 pressure report present") { report.include?("# Air Combat") }
check("A-16 dev tutorial mentions entrypoint") { dev_tutorial.include?("entrypoint Contract") }

puts
puts "Section B -- Dual Toolchain Compilation"
check("B-01 Rust compile status ok") { status(rust1) == "ok" }
check("B-02 Rust diagnostics empty") { diagnostics(rust1).empty? }
check("B-03 Rust warnings empty") { warnings(rust1).empty? }
check("B-04 Rust process exit zero") { rust1["_status"] == 0 }
check("B-05 Rust stderr empty") { rust1["_stderr"].to_s.empty? }
check("B-06 Ruby compile status ok") { status(ruby1) == "ok" }
check("B-07 Ruby diagnostics empty") { diagnostics(ruby1).empty? }
check("B-08 Ruby process exit zero") { ruby1["_status"] == 0 }
check("B-09 Ruby stderr empty") { ruby1["_stderr"].to_s.empty? }
check("B-10 Ruby/Rust status parity") { status(ruby1) == status(rust1) }

puts
puts "Section C -- Hash Stability And Drift"
check("C-01 Rust hash stable across two fresh runs") { source_hash(rust1) == source_hash(rust2) }
check("C-02 Ruby hash stable across two fresh runs") { source_hash(ruby1) == source_hash(ruby2) }
check("C-03 Ruby/Rust source_hash agree") { source_hash(ruby1) == source_hash(rust1) }
check("C-04 current source_hash is frozen expected P2 value") { source_hash(rust1) == EXPECTED_HASH }
check("C-05 expected hash is sha256") { EXPECTED_HASH.match?(/\Asha256:[a-f0-9]{64}\z/) }
check("C-06 current hash differs from P1 pre-entrypoint hash") { EXPECTED_HASH != P1_HASH }
check("C-07 current hash differs from card's claimed 8b hash") { EXPECTED_HASH != CLAIMED_P2_HASH }
check("C-08 registry records current P2 hash") { registry.include?(EXPECTED_HASH) }
check("C-09 registry explains superseded claimed 8b hash") { registry.include?(CLAIMED_P2_HASH) && registry.include?("superseded") }
check("C-10 source .ig files have no git diff") { source_has_no_ig_diff? }

puts
puts "Section D -- Entrypoint Source And Metadata"
rust_manifest_ep = rust_manifest["entrypoint"] || {}
rust_sir_ep = rust_sir["entrypoint"] || {}
ruby_manifest_ep = ruby_manifest["entrypoint"] || {}
ruby_sir_ep = ruby_sir["entrypoint"] || {}
check("D-01 source has exactly one entrypoint declaration") { metrics[:entrypoint] == 1 }
check("D-02 source declares entrypoint RunDuel") { read_source("example.ig").include?("entrypoint RunDuel") }
check("D-03 source AC-P10 comment names named run-profiles") { read_source("example.ig").include?("PRESSURE AC-P10") && read_source("example.ig").include?("named PROP-029 run-profile") }
check("D-04 Rust manifest entrypoint kind default_entrypoint") { rust_manifest_ep["kind"] == "default_entrypoint" }
check("D-05 Rust manifest resolved_contract RunDuel") { rust_manifest_ep["resolved_contract"] == "RunDuel" }
check("D-06 Rust manifest declared_target RunDuel") { rust_manifest_ep["declared_target"] == "RunDuel" }
check("D-07 Rust manifest contract_path is run_duel") { rust_manifest_ep["contract_path"].to_s.include?("run_duel") }
check("D-08 Rust SIR entrypoint kind entrypoint_decl") { rust_sir_ep["kind"] == "entrypoint_decl" }
check("D-09 Rust SIR target RunDuel") { rust_sir_ep["target"] == "RunDuel" }
check("D-10 Rust SIR resolved_contract RunDuel") { rust_sir_ep["resolved_contract"] == "RunDuel" }
check("D-11 Ruby manifest resolved_contract RunDuel") { ruby_manifest_ep["resolved_contract"] == "RunDuel" }
check("D-12 Ruby SIR target RunDuel") { ruby_sir_ep["target"] == "RunDuel" }
check("D-13 entrypoint is metadata, not extra contract") { Array(rust1["contracts"]).include?("RunDuel") && metrics[:contracts] == 31 }
check("D-14 TrackBogey remains a contract, not a second entrypoint") { Array(rust1["contracts"]).include?("TrackBogey") && !all_source.include?("entrypoint TrackBogey") }

puts
puts "Section E -- P1 Metrics Preserved"
result_contracts = Array(rust1["contracts"]).sort
manifest_contracts = Array(rust_manifest["contracts"]).sort
sir_contracts = Array(rust_sir["contracts"]).map { |c| c["contract_name"] || c["name"] }.compact.sort
manifest_units = Array(rust_manifest["source_units"])
unit_modules = manifest_units.map { |u| u["module"] }.sort
check("E-01 exactly 8 source files") { metrics[:files] == 8 }
check("E-02 exactly 9 type declarations") { metrics[:types] == 9 }
check("E-03 exactly 31 contracts in source") { metrics[:contracts] == 31 }
check("E-04 exactly 31 contracts in Rust result") { result_contracts.size == 31 }
check("E-05 result contracts match expected") { result_contracts == EXPECTED_CONTRACTS }
check("E-06 manifest contracts match expected") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-07 SIR contracts match expected") { sir_contracts == EXPECTED_CONTRACTS }
check("E-08 manifest has 8 source units") { manifest_units.size == 8 }
check("E-09 source unit modules match expected") { unit_modules == EXPECTED_SOURCE_UNITS }
check("E-10 exactly 61 call_contract sites") { metrics[:call_contract] == 61 }
check("E-11 call_contract targets are PascalCase literals") { all_source.scan(/call_contract\("([^"]+)"/).flatten.all? { |name| name.match?(/\A[A-Z]/) } }
check("E-12 exactly 6 fold sites") { metrics[:fold] == 6 }
check("E-13 exactly 2 map sites") { metrics[:map] == 2 }
check("E-14 exactly 2 filter sites") { metrics[:filter] == 2 }
check("E-15 expected types present") { EXPECTED_TYPES.all? { |type| all_source.include?("type #{type}") } }

puts
puts "Section F -- Artifacts And Flake Avoidance"
check("F-01 Rust manifest parsed") { rust_manifest.is_a?(Hash) && !rust_manifest.empty? }
check("F-02 Rust SIR parsed") { rust_sir.is_a?(Hash) && !rust_sir.empty? }
check("F-03 Rust sourcemap parsed") { rust_sourcemap.is_a?(Hash) && !rust_sourcemap.empty? }
check("F-04 Rust compilation_report exists") { File.exist?(File.join(rust_out1, "compilation_report.json")) }
check("F-05 Rust diagnostics.json exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }
check("F-06 Rust SIR kind semantic_ir_program") { rust_sir["kind"] == "semantic_ir_program" }
check("F-07 manifest semantic_ir_ref matches SIR program") { rust_manifest["semantic_ir_ref"].to_s.end_with?(rust_sir["program_id"].to_s.split("/").last.to_s) }
check("F-08 runner uses Open3.capture3") { runner_source.include?("Open3.capture3") }
check("F-09 runner uses mktmpdir fresh package dirs") { runner_source.include?("Dir.mktmpdir") }
check("F-10 runner invokes compiler directly without pipeline helpers") do
  runner_source.include?('Open3.capture3(rust_bin.to_s, "compile"') &&
    !runner_source.match?(/Open3[.]pipeline|IO[.]popen/)
end

puts
puts "Section G -- Pressures Preserved And Routed"
(1..8).each do |n|
  id = format("AC-P%02d", n)
  check("G-#{format("%02d", n)} registry preserves #{id}") { registry.include?(id) }
end
check("G-09 registry preserves AC-P09 ServiceLoop") { registry.include?("AC-P09") && registry.include?("ServiceLoop") }
check("G-10 registry preserves AC-P10 entrypoint profiles") { registry.include?("AC-P10") && registry.include?("named run-profiles") }
check("G-11 AC-P10 routes to PROP-029") { registry.include?("PROP-029") && registry.include?("rich entrypoint") }
check("G-12 AC-P10 does not route to host-loop config") { !registry.match?(/AC-P10.*host-loop/i) }
check("G-13 fold pressures still route to fold-struct ladder") { registry.include?("LANG-FOLD-STRUCT-ACCUMULATOR") }
check("G-14 entity pressure still routes to LANG-COMPOSE-ENTITY") { registry.include?("LANG-COMPOSE-ENTITY") }
check("G-15 dynamic dispatch remains intentionally fail-closed") { registry.include?("INTENTIONAL fail-closed") && registry.include?("LAB-DYNAMIC-CONTRACT-DISPATCH-P2") }
check("G-16 report preserves IO membrane table") { report.include?("What We Need From IO") && report.include?("PURE CORE") }

puts
puts "Section H -- ServiceLoop And Canon Anchors"
check("H-01 ch13 names ServiceLoop") { ch13.include?("ServiceLoop") }
check("H-02 ch13 names clock.every") { ch13.include?("clock.every") }
check("H-03 ch13 names tick.time") { ch13.include?("tick.time") }
check("H-04 ch13 keeps ServiceLoop Stage 4/deferred") { ch13.include?("Stage 4") && ch13.include?("deferred") }
check("H-05 covenant Postulate 14 maps service-loop liveness through PROP-037") { covenant.include?("Postulate 14") && covenant.include?("PROP-037 progression descriptors") }
check("H-06 registry points away from ad hoc host loop") { registry.include?("not route future game-loop work through an ad hoc host loop") }
check("H-07 report points player input to PROP-023") { report.include?("PROP-023") && report.include?("strategy edits") }
check("H-08 dev tutorial treats entrypoint as selector, not main") { dev_tutorial.include?("selector") && dev_tutorial.include?("not a `main`") }

puts
puts "Section I -- Closed Surfaces"
check("I-01 no capability declarations in source") { !all_source.match?(/^\s*capability\s+/) }
check("I-02 no effect declarations in source") { !all_source.match?(/^\s*effect\s+/) }
check("I-03 no stdlib.io imports") { !all_source.include?("stdlib.io") }
check("I-04 no now() in source") { !all_source.include?("now()") }
check("I-05 no random calls in source") { !all_source.include?("random") }
check("I-06 no Rack/HTTP/Socket source") { !all_source.match?(/\b(Rack|HTTP|Socket)\b/) }
check("I-07 no SQL/ORM/DB terms in source") { !all_source.match?(/\b(SQL|ORM|ActiveRecord|Database)\b/) }
check("I-08 no parser/runtime ServiceLoop authority claimed") { registry.include?("no parser/runtime authorization for a real ServiceLoop") }
check("I-09 no rich entrypoint implementation claimed") { registry.include?("rich entrypoint") && !all_source.match?(/\brun_profile\b|^\s*profile\s*\{/i) }
check("I-10 no app .ig source edits in this rebaseline") { source_has_no_ig_diff? }

puts
puts "Section J -- Closure Artifacts"
check("J-01 rebaseline doc exists") { File.exist?(DOC_PATH) }
check("J-02 rebaseline doc records expected hash") { doc.include?(EXPECTED_HASH) }
check("J-03 rebaseline doc records claimed hash drift") { doc.include?(CLAIMED_P2_HASH) && doc.downcase.include?("drift") }
check("J-04 P2 card is closed") { p2_card.include?("**Status:** CLOSED") || p2_card.include?("Status: CLOSED") }
check("J-05 P2 card records proof count") { p2_card.include?("115/115 PASS") }
check("J-06 portfolio index records P2") { portfolio.include?("LAB-AIR-COMBAT-BASELINE-P2") }

puts
total = $pass_count + $fail_count
puts "=" * 60
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 60
exit($fail_count.zero? ? 0 : 1)
