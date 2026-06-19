#!/usr/bin/env ruby
# frozen_string_literal: true

# LAB-WEB-ROUTER-BASELINE-P1 -- freeze web_router as a positive
# dual-toolchain baseline and pressure source.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, HTTP
# server, Rack adapter, sockets, middleware, header-map, path-param, or app
# source implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "web_router"
RUST_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[types.ig serve.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:15cc6c7d4ba22f29aa02878f58b8507ce4c7cbc53f3c39d1a228004f0b57c3ce"
EXPECTED_SOURCE_UNITS = %w[WebRouterExample WebRouterServe WebRouterTypes].sort.freeze
EXPECTED_TYPES = %w[HttpRequest HttpResponse].sort.freeze
EXPECTED_VARIANT_ARMS = %w[Found Created NotFound Denied UpstreamErr Unavailable].freeze
EXPECTED_CONTRACTS = %w[
  Handle MakeReq Respond RunArticle RunCreate RunHome RunMissing Serve
].sort.freeze
EXPECTED_PRESSURES = %w[WR-P01 WR-P02 WR-P03 WR-P04 WR-P05 WR-P06].freeze

$pass_count = 0
$fail_count = 0

def check(label)
  if yield
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

def registry
  @registry ||= read(APP_DIR / "PRESSURE_REGISTRY.md")
end

def app_report
  @app_report ||= read(APP_DIR / "report.md")
end

def card
  @card ||= read(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-WEB-ROUTER-BASELINE-P1.md")
end

def lab_doc
  @lab_doc ||= read(LAB_ROOT / "lab-docs" / "governance" / "lab-web-router-baseline-v0.md")
end

def portfolio
  @portfolio ||= read(LAB_ROOT / ".agents" / "portfolio-index.md")
end

def rack_core_doc
  @rack_core_doc ||= read(LAB_ROOT / "lab-docs" / "lang" / "lab-rack-core-contract-shape-and-pipeline-proof-v0.md")
end

def microservice_doc
  @microservice_doc ||= read(LAB_ROOT / "lab-docs" / "lang" / "lab-igniter-lang-microservice-envelope-p1-v0.md")
end

def rust_bin
  return RUST_RELEASE if File.executable?(RUST_RELEASE.to_s)
  RUST_DEBUG
end

TMP = Dir.mktmpdir("web_router_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def parse_json(stdout, stderr = "", status = nil)
  JSON.parse(stdout.force_encoding("UTF-8"))
rescue
  { "_parse_error" => stdout, "_stderr" => stderr, "_status" => status&.exitstatus }
end

def result_body(result)
  result["result"] || result
end

def run_rust_compile(label)
  out = File.join(TMP, "web_router_rust_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  [parse_json(stdout, stderr, status), out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "web_router_ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: #{SOURCE_FILES.inspect},
      out_path: #{out.inspect}
    )
    puts JSON.generate(result)
  RUBY
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / "lib"}", "-e", script)
  [parse_json(stdout, stderr, status), out]
end

def load_json(path)
  return nil unless File.exist?(path)
  JSON.parse(File.read(path, encoding: "UTF-8"))
end

rust1, rust_out1 = run_rust_compile("one")
rust2, rust_out2 = run_rust_compile("two")
ruby1_raw, ruby_out1 = run_ruby_compile("one")
ruby2_raw, ruby_out2 = run_ruby_compile("two")
ruby1 = result_body(ruby1_raw)
ruby2 = result_body(ruby2_raw)

manifest = load_json(File.join(rust_out1, "manifest.json")) || {}
sir = load_json(File.join(rust_out1, "semantic_ir_program.json")) || {}
report = load_json(File.join(rust_out1, "compilation_report.json")) || {}
ruby_manifest = load_json(File.join(ruby_out1, "manifest.json")) || {}

source_units = Array(manifest["source_units"])
sir_units = Array(sir["source_units"])
variant_decls = Array(sir["variant_declarations"])
contract_names = code_source.scan(/^(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort
type_names = code_source.scan(/^type\s+([A-Za-z0-9_]+)/).flatten.sort
variant_names = code_source.scan(/^variant\s+([A-Za-z0-9_]+)/).flatten.sort
call_callees = code_source.scan(/call_contract\(\s*"([^"]+)"/m).flatten

metrics = {
  files: SOURCE_FILES.size,
  types: type_names.size,
  variants: variant_names.size,
  contracts: contract_names.size,
  code_call_contract: code_source.scan(/call_contract\(/).size,
  registry_match: registry.include?("2 `match`") || registry.include?("2 / 1"),
  executable_match: code_source.scan(/\bmatch\s+[A-Za-z0-9_.]+\s*\{/).size,
  entrypoint: code_source.scan(/^entrypoint\s+/).size,
  starts_with: code_source.scan(/\bstarts_with\(/).size,
  byte_length: code_source.scan(/\bbyte_length\(/).size,
  string_eq: code_source.scan(/==/).size
}

puts "LAB-WEB-ROUTER-BASELINE-P1"

section("A: Preconditions")
check("A-01 app directory exists") { APP_DIR.directory? }
check("A-02 igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
check("A-03 Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
SOURCE_NAMES.each_with_index do |name, index|
  check("A-#{format('%02d', index + 4)} source file exists: #{name}") { File.exist?(APP_DIR / name) }
end
check("A-07 pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-08 app report exists") { File.exist?(APP_DIR / "report.md") }
check("A-09 governance card exists") { !card.empty? }
check("A-10 lab doc exists") { !lab_doc.empty? }
check("A-11 rack core context doc exists") { !rack_core_doc.empty? }
check("A-12 microservice envelope context doc exists") { !microservice_doc.empty? }

section("B: Source Metrics")
check("B-01 exactly 3 source files") { metrics[:files] == 3 }
check("B-02 exactly 2 type declarations") { metrics[:types] == 2 }
check("B-03 exactly 1 variant declaration") { metrics[:variants] == 1 }
check("B-04 exactly 8 contracts") { metrics[:contracts] == 8 }
check("B-05 exactly 10 call_contract sites") { metrics[:code_call_contract] == 10 }
check("B-06 registry preserves claimed 2 match metric") { metrics[:registry_match] }
check("B-07 exactly 1 executable match expression") { metrics[:executable_match] == 1 }
check("B-08 exactly 1 entrypoint declaration") { metrics[:entrypoint] == 1 }
check("B-09 starts_with is used for prefix route") { metrics[:starts_with] == 1 }
check("B-10 byte_length is used for root fallback") { metrics[:byte_length] == 1 }
check("B-11 String equality is used for method/path routes") { metrics[:string_eq] >= 2 }
check("B-12 no filter/concat/fold pressure in this app") { !code_source.match?(/\b(filter|concat|fold)\(/) }

section("C: Type, Variant, Contract Inventory")
check("C-01 type list matches expected") { type_names == EXPECTED_TYPES }
check("C-02 variant list matches expected") { variant_names == ["ContractResult"] }
check("C-03 contract list matches expected") { contract_names == EXPECTED_CONTRACTS }
EXPECTED_TYPES.each { |name| check("C-type #{name}") { type_names.include?(name) } }
EXPECTED_CONTRACTS.each { |name| check("C-contract #{name}") { contract_names.include?(name) } }
check("C-14 HttpRequest has method and path") { source("types.ig").include?("method : String") && source("types.ig").include?("path   : String") }
check("C-15 HttpResponse has status and body") { source("types.ig").include?("status : Integer") && source("types.ig").include?("body   : String") }
check("C-16 ContractResult has 6 arms in source") { EXPECTED_VARIANT_ARMS.all? { |arm| source("types.ig").include?(arm) } }

section("D: Ruby Compile")
check("D-01 Ruby wrapper parsed") { !ruby1_raw.key?("_parse_error") }
check("D-02 Ruby status ok") { ruby1["status"] == "ok" }
check("D-03 Ruby diagnostics empty") { Array(ruby1["diagnostics"]).empty? }
check("D-04 Ruby warnings empty") { Array(ruby1["warnings"]).empty? }
check("D-05 Ruby source hash matches live baseline") { ruby1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-06 Ruby source hash stable across two runs") { ruby2["source_hash"] == ruby1["source_hash"] }
check("D-07 Ruby contracts match expected") { Array(ruby1["contracts"]).sort == EXPECTED_CONTRACTS }
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage #{stage}") { ruby1.dig("stages", stage) == "ok" }
end
check("D-13 Ruby igapp directory exists") { File.directory?(ruby_out1) }
check("D-14 Ruby manifest exists") { File.exist?(File.join(ruby_out1, "manifest.json")) }
check("D-15 Ruby manifest source hash matches") { ruby_manifest["source_hash"] == EXPECTED_SOURCE_HASH }

section("E: Rust Compile")
check("E-01 Rust stdout parsed") { !rust1.key?("_parse_error") }
check("E-02 Rust status ok") { rust1["status"] == "ok" }
check("E-03 Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("E-04 Rust warnings empty") { Array(rust1["warnings"]).empty? }
check("E-05 Rust source hash matches live baseline") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("E-06 Rust source hash stable across two runs") { rust2["source_hash"] == rust1["source_hash"] }
check("E-07 Rust contracts match expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
%w[parse classify typecheck emit assemble].each do |stage|
  check("E-stage #{stage}") { rust1.dig("stages", stage) == "ok" }
end
check("E-13 Rust igapp directory exists") { File.directory?(rust_out1) }
check("E-14 Rust second igapp directory exists") { File.directory?(rust_out2) }
check("E-15 Ruby and Rust source hashes agree") { ruby1["source_hash"] == rust1["source_hash"] }

section("F: Manifest and SemanticIR")
check("F-01 manifest source_hash matches") { manifest["source_hash"] == EXPECTED_SOURCE_HASH }
check("F-02 SIR source_hash matches") { sir["source_hash"] == EXPECTED_SOURCE_HASH }
check("F-03 report source_hash matches") { report["source_hash"] == EXPECTED_SOURCE_HASH }
check("F-04 manifest fragment class is core") { manifest["fragment_class"] == "core" }
check("F-05 manifest has 3 source units") { source_units.size == 3 }
check("F-06 SIR has 3 source units") { sir_units.size == 3 }
check("F-07 manifest source units match expected") { source_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("F-08 SIR source units match expected") { sir_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("F-09 manifest contract index has 8 entries") { Hash(manifest["contract_index"]).size == 8 }
check("F-10 manifest contract list matches") { Hash(manifest["contract_index"]).keys.sort == EXPECTED_CONTRACTS }
check("F-11 SIR contract list matches") { Array(sir["contracts"]).map { |c| c["contract_name"] || c["name"] }.compact.sort == EXPECTED_CONTRACTS }
check("F-12 manifest has semantic_ir_ref") { !manifest["semantic_ir_ref"].to_s.empty? }
check("F-13 manifest has sourcemap_ref") { !manifest["sourcemap_ref"].to_s.empty? }
check("F-14 diagnostics.json exists") { File.exist?(File.join(rust_out1, "diagnostics.json")) }
check("F-15 sourcemap.json exists") { File.exist?(File.join(rust_out1, "sourcemap.json")) }

section("G: Variant and Match Evidence")
variant = variant_decls.find { |decl| decl["name"] == "ContractResult" } || {}
check("G-01 SIR has ContractResult variant") { variant["name"] == "ContractResult" }
check("G-02 ContractResult arms match expected order") { Array(variant["arms"]).map { |arm| arm["name"] } == EXPECTED_VARIANT_ARMS }
EXPECTED_VARIANT_ARMS.each_with_index do |arm, index|
  check("G-#{format('%02d', index + 3)} variant arm #{arm} present") { Array(variant["arms"]).any? { |item| item["name"] == arm } }
end
check("G-09 Found carries body:String") { Array(variant["arms"]).find { |a| a["name"] == "Found" }.dig("fields", 0, "type", "name") == "String" }
check("G-10 Created carries body:String") { Array(variant["arms"]).find { |a| a["name"] == "Created" }.dig("fields", 0, "type", "name") == "String" }
check("G-11 empty outcome arms have no payloads") do
  %w[NotFound Denied UpstreamErr Unavailable].all? do |name|
    Array(Array(variant["arms"]).find { |a| a["name"] == name }["fields"]).empty?
  end
end
check("G-12 Respond uses one exhaustive match") { source("serve.ig").include?("compute resp : HttpResponse = match result") }
check("G-13 Respond maps Found to 200") { source("serve.ig").include?("Found") && source("serve.ig").include?("status: 200") }
check("G-14 Respond maps Created to 201") { source("serve.ig").include?("Created") && source("serve.ig").include?("status: 201") }
check("G-15 Respond maps NotFound to 404") { source("serve.ig").include?("NotFound") && source("serve.ig").include?("status: 404") }
check("G-16 Respond maps Denied to 403") { source("serve.ig").include?("Denied") && source("serve.ig").include?("status: 403") }
check("G-17 Respond maps UpstreamErr to 502") { source("serve.ig").include?("UpstreamErr") && source("serve.ig").include?("status: 502") }
check("G-18 Respond maps Unavailable to 503") { source("serve.ig").include?("Unavailable") && source("serve.ig").include?("status: 503") }
check("G-19 KDR relief documented") { registry.include?("KDR") && registry.include?("sealed variant") && app_report.include?("stringly") }

section("H: Routing and Pipeline Shape")
check("H-01 Handle routes /articles/ by prefix") { source("serve.ig").include?('starts_with(req.path, "/articles/")') }
check("H-02 Handle gates article route to GET") { source("serve.ig").include?('req.method == "GET"') }
check("H-03 Handle routes POST /articles to Created") { source("serve.ig").include?('req.path == "/articles"') && source("serve.ig").include?("Created { body: \"article created\" }") }
check("H-04 Handle routes root to home") { source("serve.ig").include?("Found { body: \"home\" }") }
check("H-05 unknown non-root path goes NotFound") { source("serve.ig").include?("byte_length(req.path) > 1") && source("serve.ig").include?("NotFound { }") }
check("H-06 Serve calls Handle") { source("serve.ig").include?('call_contract("Handle", req)') }
check("H-07 Serve calls Respond") { source("serve.ig").include?('call_contract("Respond", result)') }
check("H-08 scenario RunHome exists") { source("example.ig").include?("contract RunHome") }
check("H-09 scenario RunArticle exists") { source("example.ig").include?("contract RunArticle") }
check("H-10 scenario RunCreate exists") { source("example.ig").include?("contract RunCreate") }
check("H-11 scenario RunMissing exists") { source("example.ig").include?("contract RunMissing") }
check("H-12 all call_contract callees are Tier-1 literals") { call_callees.size == metrics[:code_call_contract] }
check("H-13 all call_contract callees are PascalCase") { call_callees.all? { |name| name.match?(/\A[A-Z]/) } }

section("I: Entrypoint")
check("I-01 source has entrypoint RunArticle") { source("example.ig").include?("entrypoint RunArticle") }
check("I-02 manifest default entrypoint resolves RunArticle") { manifest.dig("entrypoint", "resolved_contract") == "RunArticle" }
check("I-03 manifest declared target is RunArticle") { manifest.dig("entrypoint", "declared_target") == "RunArticle" }
check("I-04 SIR entrypoint resolves RunArticle") { sir.dig("entrypoint", "resolved_contract") == "RunArticle" }
check("I-05 SIR entrypoint target is RunArticle") { sir.dig("entrypoint", "target") == "RunArticle" }
check("I-06 entrypoint path points at run_article") { manifest.dig("entrypoint", "contract_path").to_s.include?("run_article") }
check("I-07 registry records entrypoint") { registry.include?("entrypoint | `RunArticle`") || registry.include?("entrypoint RunArticle") }
check("I-08 lab doc records entrypoint") { lab_doc.include?("entrypoint RunArticle") || lab_doc.include?("`RunArticle`") }

section("J: Pressure Registry WR-P01..WR-P06")
EXPECTED_PRESSURES.each_with_index do |pid, index|
  check("J-#{format('%02d', index + 1)} registry preserves #{pid}") { registry.include?(pid) }
end
check("J-07 WR-P01 routes to LANG-SUMTYPE-CONSTRUCT-MATCH") { registry.include?("WR-P01") && registry.include?("LANG-SUMTYPE-CONSTRUCT-MATCH") }
check("J-08 WR-P02 marks stdlib.text route positive") { registry.include?("WR-P02") && registry.include?("stdlib.text") }
check("J-09 WR-P03 routes header Map construction") { registry.include?("WR-P03") && registry.include?("LANG-STDLIB-MAP") }
check("J-10 WR-P04 routes split/Collection/Option") { registry.include?("WR-P04") && registry.include?("split") && registry.include?("Option") }
check("J-11 WR-P05 routes accept loop behind ServiceLoop") { registry.include?("WR-P05") && registry.include?("PROP-037") }
check("J-12 WR-P06 routes record-literal factory pressure") { registry.include?("WR-P06") && registry.include?("record-literal") }
check("J-13 registry classifies capability discovery positive") { registry.include?("Capability Discovery") && registry.include?("dual-clean") }
check("J-14 registry records closure summary") { registry.include?("Baseline Closure") && registry.include?("LAB-WEB-ROUTER-BASELINE-P1") }

section("K: Closed Surfaces")
check("K-01 no capability declarations") { !code_source.match?(/^\s*capability\s+/) }
check("K-02 no effect declarations") { !code_source.match?(/^\s*effect\s+/) }
check("K-03 no observed/effect contract modifier") { !code_source.match?(/^\s*(observed|effect|privileged|irreversible)\s+contract\s+/) }
check("K-04 no stdlib.io import") { !all_source.include?("stdlib.io") }
check("K-05 no socket/network server terms in source code") { !code_source.match?(/\b(Socket|TCP|listen|accept|bind|server)\b/i) }
check("K-06 no Rack env compatibility code") { !code_source.match?(/\bRack|env|PATH_INFO|REQUEST_METHOD\b/) }
check("K-07 no header Map construction") { !code_source.match?(/Map\[|map_empty|map_from_pairs|headers/) }
check("K-08 no path-param parser") { !code_source.match?(/\bsplit\(|last\(|params|param/) }
check("K-09 no dynamic route dispatch") { !code_source.match?(/call_contract\(\s*[a-z_][a-zA-Z0-9_]*\s*,/) }
check("K-10 no middleware or streaming") { !code_source.match?(/\b(middleware|stream|chunk)\b/i) }
check("K-11 manifest effects empty") { Array(manifest["effects"]).empty? }
check("K-12 manifest capabilities empty") { Array(manifest["capabilities"]).empty? }
check("K-13 requirements has no capability requirements") do
  reqs = load_json(File.join(rust_out1, "requirements.json")) || {}
  reqs.to_s !~ /capability|socket|network|storage|http/i
end
check("K-14 registry safety interpretation closes IO") { registry.include?("It does NOT claim") && registry.include?("sockets") }
check("K-15 card closed surfaces preserved") { card.include?("No sockets") && card.include?("No header `Map`") }
check("K-16 lab doc closed surfaces preserved") { lab_doc.include?("No sockets") && lab_doc.include?("No header `Map`") }

section("L: Boundary Context")
check("L-01 Rack core doc keeps accept loop deferred") { rack_core_doc.include?("Accept-loop") && rack_core_doc.include?("PROP-037") }
check("L-02 Rack core doc says no real network IO") { rack_core_doc.include?("no real network I/O") || rack_core_doc.include?("No real network I/O") }
check("L-03 Rack core doc has HTTP contract algebra proof base") { rack_core_doc.include?("HTTP contract algebra proof base") }
check("L-04 microservice doc rejects server implementation") { microservice_doc.include?("Not a server implementation") }
check("L-05 microservice doc names ingress substrate") { microservice_doc.include?("ingress_substrate") }
check("L-06 microservice doc keeps old Ruby framework non-authority") { microservice_doc.include?("old Ruby") && microservice_doc.include?("not authority") }
check("L-07 app report routes accept loop to ServiceLoop") { app_report.include?("Accept loop") && app_report.include?("PROP-037") }
check("L-08 app report routes request envelope to microservice") { app_report.include?("ServiceRequest") && app_report.include?("LAB-IGNITER-LANG-MICROSERVICE") }

section("M: Closure Artifacts")
check("M-01 registry records live hash") { registry.include?(EXPECTED_SOURCE_HASH) }
check("M-02 card records live hash") { card.include?(EXPECTED_SOURCE_HASH) }
check("M-03 lab doc records live hash") { lab_doc.include?(EXPECTED_SOURCE_HASH) }
check("M-04 lab doc records proof runner") { lab_doc.include?("verify_lab_web_router_baseline_p1.rb") }
check("M-05 card status is closed") { card.include?("**Status:** CLOSED") }
check("M-06 card records proof result") { card.include?("PROVED") && card.include?("PASS") }
check("M-07 portfolio index has closure entry") { portfolio.include?("LAB-WEB-ROUTER-BASELINE-P1 CLOSED") }
check("M-08 proof runner uses Open3") { File.read(__FILE__, encoding: "UTF-8").include?("Open3.capture3") }
check("M-09 proof runner uses Dir.mktmpdir") { File.read(__FILE__, encoding: "UTF-8").include?("Dir.mktmpdir") }
check("M-10 proof runner avoids shell pipe") do
  pipe_head = ["|", "head"].join(" ")
  !File.read(__FILE__, encoding: "UTF-8").include?(pipe_head)
end

puts
total = $pass_count + $fail_count
puts "=" * 72
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 72
exit($fail_count.zero? ? 0 : 1)
