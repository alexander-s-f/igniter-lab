#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_lead_router_baseline_p1.rb
# LAB-LEAD-ROUTER-BASELINE-P1 - freeze lead_router as a dual-toolchain
# positive baseline and pressure source.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, IO, HTTP,
# DB, clock, RNG, Outcome/bind, entity, or fold-to-struct implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

ROOT = Pathname.new(__dir__).parent
LAB_ROOT = ROOT.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "lead_router"
RUST_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[types.ig pipeline.ig service.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:3cca9ed52a593e60ed86fb59e359809d255425af5690ded364cd8329fab71e1b"
DOC_PRIOR_HASH = "sha256:16deae290738578a09cc324de18ff2312b14b960e0d581945285b913d534e3ba"

EXPECTED_TYPES = %w[
  Ctx LeadSignal Params StepReceipt Vendor VendorResponse
].sort.freeze

EXPECTED_VARIANTS = %w[Pipe].freeze

EXPECTED_CONTRACTS = %w[
  BuildLeadSignal BusinessHours CheckAvailability CtxWithBid CtxWithMode
  CtxWithSlots CtxWithTrade CtxWithVendor CtxWithZip DemoVendor ElocalResponse
  FindTrade FindVendor FindZip GenerateResults InBusinessHours InquirlyResponse
  MakeAccept MakeParams MakeReject MakeSignalAccept MakeSignalReject NullVendor
  ResolveMode RunAccept RunAcceptSignal RunPipeline RunReject SumSlots Validate
  VendorProtocol
].sort.freeze

PRESSURE_IDS = %w[
  LR-P01 LR-P02 LR-P03 LR-P04 LR-P05 LR-P06 LR-P07 LR-P08 LR-P09 LR-P10 LR-P11
].freeze

$pass_count = 0
$fail_count = 0

def check(label)
  ok = yield
  if ok
    $pass_count += 1
    puts "  PASS  #{label}"
  else
    $fail_count += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail_count += 1
  puts "  ERROR #{label} - #{e.class}: #{e.message.lines.first&.strip}"
end

def section(title)
  puts "\n-- #{title}"
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue
  ""
end

def source(name)
  read(APP_DIR / name)
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| source(name) }.join("\n")
end

def code_source
  @code_source ||= all_source.lines
    .reject { |line| line.strip.start_with?("--") }
    .map { |line| line.sub(/\s+--.*$/, "") }
    .join
end

def report
  @report ||= source("report.md")
end

def registry
  @registry ||= source("PRESSURE_REGISTRY.md")
end

def rust_bin
  return RUST_RELEASE if File.executable?(RUST_RELEASE.to_s)
  RUST_DEBUG
end

TMP = Dir.mktmpdir("lead_router_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def parse_json(stdout, stderr = "", status = nil)
  JSON.parse(stdout.force_encoding("UTF-8"))
rescue
  { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status&.exitstatus }
end

def run_rust_compile(label)
  out = File.join(TMP, "lead_router_rust_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  [parse_json(stdout, stderr, status), out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "lead_router_ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    paths = #{SOURCE_FILES.inspect}
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: paths, out_path: #{out.inspect})
    puts JSON.generate(result)
  RUBY
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / "lib"}", "-e", script)
  [parse_json(stdout, stderr, status), out]
end

def result_body(result)
  result["result"] || result
end

def load_json(path)
  return nil unless File.exist?(path)
  JSON.parse(File.read(path, encoding: "UTF-8"))
end

rust1, rust_out1 = run_rust_compile("one")
sleep 1
rust2, rust_out2 = run_rust_compile("two")
ruby1, ruby_out1 = run_ruby_compile("one")
ruby2, ruby_out2 = run_ruby_compile("two")

rust_manifest = load_json(File.join(rust_out1, "manifest.json")) || {}
rust_sir = load_json(File.join(rust_out1, "semantic_ir_program.json")) || {}
rust_report = load_json(File.join(rust_out1, "compilation_report.json")) || {}
ruby_manifest = load_json(File.join(ruby_out1, "manifest.json")) || {}

ruby_result = result_body(ruby1)
ruby_result2 = result_body(ruby2)

metrics = {
  files: SOURCE_FILES.size,
  types: all_source.scan(/^type\s+/).size,
  variants: all_source.scan(/^variant\s+/).size,
  contracts: all_source.scan(/^(?:pure\s+)?contract\s+/).size,
  textual_call_contract: all_source.scan(/call_contract\(/).size,
  code_call_contract: code_source.scan(/call_contract\(/).size,
  textual_match: all_source.scan(/\bmatch\s+/).size,
  code_match: code_source.scan(/\bmatch\s+/).size,
  fold: code_source.scan(/\bfold\(/).size,
  entrypoint: code_source.scan(/^entrypoint\s+/).size
}

type_names = all_source.scan(/^type\s+([A-Za-z0-9_]+)/).flatten.sort
variant_names = all_source.scan(/^variant\s+([A-Za-z0-9_]+)/).flatten.sort
contract_names = all_source.scan(/^(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort
call_callees = code_source.scan(/call_contract\(\s*"([^"]+)"/m).flatten
nonliteral_calls = code_source.scan(/call_contract\((?!\s*")/m)
match_blocks = code_source.scan(/\bmatch\s+[A-Za-z0-9_.]+\s*\{/)

puts "LAB-LEAD-ROUTER-BASELINE-P1"

section("A: Preconditions")
check("A-01 app directory exists") { APP_DIR.directory? }
check("A-02 igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
check("A-03 Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-04 Rust runner uses release or debug compiler") { [RUST_RELEASE, RUST_DEBUG].include?(rust_bin) }
SOURCE_NAMES.each_with_index do |name, index|
  check("A-#{format('%02d', index + 5)} source file exists: #{name}") { File.exist?(APP_DIR / name) }
end
check("A-09 pressure registry present") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-10 report present") { File.exist?(APP_DIR / "report.md") }

section("B: Source Metrics")
check("B-01 exactly 4 source files") { metrics[:files] == 4 }
check("B-02 exactly 6 type declarations") { metrics[:types] == 6 }
check("B-03 exactly 1 variant declaration") { metrics[:variants] == 1 }
check("B-04 exactly 31 contracts") { metrics[:contracts] == 31 }
check("B-05 textual call_contract mentions match registry count 38") { metrics[:textual_call_contract] == 38 }
check("B-06 executable call_contract sites are 37 after stripping comments") { metrics[:code_call_contract] == 37 }
check("B-07 textual match mentions preserve registry count 10") { metrics[:textual_match] == 10 }
check("B-08 executable match expressions are 9 after stripping comments") { metrics[:code_match] == 9 }
check("B-09 exactly 1 scalar fold") { metrics[:fold] == 1 }
check("B-10 exactly 1 bare entrypoint") { metrics[:entrypoint] == 1 }

section("C: Type, Variant, Contract Inventory")
check("C-01 type list matches expected") { type_names == EXPECTED_TYPES }
check("C-02 variant list matches expected") { variant_names == EXPECTED_VARIANTS }
check("C-03 contract list matches expected") { contract_names == EXPECTED_CONTRACTS }
EXPECTED_TYPES.each { |name| check("C-type #{name}") { type_names.include?(name) } }
EXPECTED_VARIANTS.each { |name| check("C-variant #{name}") { variant_names.include?(name) } }
EXPECTED_CONTRACTS.each { |name| check("C-contract #{name}") { contract_names.include?(name) } }

section("D: Ruby Compile")
check("D-01 Ruby status ok") { ruby_result["status"] == "ok" }
check("D-02 Ruby diagnostics empty") { Array(ruby_result["diagnostics"]).empty? }
check("D-03 Ruby warnings empty") { Array(ruby_result["warnings"]).empty? }
check("D-04 Ruby source hash matches live baseline") { ruby_result["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-05 Ruby source hash stable across two runs") { ruby_result2["source_hash"] == ruby_result["source_hash"] }
check("D-06 Ruby contracts match expected") { Array(ruby_result["contracts"]).sort == EXPECTED_CONTRACTS }
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage #{stage}") { ruby_result.dig("stages", stage) == "ok" }
end
check("D-12 Ruby igapp directory exists") { File.directory?(ruby_out1) }
check("D-13 Ruby manifest exists") { File.exist?(File.join(ruby_out1, "manifest.json")) }
check("D-14 Ruby manifest entrypoint is RunAccept") { ruby_manifest.dig("entrypoint", "resolved_contract") == "RunAccept" }
check("D-15 Ruby source_units count is 4") { Array(ruby_result.dig("report", "source_units")).size == 4 }

section("E: Rust Compile")
check("E-01 Rust status ok") { rust1["status"] == "ok" }
check("E-02 Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("E-03 Rust warnings empty") { Array(rust1["warnings"]).empty? }
check("E-04 Rust source hash matches live baseline") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("E-05 Rust source hash stable across spaced two runs") { rust2["source_hash"] == rust1["source_hash"] }
check("E-06 Rust contracts match expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
%w[parse classify typecheck emit assemble].each do |stage|
  check("E-stage #{stage}") { rust1.dig("stages", stage) == "ok" }
end
check("E-12 Rust igapp directory exists") { File.directory?(rust_out1) }
check("E-13 Rust manifest exists") { File.exist?(File.join(rust_out1, "manifest.json")) }
check("E-14 Rust semantic_ir exists") { File.exist?(File.join(rust_out1, "semantic_ir_program.json")) }
check("E-15 Rust diagnostics file exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }
check("E-16 Rust compilation_report exists") { File.exist?(File.join(rust_out1, "compilation_report.json")) }
check("E-17 Rust manifest entrypoint is RunAccept") { rust_manifest.dig("entrypoint", "resolved_contract") == "RunAccept" }
check("E-18 Rust SIR entrypoint is RunAccept") { rust_sir.dig("entrypoint", "resolved_contract") == "RunAccept" || rust_sir.dig("entrypoint", "target") == "RunAccept" }

section("F: Hash, Manifest, Source Units")
check("F-01 Ruby and Rust live source hashes agree") { ruby_result["source_hash"] == rust1["source_hash"] }
check("F-02 doc prior hash is not the live full-app hash") { DOC_PRIOR_HASH != EXPECTED_SOURCE_HASH }
check("F-03 rust manifest source_hash matches result") { rust_manifest["source_hash"] == rust1["source_hash"] }
check("F-04 rust report source_hash matches result") { rust_report["source_hash"] == rust1["source_hash"] }
check("F-05 rust source_units count is 4") { Array(rust_manifest["source_units"]).size == 4 }
check("F-06 rust source_unit modules match expected") do
  Array(rust_manifest["source_units"]).map { |u| u["module"] }.sort == %w[
    LeadRouterExample LeadRouterPipeline LeadRouterService LeadRouterTypes
  ].sort
end
check("F-07 each rust source_unit has sha256 source_hash") do
  Array(rust_manifest["source_units"]).all? { |u| u["source_hash"].to_s.start_with?("sha256:") }
end
check("F-08 entrypoint source span is present") { rust_manifest.dig("entrypoint", "source_span", "line").to_i > 0 }

section("G: Static call_contract Discipline")
check("G-01 no executable non-literal call_contract forms") { nonliteral_calls.empty? }
check("G-02 every executable call_contract has a string literal callee") { call_callees.size == metrics[:code_call_contract] }
check("G-03 every executable callee names a known contract") { call_callees.all? { |name| contract_names.include?(name) } }
check("G-04 desired dynamic dispatch appears only in comments") do
  all_source.include?("call_contract(vendor_key + \"Response\", p)") &&
    !code_source.include?("call_contract(vendor_key + \"Response\", p)")
end
check("G-05 VendorProtocol branches statically") do
  source("service.ig").include?('call_contract("InquirlyResponse", p)') &&
    source("service.ig").include?('call_contract("ElocalResponse", p)')
end
check("G-06 RunPipeline uses literal step calls") do
  %w[Validate FindTrade FindVendor FindZip BusinessHours ResolveMode CheckAvailability GenerateResults].all? do |name|
    source("service.ig").include?("call_contract(\"#{name}\"")
  end
end
check("G-07 MakeParams factory pins Params") { source("service.ig").include?("contract MakeParams") && source("service.ig").include?("output p : Params") }
check("G-08 no call_contract callee is lowercase stdlib alias") { call_callees.none? { |name| name =~ /\A[a-z]/ } }

section("H: Variant + Match Railway")
check("H-01 Pipe variant present") { source("types.ig").include?("variant Pipe") }
check("H-02 Proceed arm carries Ctx") { source("types.ig").include?("Proceed { ctx : Ctx }") }
check("H-03 Reject arm carries stage/message") { source("types.ig").include?("Reject  { stage : String, message : String }") }
check("H-04 exactly 9 executable match blocks") { match_blocks.size == 9 }
check("H-05 railway steps carry Reject unchanged in 7 step matches") { code_source.scan(/Reject\s+\{\s*stage,\s*message\s*\}\s*=>\s*Reject\s*\{/).size >= 7 }
check("H-06 FindVendor uses match over prev") { source("pipeline.ig").include?("contract FindVendor") && source("pipeline.ig").include?("compute r = match prev") }
check("H-07 ElocalResponse maps Pipe to VendorResponse") { source("service.ig").include?("contract ElocalResponse") && source("service.ig").include?("output resp : VendorResponse") }
check("H-08 BuildLeadSignal matches Pipe") { source("service.ig").include?("contract BuildLeadSignal") && source("service.ig").include?("compute sig = match p") }
check("H-09 report names dry-monads bind") { report.include?("dry-monads") && report.include?(".bind") }
check("H-10 report says variant + match compile dual-clean") { report.include?("variant` + `match") && report.include?("dual-clean") }

section("I: Entry Point and Run Profiles")
check("I-01 source declares entrypoint RunAccept") { source("example.ig").include?("entrypoint RunAccept") }
check("I-02 RunAccept contract present") { contract_names.include?("RunAccept") }
check("I-03 RunAcceptSignal contract present") { contract_names.include?("RunAcceptSignal") }
check("I-04 RunReject contract present") { contract_names.include?("RunReject") }
check("I-05 LR-P11 present in registry") { registry.include?("LR-P11") }
check("I-06 LR-P11 routes to PROP-029") { registry.include?("PROP-029") && registry.include?("run-profile") }
check("I-07 dev tutorial says bare entrypoint implemented") { read(LANG_ROOT / "docs" / "dev-tutorial.md").include?("entrypoint Double") }
check("I-08 dev tutorial marks rich entrypoint not dual-clean") { read(LANG_ROOT / "docs" / "dev-tutorial.md").include?("Rich entrypoint") }

section("J: Pressure Registry IDs")
PRESSURE_IDS.each { |id| check("J-id #{id} present") { registry.include?(id) } }
check("J-12 LR-P01 routes Outcome/bind") { registry.include?("Outcome") && registry.include?("bind") && registry.include?("and_then") }
check("J-13 LR-P02 routes fold struct accumulator") { registry.include?("LANG-FOLD-STRUCT-ACCUMULATOR") }
check("J-14 LR-P04 routes compose entity") { registry.include?("LANG-COMPOSE-ENTITY") }
check("J-15 LR-P05 routes dynamic dispatch P2") { registry.include?("LAB-DYNAMIC-CONTRACT-DISPATCH-P2") }
check("J-16 LR-P07 routes storage capability") { registry.include?("StorageCapability") && registry.include?("PROP-046") }
check("J-17 LR-P10 routes microservice envelope") { registry.include?("ServiceRequest") && registry.include?("ServiceResponse") }

section("K: IO and Runtime Boundaries")
check("K-01 source has no capability declarations") { !code_source.match?(/^\s*capability\s+/) }
check("K-02 source has no effect declarations") { !code_source.match?(/^\s*effect\s+/) }
check("K-03 source has no DB/SQL/ORM code") { !code_source.match?(/\b(SQL|ActiveRecord|ORM|SELECT|INSERT|UPDATE)\b/) }
check("K-04 source has no HTTP server primitives") { !code_source.match?(/\b(Rack|socket|listen|accept_loop)\b/) }
check("K-05 source has no clock now call") { !code_source.match?(/\bnow\(|Time\.current|DateTime\b/) }
check("K-06 source has no RNG call") { !code_source.match?(/\bRandom\b|rng\(|rand\(/) }
check("K-07 clock is injected as current_min") { source("pipeline.ig").include?("input current_min : Integer") }
check("K-08 RNG token is injected as upi") { source("service.ig").include?("input upi          : String") || source("pipeline.ig").include?("input upi : String") }
check("K-09 DB read results are injected flags/data") { source("service.ig").include?("input trade_found") && source("service.ig").include?("input vendor") && source("service.ig").include?("input slot_counts") }
check("K-10 outbox write remains pure payload only") { source("service.ig").include?("BuildLeadSignal") && registry.include?("OutboxEvent.create!") }

section("L: Request/Reply Context and Complementarity")
check("L-01 report names request/reply service") { report.include?("request/reply") }
check("L-02 report contrasts air_combat tick-loop") { report.include?("air_combat") && report.include?("tick-loop") }
check("L-03 report names ServiceRequest envelope") { report.include?("ServiceRequest") }
check("L-04 report names ServiceResponse envelope") { report.include?("ServiceResponse") }
check("L-05 IO P5 doc keeps no HTTP accept loop closed") { read(LAB_ROOT / "lab-docs" / "lang" / "lab-igniter-lang-io-runtime-p5-regression-v0.md").include?("No HTTP accept loop") }
check("L-06 microservice P3 doc says no HTTP server") { read(LAB_ROOT / "lab-docs" / "lang" / "lab-igniter-lang-microservice-p3-runtime-wired-envelope-proof-v0.md").include?("no HTTP server") }
check("L-07 microservice P1 doc defines ServiceRequest") { read(LAB_ROOT / "lab-docs" / "lang" / "lab-igniter-lang-microservice-envelope-p1-v0.md").include?("ServiceRequest") }
check("L-08 report says pure core stays pure") { report.include?("pure core stays pure") }

section("M: Fold, Entity, Dynamic Dispatch Route Alignment")
check("M-01 scalar fold SumSlots present") { source("pipeline.ig").include?("fold(slot_counts, 0, (acc, s) -> acc + s)") }
check("M-02 fold P3 card closed") { read(LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-FOLD-STRUCT-ACCUMULATOR-P3.md").include?("CLOSED") }
check("M-03 entity PROP P2 card closed") { read(LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-COMPOSE-ENTITY-PROP-P2.md").include?("CLOSED") }
check("M-04 dynamic dispatch P2 card preserves fail-closed") { read(LAB_ROOT / ".agents" / "work" / "cards" / "lab" / "LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md").include?("PRESERVE fail-closed") }
check("M-05 dev tutorial marks dynamic dispatch blocked") { read(LANG_ROOT / "docs" / "dev-tutorial.md").include?("Dynamic dispatch is blocked") }

section("N: Liveness and Artifact Sanity")
liveness = rust1["liveness_instrumentation"] || {}
counters = liveness["counters"] || {}
check("N-01 liveness object present") { liveness["kind"] == "liveness_instrumentation" }
check("N-02 liveness breaches empty") { Array(liveness["breaches"]).empty? }
check("N-03 tc infer depth below fatal limit") { counters.fetch("typechecker.infer_expr.max_depth", 1001).to_i < 1000 }
check("N-04 form resolver walk depth below fatal limit") { counters.fetch("form_resolver.walk_expr.max_depth", 1001).to_i < 1000 }
check("N-05 parser import steps below 100") { counters.fetch("parser.parse_import.max_steps", 101).to_i < 100 }
check("N-06 second rust out path differs from first") { rust_out2 != rust_out1 }
check("N-07 second ruby out path differs from first") { ruby_out2 != ruby_out1 }

total = $pass_count + $fail_count
puts "\nResult: #{$pass_count}/#{total} PASS (#{$fail_count} FAIL)"

if $fail_count.zero? && $pass_count >= 95
  puts "VERDICT: PASS - lead_router positive baseline frozen."
  exit 0
else
  puts "VERDICT: FAIL - lead_router baseline proof did not satisfy gate."
  exit 1
end
