#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_call_router_baseline_p1.rb
# LAB-CALL-ROUTER-BASELINE-P1 -- freeze call_router as a positive
# dual-toolchain baseline and pressure source.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, IO,
# webhook server, storage, clock, queue, or app source implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "call_router"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[
  types.ig correlate.ig operator.ig webhook.ig service.ig example.ig
].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:1b8da43dd1fb66ae6b587056bfe459734e9eb854ccb2a1b308e996ac0334eed5"
EXPECTED_SOURCE_UNITS = %w[
  CallRouterCorrelate CallRouterExample CallRouterOperator
  CallRouterService CallRouterTypes CallRouterWebhook
].sort.freeze
EXPECTED_TYPES = %w[
  CallrailCall CallrailCompany ChannelBehavior TradeVendor Operator RcEvent CallLog
].sort.freeze
EXPECTED_VARIANTS = {
  "Telephony" => %w[NoCall Ringing CallConnected],
  "MatchResult" => %w[Matched Unmatched],
  "ChannelFlow" => %w[Marketing CallCenter Inactive]
}.freeze
EXPECTED_CONTRACTS = %w[
  AppendWebhook BuildLog ChannelBehaviorOf ChannelFlowOf ClassifyTelephony
  ClearContext CustomerPhoneOf DemoCall DemoCompany DemoInboundEvent
  DemoNoCallEvent DemoOperator DemoVendor HandleRingcentral LifecycleComplete
  MakeBehavior MatchCall OperatorChannelBehavior OperatorStep RunChannel
  RunConnectedMatched RunNoCall RunUpsert SetContext WebhookCount
].sort.freeze
EXPECTED_PRESSURES = (1..11).map { |n| "CR-P#{format('%02d', n)}" }.freeze

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

def section(title)
  puts
  puts "Section #{title}"
end

def read_path(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def read_source(name)
  read_path(APP_DIR / name)
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| read_source(name) }.join("\n")
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

def normalize_compile_result(result)
  result["result"] || result
end

TMP = Dir.mktmpdir("call_router_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "call_router_rust_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout,
    "_stderr" => stderr,
    "_status" => status.exitstatus
  }
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "call_router_ruby_#{label}.igapp")
  script = <<~RUBY
    require "json"
    require "igniter_lang/compiler_orchestrator"
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: #{SOURCE_FILES.inspect},
      out_path: #{out.inspect}
    )
    inner = result["result"] || result
    puts JSON.generate({
      "status" => result["status"],
      "result" => {
        "status" => inner["status"],
        "source_hash" => inner["source_hash"],
        "diagnostics" => inner["diagnostics"],
        "warnings" => inner["warnings"],
        "contracts" => inner["contracts"],
        "stages" => inner["stages"],
        "igapp_path" => inner["igapp_path"]
      }
    })
  RUBY
  stdout, stderr, status = Open3.capture3("ruby", "-I#{LANG_ROOT / 'lib'}", "-e", script)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout,
    "_stderr" => stderr,
    "_status" => status.exitstatus
  }
  [parsed, out]
end

rust1, rust_out1 = run_rust_compile("one")
rust2, rust_out2 = run_rust_compile("two")
ruby1_raw, ruby_out1 = run_ruby_compile("one")
ruby2_raw, ruby_out2 = run_ruby_compile("two")
ruby1 = normalize_compile_result(ruby1_raw)
ruby2 = normalize_compile_result(ruby2_raw)

manifest_path = File.join(rust_out1, "manifest.json")
sir_path = File.join(rust_out1, "semantic_ir_program.json")
sourcemap_path = File.join(rust_out1, "sourcemap.json")
report_path = File.join(rust_out1, "compilation_report.json")
diagnostics_path = File.join(rust_out1, "diagnostics.json")

$manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path, encoding: "UTF-8")) : nil
$sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path, encoding: "UTF-8")) : nil
$sourcemap = File.exist?(sourcemap_path) ? JSON.parse(File.read(sourcemap_path, encoding: "UTF-8")) : nil
$report = File.exist?(report_path) ? JSON.parse(File.read(report_path, encoding: "UTF-8")) : nil

registry = read_path(APP_DIR / "PRESSURE_REGISTRY.md")
app_report = read_path(APP_DIR / "report.md")
card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-CALL-ROUTER-BASELINE-P1.md")
lab_doc = read_path(LAB_ROOT / "lab-docs" / "governance" / "lab-call-router-compilation-baseline-v0.md")
portfolio = read_path(LAB_ROOT / ".agents" / "portfolio-index.md")
dev_tutorial = read_path(LANG_ROOT / "docs" / "dev-tutorial.md")
ch13 = read_path(LANG_ROOT / "docs" / "spec" / "ch13-managed-recursion.md")
covenant = read_path(LANG_ROOT / "docs" / "language-covenant.md")
dynamic_dispatch_card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "lab" / "LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md")
lead_card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-LEAD-ROUTER-BASELINE-P1.md")
air_card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-AIR-COMBAT-BASELINE-P1.md")

metrics = {
  files: SOURCE_FILES.size,
  types: all_source.scan(/^type\s+/).size,
  variants: all_source.scan(/^variant\s+/).size,
  contracts: all_source.scan(/^(?:pure\s+)?contract\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  call_contract_literals: all_source.scan(/call_contract\("([^"]+)"/).flatten,
  match: all_source.scan(/\bmatch\s+/).size,
  filter: all_source.scan(/\bfilter\(/).size,
  concat: all_source.scan(/\bconcat\(/).size
}

manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort
manifest_units = (($manifest || {})["source_units"] || [])
sir_units = (($sir || {})["source_units"] || [])
manifest_entrypoint = ($manifest || {})["entrypoint"] || {}
sir_entrypoint = ($sir || {})["entrypoint"] || {}
variant_decls = (($sir || {})["variant_declarations"] || [])

section("A -- Preconditions")
check("A-01: app directory exists") { APP_DIR.directory? }
check("A-02: rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03: igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format('%02d', idx + 4)}: source exists -- #{name}") { File.exist?(APP_DIR / name) }
end
check("A-10: pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-11: app report exists") { File.exist?(APP_DIR / "report.md") }
check("A-12: lab baseline doc exists") { !lab_doc.empty? }
check("A-13: governance card exists") { !card.empty? }
check("A-14: dev tutorial read surface exists") { !dev_tutorial.empty? }
check("A-15: service-loop spec read surface exists") { !ch13.empty? }
check("A-16: language covenant read surface exists") { !covenant.empty? }

section("B -- Rust compilation via Open3/mktmpdir")
check("B-01: Rust compile returns status ok") { rust1["status"] == "ok" }
check("B-02: Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("B-03: Rust warnings empty") { Array(rust1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("B-#{format('%02d', idx + 4)}: Rust stage #{stage} ok") { (rust1["stages"] || {})[stage] == "ok" }
end
check("B-09: Rust result has 25 contracts") { Array(rust1["contracts"]).size == 25 }
check("B-10: Rust compile wrote fresh igapp one") { File.directory?(rust_out1) }
check("B-11: Rust second compile wrote fresh igapp two") { File.directory?(rust_out2) }
check("B-12: Rust compile stdout parsed as JSON") { !rust1.key?("_parse_error") }

section("C -- Ruby compilation via CompilerOrchestrator")
check("C-01: Ruby wrapper status ok") { ruby1_raw["status"] == "ok" || ruby1["status"] == "ok" }
check("C-02: Ruby inner status ok") { ruby1["status"] == "ok" }
check("C-03: Ruby diagnostics empty") { Array(ruby1["diagnostics"]).empty? }
check("C-04: Ruby warnings empty") { Array(ruby1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("C-#{format('%02d', idx + 5)}: Ruby stage #{stage} ok") { (ruby1["stages"] || {})[stage] == "ok" }
end
check("C-10: Ruby result has 25 contracts") { Array(ruby1["contracts"]).size == 25 }
check("C-11: Ruby compile wrote fresh igapp one") { File.directory?(ruby_out1) }
check("C-12: Ruby second compile wrote fresh igapp two") { File.directory?(ruby_out2) }
check("C-13: Ruby compile stdout parsed as JSON") { !ruby1_raw.key?("_parse_error") }

section("D -- Hash and path sensitivity")
check("D-01: Rust source_hash matches absolute-path baseline") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-02: Ruby source_hash matches absolute-path baseline") { ruby1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-03: Rust source_hash stable across two fresh runs") { rust2["source_hash"] == rust1["source_hash"] }
check("D-04: Ruby source_hash stable across two fresh runs") { ruby2["source_hash"] == ruby1["source_hash"] }
check("D-05: Ruby and Rust source_hash agree") { ruby1["source_hash"] == rust1["source_hash"] }
check("D-06: source_hash is sha256-prefixed") { rust1["source_hash"].to_s.start_with?("sha256:") }
check("D-07: registry records live hash") { registry.include?(EXPECTED_SOURCE_HASH) }
check("D-08: card records live hash") { card.include?(EXPECTED_SOURCE_HASH) }
check("D-09: lab doc records live hash") { lab_doc.include?(EXPECTED_SOURCE_HASH) }
check("D-10: lab doc documents path sensitivity / clean subprocess") { lab_doc.include?("absolute") && lab_doc.include?("Open3") }
check("D-11: runner source uses Open3") { File.read(__FILE__, encoding: "UTF-8").include?("Open3.capture3") }
check("D-12: runner source uses mktmpdir") { File.read(__FILE__, encoding: "UTF-8").include?("Dir.mktmpdir") }

section("E -- Artifacts, manifest, and SIR")
check("E-01: manifest.json exists and parsed") { !$manifest.nil? }
check("E-02: semantic_ir_program.json exists and parsed") { !$sir.nil? }
check("E-03: sourcemap.json exists and parsed") { !$sourcemap.nil? }
check("E-04: compilation_report.json exists and parsed") { !$report.nil? }
check("E-05: diagnostics.json exists") { File.exist?(diagnostics_path) }
check("E-06: manifest source_hash matches result") { ($manifest || {})["source_hash"] == rust1["source_hash"] }
check("E-07: SIR source_hash matches result") { ($sir || {})["source_hash"] == rust1["source_hash"] }
check("E-08: report source_hash matches result") { ($report || {})["source_hash"] == rust1["source_hash"] }
check("E-09: manifest has semantic_ir_ref") { !($manifest || {})["semantic_ir_ref"].to_s.empty? }
check("E-10: manifest has sourcemap_ref") { !($manifest || {})["sourcemap_ref"].to_s.empty? }
check("E-11: manifest contract_index has 25 entries") { (($manifest || {})["contract_index"] || {}).size == 25 }
check("E-12: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }

section("F -- Source units, types, variants, contracts")
check("F-01: manifest has 6 source_units") { manifest_units.size == 6 }
check("F-02: SIR has 6 source_units") { sir_units.size == 6 }
check("F-03: manifest source unit modules match expected") { manifest_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("F-04: SIR source unit modules match expected") { sir_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
EXPECTED_SOURCE_UNITS.each_with_index do |mod, idx|
  check("F-#{format('%02d', idx + 5)}: source unit #{mod} present") { manifest_units.any? { |u| u["module"] == mod } }
end
check("F-11: type declarations count is 7") { metrics[:types] == 7 }
check("F-12: CallRouterTypes manifest types match expected") do
  types_unit = manifest_units.find { |u| u["module"] == "CallRouterTypes" } || {}
  Array(types_unit["types"]).sort == EXPECTED_TYPES
end
check("F-13: 3 variants declared in source") { metrics[:variants] == 3 }
check("F-14: SIR has 3 variant declarations") { variant_decls.size == 3 }
check("F-15: result contract list matches expected set") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
check("F-16: manifest contract list matches expected set") { manifest_contracts == EXPECTED_CONTRACTS }
check("F-17: SIR contract list matches expected set") { sir_contracts == EXPECTED_CONTRACTS }
check("F-18: Ruby contract list matches Rust") { Array(ruby1["contracts"]).sort == Array(rust1["contracts"]).sort }

section("G -- Metrics and Tier-1 dispatch")
check("G-01: exactly 6 source files") { metrics[:files] == 6 }
check("G-02: exactly 7 types") { metrics[:types] == 7 }
check("G-03: exactly 3 variants") { metrics[:variants] == 3 }
check("G-04: exactly 25 contracts") { metrics[:contracts] == 25 }
check("G-05: exactly 30 call_contract sites") { metrics[:call_contract] == 30 }
check("G-06: exactly 11 match sites") { metrics[:match] == 11 }
check("G-07: exactly 1 filter site") { metrics[:filter] == 1 }
check("G-08: exactly 1 concat site") { metrics[:concat] == 1 }
check("G-09: all call_contract sites are string literals") { metrics[:call_contract_literals].size == metrics[:call_contract] }
check("G-10: all call_contract targets start PascalCase") { metrics[:call_contract_literals].all? { |name| name.match?(/\A[A-Z]/) } }
check("G-11: no dynamic call_contract callee syntax") { !all_source.match?(/call_contract\(\s*[a-z_][a-zA-Z0-9_]*\s*,/) }
check("G-12: Dynamic dispatch P2 preserves variable-callee fail-closed policy") do
  dynamic_dispatch_card.include?("PRESERVE fail-closed") && dynamic_dispatch_card.include?("No stringly runtime authority")
end

section("H -- Variant and match positive evidence")
EXPECTED_VARIANTS.each_with_index do |(variant, arms), idx|
  check("H-#{format('%02d', idx + 1)}: #{variant} variant present with expected arms") do
    decl = variant_decls.find { |v| v["name"] == variant } || {}
    Array(decl["arms"]).map { |arm| arm["name"] } == arms
  end
end
check("H-04: Telephony has CallConnected payload fields") do
  telephony = variant_decls.find { |v| v["name"] == "Telephony" } || {}
  cc = Array(telephony["arms"]).find { |arm| arm["name"] == "CallConnected" } || {}
  Array(cc["fields"]).map { |f| f["name"] }.sort == %w[customer_phone direction started_at_min].sort
end
check("H-05: MatchResult Matched carries CallrailCall") do
  match_result = variant_decls.find { |v| v["name"] == "MatchResult" } || {}
  matched = Array(match_result["arms"]).find { |arm| arm["name"] == "Matched" } || {}
  field = Array(matched["fields"]).first || {}
  field["name"] == "call" && field.dig("type", "name") == "CallrailCall"
end
check("H-06: ClassifyTelephony constructs CallConnected/Ringing/NoCall") do
  src = read_source("correlate.ig")
  src.include?("CallConnected {") && src.include?("Ringing { }") && src.include?("NoCall { }")
end
check("H-07: OperatorStep matches Telephony state machine") do
  src = read_source("operator.ig")
  src.include?("match t") && src.include?("CallConnected") && src.include?("Ringing") && src.include?("NoCall")
end
check("H-08: ChannelBehaviorOf matches ChannelFlow policy") do
  src = read_source("operator.ig")
  src.include?("match f") && src.include?("Marketing") && src.include?("CallCenter") && src.include?("Inactive")
end
check("H-09: HandleRingcentral matches MatchResult") do
  src = read_source("service.ig")
  src.include?("match m") && src.include?("Matched") && src.include?("Unmatched")
end
check("H-10: variant + match is documented as positive capability") do
  registry.include?("variant") && registry.include?("state machine") && app_report.include?("variant") && app_report.include?("dual-clean")
end

section("I -- Entry point and run profile pressure")
check("I-01: source has bare entrypoint RunConnectedMatched") { read_source("example.ig").include?("entrypoint RunConnectedMatched") }
check("I-02: Rust manifest entrypoint resolves RunConnectedMatched") do
  manifest_entrypoint["resolved_contract"] == "RunConnectedMatched" && manifest_entrypoint["declared_target"] == "RunConnectedMatched"
end
check("I-03: Rust SIR entrypoint resolves RunConnectedMatched") do
  sir_entrypoint["resolved_contract"] == "RunConnectedMatched" && sir_entrypoint["target"] == "RunConnectedMatched"
end
check("I-04: entrypoint contract artifact path is present") { manifest_entrypoint["contract_path"].to_s.include?("run_connected_matched") }
%w[RunConnectedMatched RunNoCall RunUpsert RunChannel].each_with_index do |name, idx|
  check("I-#{format('%02d', idx + 5)}: scenario contract #{name} exists") { EXPECTED_CONTRACTS.include?(name) }
end
check("I-09: CR-P11 registry route names PROP-029 rich entrypoint") { registry.include?("CR-P11") && registry.include?("PROP-029") }
check("I-10: dev tutorial marks rich entrypoint as not yet dual-clean") do
  dev_tutorial.include?("Rich entrypoint") && dev_tutorial.include?("Only the **bare** `entrypoint C` is implemented")
end
check("I-11: lab doc captures named run-profile pressure") { lab_doc.include?("CR-P11") && lab_doc.include?("RunConnectedMatched") && lab_doc.include?("RunNoCall") }

section("J -- Pressure registry CR-P01..CR-P11")
EXPECTED_PRESSURES.each_with_index do |pid, idx|
  check("J-#{format('%02d', idx + 1)}: registry preserves #{pid}") { registry.include?(pid) }
end
check("J-12: CR-P02 routed to string contains/ends_with") { registry.include?("CR-P02") && registry.include?("contains") && registry.include?("ends_with") }
check("J-13: CR-P03 routed to first/last + Option") { registry.include?("CR-P03") && registry.include?("first") && registry.include?("Option") }
check("J-14: CR-P04 routed to compose/entity") { registry.include?("CR-P04") && registry.include?("LANG-COMPOSE-ENTITY") }
check("J-15: CR-P05 routed to record literal tracks") { registry.include?("CR-P05") && registry.include?("record-literal") }
check("J-16: CR-P06 routed to fold-to-struct") { registry.include?("CR-P06") && registry.include?("LANG-FOLD-STRUCT-ACCUMULATOR") }
check("J-17: CR-P07 keeps dynamic dispatch avoided") { registry.include?("CR-P07") && registry.include?("dynamic vendor/channel dispatch avoided") }
check("J-18: CR-P08 routes DB reads/writes to storage/effect") { registry.include?("CR-P08") && registry.include?("PROP-046") && registry.include?("PROP-035") }
check("J-19: CR-P09 routes clock/freshness behind boundary") { registry.include?("CR-P09") && registry.include?("clock") && registry.include?("no source `now()`") }
check("J-20: CR-P10 routes streams to PROP-023 + ServiceLoop/PROP-037") { registry.include?("CR-P10") && registry.include?("PROP-023") && registry.include?("PROP-037") }
check("J-21: CR-P11 routes named profiles to PROP-029") { registry.include?("CR-P11") && registry.include?("PROP-029") }
check("J-22: report says baseline is positive pressure source, not blocker") { app_report.include?("positive baseline") && app_report.include?("pressure source") }

section("K -- Pure core and closed surfaces")
check("K-01: source has no capability declarations") { !all_source.match?(/^\s*capability\s+/) }
check("K-02: source has no effect declarations") { !all_source.match?(/^\s*effect\s+/) }
check("K-03: source has no observed/effect modifiers") { !all_source.match?(/^\s*(observed|effect|privileged|irreversible)\s+contract\s+/) }
check("K-04: source imports no IO stdlib") { !all_source.include?("stdlib.io") }
check("K-05: source has no DB/SQL/ORM/ActiveRecord code") { !all_source.match?(/\b(SQL|ORM|ActiveRecord|Database)\b/) }
check("K-06: source has no HTTP/Rack/socket server") { !all_source.match?(/\b(HTTP|Rack|Socket|server)\b/) }
check("K-07: source has no now()") { !all_source.include?("now()") }
check("K-08: source has no DateTime") { !all_source.include?("DateTime") }
check("K-09: source has no random/RNG call") { !all_source.match?(/\b(random|rand|RNG)\b/) }
check("K-10: source has no background worker implementation") { !all_source.match?(/\b(Sidekiq|Worker|perform_async)\b/) }
check("K-11: registry non-goals close DB/HTTP/fuzzy/clock/dynamic/fold/entity") { %w[DB HTTP fuzzy clock dynamic fold-to-struct entity].all? { |term| registry.include?(term) } }
check("K-12: card closed surfaces close storage/backend host authority") { card.include?("No DB") && card.include?("No HTTP server") && card.include?("No background worker") }
check("K-13: manifest fragment class is core") { ($manifest || {})["fragment_class"] == "core" }
check("K-14: manifest effects are empty") { Array(($manifest || {})["effects"]).empty? }
check("K-15: manifest capabilities are empty") { Array(($manifest || {})["capabilities"]).empty? }
check("K-16: SIR contracts have empty escape_boundaries") { (($sir || {})["contracts"] || []).all? { |c| Array(c["escape_boundaries"]).empty? } }

section("L -- ServiceLoop, request/reply, and authority routing")
check("L-01: report identifies request-reply per webhook") { app_report.include?("request") && app_report.include?("reply per webhook") }
check("L-02: report identifies standing correlator / worker") { app_report.include?("standing correlator") || app_report.include?("standing matcher") }
check("L-03: report routes standing matcher to ServiceLoop / Progression") { app_report.include?("ServiceLoop") && app_report.include?("Progression") }
check("L-04: report names PROP-037 for service liveness") { app_report.include?("PROP-037") }
check("L-05: report names PROP-023 stream input") { app_report.include?("PROP-023") }
check("L-06: Ch13 says ServiceLoop is proposed/deferred") { ch13.include?("ServiceLoop") && ch13.include?("deferred") }
check("L-07: Ch13 ties service liveness to PROP-037") { ch13.include?("PROP-037") && ch13.include?("service liveness") }
check("L-08: Covenant says loops are managed") { covenant.include?("Postulate 14") && covenant.include?("Loops Are Managed") }
check("L-09: Covenant keeps service-loop liveness through PROP-037") { covenant.include?("Service-loop liveness maps through PROP-037") }
check("L-10: card rejects ad hoc host loop") { card.include?("no host-loop evasion") || card.include?("rather than an ad hoc host loop") }

section("M -- Cross-baseline positioning")
check("M-01: lead_router card is request/reply railway") { lead_card.include?("request/reply") && lead_card.include?("railway") }
check("M-02: air_combat card is tick-loop / ServiceLoop pressure") { air_card.include?("tick") && air_card.include?("ServiceLoop") }
check("M-03: call_router card is two-stream webhook correlation") { card.include?("two-stream webhook correlation") }
check("M-04: call_router report names third SparkCRM companion") { app_report.include?("third SparkCRM companion") }
check("M-05: lab doc classifies positive baseline + pressure source") { lab_doc.include?("positive baseline") && lab_doc.include?("pressure source") }
check("M-06: lab doc states evidence baseline only") { lab_doc.include?("evidence baseline only") }

section("N -- Closure artifacts")
check("N-01: card has closure summary") { card.include?("Closure Summary") && card.include?("CLOSED") }
check("N-02: registry has closure summary") { registry.include?("Baseline Closure") && registry.include?("verify_lab_call_router_baseline_p1.rb") }
check("N-03: lab doc records proof runner path") { lab_doc.include?("verify_lab_call_router_baseline_p1.rb") }
check("N-04: portfolio index has call_router closure row") { portfolio.include?("LAB-CALL-ROUTER-BASELINE-P1 CLOSED") }
check("N-05: proof runner does not use shell pipe") do
  runner = File.read(__FILE__, encoding: "UTF-8")
  pipe_to_head = ["|", "head"].join(" ")
  head_dash = ["head", "-"].join(" ")
  redirect_marker = ["2>", "&1"].join("")
  !runner.include?(pipe_to_head) && !runner.include?(head_dash) && !runner.include?(redirect_marker)
end
check("N-06: card documents Rust stdout timing flake") { card.include?("Rust assembler/stdout timing flake") }
check("N-07: registry documents fd/timing artifact") { registry.include?("fd/timing artifact") }
check("N-08: lab doc documents fd/timing artifact") { lab_doc.include?("fd/timing artifact") }

puts
total = $pass_count + $fail_count
puts "=" * 72
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 72
exit($fail_count.zero? ? 0 : 1)
