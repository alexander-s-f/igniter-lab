#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_batch_importer_baseline_p1.rb
# LAB-BATCH-IMPORTER-BASELINE-P1
#
# Freeze batch_importer as a positive dual-toolchain baseline and pressure
# source for partial-success import receipts.
#
# Authority: lab evidence only. No app source edits and no canon authority.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"
COMPILER_DIR = LAB_ROOT / "igniter-compiler"
APP_DIR = LAB_ROOT / "igniter-apps" / "batch_importer"
CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-BATCH-IMPORTER-BASELINE-P1.md"
REGISTRY = APP_DIR / "PRESSURE_REGISTRY.md"

SUMTYPE_P3_CARD = LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-SUMTYPE-CONSTRUCT-MATCH-P3.md"
FIRST_LAST_P2_CARD = LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-STDLIB-COLLECTION-FIRST-LAST-P2.md"
RESULT_BIND_P2_CARD = LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-STDLIB-RESULT-BIND-P2.md"

SOURCE_NAMES = %w[types.ig validate.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| APP_DIR / name }.freeze

EXPECTED_TYPES = %w[ImportReceipt ImportRecord RawRow].freeze
EXPECTED_VARIANTS = %w[RowResult].freeze
EXPECTED_ARMS = %w[Invalid Valid].freeze
EXPECTED_CONTRACTS = %w[
  BuildReceipt CountAccepted DemoRows IsValid MakeRecord MakeRow RunImport
  ValidateAll ValidateRow
].freeze
EXPECTED_SOURCE_HASH = "sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524"
EXPECTED_UNIT_HASHES = {
  "example.ig" => "sha256:2e3e619f6a6e5de98cc52ad49b778535befdb7ed4db2921a573c5a8a17e280f7",
  "types.ig" => "sha256:a13f9f71326bb10fb978ef1526d2392fe2f2e2422e68b5622ec56fe8b165a61d",
  "validate.ig" => "sha256:e84dfe99d7248f3b5a4496db490bb46dd15d512e0a8989bb634173b9c24e7d58"
}.freeze

$pass = 0
$fail = 0

def check(label)
  result = yield
  if result
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n=== #{title} ==="
end

def rust_bin
  debug = COMPILER_DIR / "target" / "debug" / "igniter_compiler"
  release = COMPILER_DIR / "target" / "release" / "igniter_compiler"
  return debug if File.executable?(debug.to_s)
  release
end

def run_rust_compile(label)
  Dir.mktmpdir("batch_importer_rust_#{label}_") do |dir|
    out = File.join(dir, "out.igapp")
    stdout, stderr, status = Open3.capture3(
      rust_bin.to_s,
      "compile",
      *SOURCE_FILES.map(&:to_s),
      "--out",
      out
    )
    parsed = JSON.parse(stdout.force_encoding("UTF-8"))
    sir = JSON.parse(File.read(File.join(out, "semantic_ir_program.json"), encoding: "UTF-8"))
    manifest = JSON.parse(File.read(File.join(out, "manifest.json"), encoding: "UTF-8"))
    report = JSON.parse(File.read(File.join(out, "compilation_report.json"), encoding: "UTF-8"))
    return { result: parsed, sir: sir, manifest: manifest, report: report, out: out, stderr: stderr, exit: status.exitstatus }
  end
rescue JSON::ParserError => e
  { result: { "status" => "parse_error", "diagnostics" => [{ "message" => e.message }] }, sir: {}, manifest: {}, report: {}, out: nil, stderr: "", exit: 1 }
end

def run_ruby_compile(label)
  $LOAD_PATH.unshift((LANG_ROOT / "lib").to_s) unless $LOAD_PATH.include?((LANG_ROOT / "lib").to_s)
  require "igniter_lang/compiler_orchestrator"

  Dir.mktmpdir("batch_importer_ruby_#{label}_") do |dir|
    out = File.join(dir, "out.igapp")
    raw = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: SOURCE_FILES.map(&:to_s),
      out_path: out
    )
    result = raw["result"] || raw
    sir = JSON.parse(File.read(File.join(out, "semantic_ir_program.json"), encoding: "UTF-8"))
    manifest = JSON.parse(File.read(File.join(out, "manifest.json"), encoding: "UTF-8"))
    report = JSON.parse(File.read(File.join(out, "compilation_report.json"), encoding: "UTF-8"))
    return { result: result, raw: raw, sir: sir, manifest: manifest, report: report, out: out }
  end
end

def source(name)
  File.read(APP_DIR / name, encoding: "UTF-8")
end

def all_source
  @all_source ||= SOURCE_NAMES.map { |name| source(name) }.join("\n\n")
end

def find_values(node, key)
  values = []
  case node
  when Hash
    values << node[key] if node.key?(key)
    node.each_value { |value| values.concat(find_values(value, key)) }
  when Array
    node.each { |value| values.concat(find_values(value, key)) }
  end
  values
end

def count_kind(node, kind)
  case node
  when Hash
    (node["kind"] == kind ? 1 : 0) + node.each_value.sum { |value| count_kind(value, kind) }
  when Array
    node.sum { |value| count_kind(value, kind) }
  else
    0
  end
end

def deep_include?(node, text)
  case node
  when Hash
    node.any? { |key, value| key.to_s.include?(text) || deep_include?(value, text) }
  when Array
    node.any? { |value| deep_include?(value, text) }
  else
    node.to_s.include?(text)
  end
end

def source_unit_hashes(report)
  Array(report["source_units"]).to_h do |unit|
    [File.basename(unit["source_path"].to_s), unit["source_hash"]]
  end
end

def contracts_from(result)
  Array(result["contracts"]).sort
end

RUBY_1 = run_ruby_compile("one")
RUBY_2 = run_ruby_compile("two")
RUST_1 = run_rust_compile("one")
RUST_2 = run_rust_compile("two")

REGISTRY_TEXT = File.read(REGISTRY, encoding: "UTF-8")
CARD_TEXT = File.read(CARD, encoding: "UTF-8")
SUMTYPE_P3_TEXT = File.read(SUMTYPE_P3_CARD, encoding: "UTF-8")
FIRST_LAST_P2_TEXT = File.read(FIRST_LAST_P2_CARD, encoding: "UTF-8")
RESULT_BIND_P2_TEXT = File.read(RESULT_BIND_P2_CARD, encoding: "UTF-8")

SIR_FNS = find_values(RUST_1[:sir], "fn")
RUST_RESULT = RUST_1[:result]
RUBY_RESULT = RUBY_1[:result]
RUST_LIVENESS = RUST_RESULT["liveness_instrumentation"] || {}
RUST_COUNTERS = RUST_LIVENESS["counters"] || {}

metrics = {
  files: SOURCE_FILES.size,
  types: all_source.scan(/^\s*type\s+([A-Za-z0-9_]+)/).flatten.sort,
  variants: all_source.scan(/^\s*variant\s+([A-Za-z0-9_]+)/).flatten.sort,
  arms: source("types.ig").scan(/^\s*(Valid|Invalid)\s*\{/).flatten.sort,
  contracts: all_source.scan(/^\s*(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort,
  call_contract: all_source.scan(/call_contract\(/).size,
  match_expr: all_source.scan(/compute\s+\w+\s*=\s*match\b/).size,
  match_arms: all_source.scan(/=>/).size,
  entrypoints: all_source.scan(/^entrypoint\s+([A-Za-z0-9_]+)/).flatten,
  executable_map: source("validate.ig").scan(/compute\s+results\s*=\s*map\(/).size,
  executable_filter: source("validate.ig").scan(/compute\s+valids\s*=\s*filter\(/).size,
  executable_count: source("validate.ig").scan(/compute\s+\w+\s*=\s*count\(/).size
}

CODE_SOURCE = all_source.lines.reject { |line| line.lstrip.start_with?("--") }.join

section("A Preconditions")
check("A-01: batch_importer app directory exists") { APP_DIR.directory? }
check("A-02: pressure registry exists") { REGISTRY.file? }
check("A-03: card exists") { CARD.file? }
check("A-04: Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-05: igniter-lang lib directory exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, index|
  check("A-#{format('%02d', index + 6)}: source file exists - #{name}") { (APP_DIR / name).file? }
end
check("A-09: Sumtype P3 required-read card exists") { SUMTYPE_P3_CARD.file? }
check("A-10: first/last P2 required-read card exists") { FIRST_LAST_P2_CARD.file? }
check("A-11: Result bind P2 required-read card exists") { RESULT_BIND_P2_CARD.file? }
check("A-12: card authority is evidence baseline only") { CARD_TEXT.include?("evidence baseline only") }

section("B Source Shape")
check("B-01: exactly 3 source files") { metrics[:files] == 3 }
check("B-02: source files are types/validate/example") { SOURCE_NAMES == %w[types.ig validate.ig example.ig] }
check("B-03: exactly 3 type declarations") { metrics[:types] == EXPECTED_TYPES.sort }
EXPECTED_TYPES.each { |type| check("B-type-#{type}: type present") { metrics[:types].include?(type) } }
check("B-07: exactly 1 variant declaration") { metrics[:variants] == EXPECTED_VARIANTS }
check("B-08: RowResult has exactly Valid and Invalid arms") { metrics[:arms] == EXPECTED_ARMS.sort }
check("B-09: exactly 9 contracts") { metrics[:contracts] == EXPECTED_CONTRACTS.sort }
EXPECTED_CONTRACTS.each { |contract| check("B-contract-#{contract}: contract present") { metrics[:contracts].include?(contract) } }
check("B-19: exactly 11 call_contract sites") { metrics[:call_contract] == 11 }
check("B-20: exactly 1 source match expression") { metrics[:match_expr] == 1 }
check("B-21: match expression has exactly 2 arms") { metrics[:match_arms] == 2 }
check("B-22: entrypoint is RunImport") { metrics[:entrypoints] == ["RunImport"] }
check("B-23: ValidateAll has one executable map") { metrics[:executable_map] == 1 }
check("B-24: CountAccepted has one executable filter") { metrics[:executable_filter] == 1 }
check("B-25: validate.ig has two executable count calls") { metrics[:executable_count] == 2 }

section("C Required Reads And Routing")
check("C-01: Sumtype P3 is closed implemented") { SUMTYPE_P3_TEXT.include?("**Status:** CLOSED") && SUMTYPE_P3_TEXT.include?("IMPLEMENTED") }
check("C-02: Sumtype P3 says no app migration") { SUMTYPE_P3_TEXT.include?("No app migration") }
check("C-03: Sumtype P3 owns Option/Result construction and match") { SUMTYPE_P3_TEXT.include?("Option[T]") && SUMTYPE_P3_TEXT.include?("Result[T,E]") }
check("C-04: first/last P2 is closed proved") { FIRST_LAST_P2_TEXT.include?("CLOSED") && FIRST_LAST_P2_TEXT.include?("62/62") }
check("C-05: first/last P2 keeps matchability closed") { FIRST_LAST_P2_TEXT.include?("Option/Result matchability") || FIRST_LAST_P2_TEXT.include?("match first") }
check("C-06: Result bind P2 is closed plan proved") { RESULT_BIND_P2_TEXT.include?("PLAN PROVED 66/66") }
check("C-07: Result bind P2 implementation is gated on Sumtype P3") { RESULT_BIND_P2_TEXT.include?("Implementation gated on Sumtype P3") }
check("C-08: registry routes BI-P01 to sumtype/collect") { REGISTRY_TEXT.include?("BI-P01") && REGISTRY_TEXT.include?("collect") }
check("C-09: registry routes BI-P07 through first/last Option") { REGISTRY_TEXT.include?("BI-P07") && REGISTRY_TEXT.include?("first") && REGISTRY_TEXT.include?("Option") }
check("C-10: card says P3 landing must not migrate app") { CARD_TEXT.include?("not to\nmigrate the app") || CARD_TEXT.include?("not to migrate the app") }

section("D Ruby Compile")
check("D-01: Ruby status ok") { RUBY_RESULT["status"] == "ok" }
check("D-02: Ruby diagnostics empty") { Array(RUBY_RESULT["diagnostics"]).empty? }
check("D-03: Ruby warnings empty") { Array(RUBY_RESULT["warnings"]).empty? }
check("D-04: Ruby source hash matches expected") { RUBY_RESULT["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-05: Ruby source hash stable across two runs") { RUBY_2[:result]["source_hash"] == RUBY_RESULT["source_hash"] }
check("D-06: Ruby contract list matches expected") { contracts_from(RUBY_RESULT) == EXPECTED_CONTRACTS.sort }
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage-#{stage}: Ruby stage #{stage} ok") { (RUBY_RESULT["stages"] || {})[stage] == "ok" }
end
check("D-12: Ruby manifest loaded") { RUBY_1[:manifest].is_a?(Hash) && !RUBY_1[:manifest].empty? }
check("D-13: Ruby SIR loaded") { RUBY_1[:sir].is_a?(Hash) && !RUBY_1[:sir].empty? }
check("D-14: Ruby source-unit hashes match expected") { source_unit_hashes(RUBY_1[:report]) == EXPECTED_UNIT_HASHES }

section("E Rust Compile")
check("E-01: Rust process exit is zero") { RUST_1[:exit] == 0 }
check("E-02: Rust stderr empty or non-fatal") { RUST_1[:stderr].to_s.strip.empty? }
check("E-03: Rust status ok") { RUST_RESULT["status"] == "ok" }
check("E-04: Rust diagnostics empty") { Array(RUST_RESULT["diagnostics"]).empty? }
check("E-05: Rust warnings empty") { Array(RUST_RESULT["warnings"]).empty? }
check("E-06: Rust source hash matches expected") { RUST_RESULT["source_hash"] == EXPECTED_SOURCE_HASH }
check("E-07: Rust source hash stable across two runs") { RUST_2[:result]["source_hash"] == RUST_RESULT["source_hash"] }
check("E-08: Rust contract list matches expected") { contracts_from(RUST_RESULT) == EXPECTED_CONTRACTS.sort }
%w[parse classify typecheck emit assemble].each do |stage|
  check("E-stage-#{stage}: Rust stage #{stage} ok") { (RUST_RESULT["stages"] || {})[stage] == "ok" }
end
check("E-14: Rust manifest loaded") { RUST_1[:manifest].is_a?(Hash) && !RUST_1[:manifest].empty? }
check("E-15: Rust SIR loaded") { RUST_1[:sir].is_a?(Hash) && !RUST_1[:sir].empty? }
check("E-16: Rust source-unit hashes match expected") { source_unit_hashes(RUST_1[:report]) == EXPECTED_UNIT_HASHES }
check("E-17: Ruby and Rust source hashes agree") { RUBY_RESULT["source_hash"] == RUST_RESULT["source_hash"] }

section("F SemanticIR And Manifest")
check("F-01: SIR contains 9 contracts") { Array(RUST_1[:sir]["contracts"]).size == 9 }
check("F-02: SIR contains RowResult variant declaration") { deep_include?(RUST_1[:sir], "RowResult") }
check("F-03: SIR contains Valid arm") { deep_include?(RUST_1[:sir], "Valid") }
check("F-04: SIR contains Invalid arm") { deep_include?(RUST_1[:sir], "Invalid") }
check("F-05: SIR contains entrypoint RunImport") { deep_include?(RUST_1[:sir], "RunImport") }
check("F-06: SIR contains stdlib.collection.map") { SIR_FNS.include?("stdlib.collection.map") }
check("F-07: SIR contains stdlib.collection.filter") { SIR_FNS.include?("stdlib.collection.filter") }
check("F-08: SIR contains stdlib.collection.count") { SIR_FNS.count("stdlib.collection.count") >= 2 }
check("F-09: SIR contains match_node") { count_kind(RUST_1[:sir], "match_node") == 1 }
check("F-10: SIR contains three variant constructs") { count_kind(RUST_1[:sir], "variant_construct") == 3 }
check("F-11: SIR contains no sealed built-in sumtype marker") { !deep_include?(RUST_1[:sir], "sealed") }
check("F-12: manifest names RunImport") { deep_include?(RUST_1[:manifest], "RunImport") }
check("F-13: manifest names all expected contracts") { EXPECTED_CONTRACTS.all? { |c| deep_include?(RUST_1[:manifest], c) } }
check("F-14: compilation report has 3 source units") { Array(RUST_1[:report]["source_units"]).size == 3 }
check("F-15: report source unit modules are stable") do
  Array(RUST_1[:report]["source_units"]).map { |u| u["module"] }.sort == %w[BatchImporterExample BatchImporterTypes BatchImporterValidate]
end

section("G Positive Partial-Success Pattern")
check("G-01: RawRow amount is Integer boundary input") { source("types.ig").include?("amount  : Integer") }
check("G-02: ImportRecord amount remains Integer") { source("types.ig").include?("amount : Integer") }
check("G-03: RowResult Valid carries ImportRecord") { source("types.ig").include?("Valid   { record : ImportRecord }") }
check("G-04: RowResult Invalid carries row_id and message") { source("types.ig").include?("Invalid { row_id : Integer, message : String }") }
check("G-05: ValidateRow rejects non-positive amount") { source("validate.ig").include?("raw.amount <= 0") }
check("G-06: ValidateRow rejects missing email") { source("validate.ig").include?('raw.email == ""') }
check("G-07: ValidateAll maps rows to ValidateRow") { source("validate.ig").include?('map(rows, r -> call_contract("ValidateRow", r))') }
check("G-08: IsValid match returns true for Valid") { source("validate.ig").include?("Valid {}   => true") }
check("G-09: IsValid match returns false for Invalid") { source("validate.ig").include?("Invalid {} => false") }
check("G-10: CountAccepted filters by IsValid") { source("validate.ig").include?('filter(results, r -> call_contract("IsValid", r))') }
check("G-11: BuildReceipt computes rejected as total - accepted") { source("validate.ig").include?("compute rejected = total - accepted") }
check("G-12: DemoRows encodes total 4 accepted 2 rejected 2") { source("example.ig").include?("total = 4, accepted = 2, rejected = 2") }

section("H Pressure Registry")
%w[BI-P01 BI-P02 BI-P03 BI-P04 BI-P05 BI-P06 BI-P07].each do |id|
  check("H-#{id}: registry preserves #{id}") { REGISTRY_TEXT.include?(id) }
end
check("H-08: BI-P01 remains ACTIVE primary") { REGISTRY_TEXT.include?("BI-P01") && REGISTRY_TEXT.include?("ACTIVE") && REGISTRY_TEXT.include?("primary") }
check("H-09: BI-P01 says typed extraction is blocked") { REGISTRY_TEXT.include?("cannot extract") || REGISTRY_TEXT.include?("extraction is the gap") }
check("H-10: BI-P04 says Result is modeled as a user variant") { REGISTRY_TEXT.include?("Result modeled as a user variant") }
check("H-11: capability discovery names map/filter/count dual-clean") { REGISTRY_TEXT.include?("map") && REGISTRY_TEXT.include?("filter") && REGISTRY_TEXT.include?("count") && REGISTRY_TEXT.include?("dual-clean") }
check("H-12: safety interpretation denies CSV/DB/extraction claims") { REGISTRY_TEXT.include?("does NOT claim") && REGISTRY_TEXT.include?("CSV") && REGISTRY_TEXT.include?("DB write") && REGISTRY_TEXT.include?("typed extraction") }
check("H-13: registry source hash updated to live expected value") { REGISTRY_TEXT.include?(EXPECTED_SOURCE_HASH) }

section("I Closed Surfaces")
closed_terms = [
  /\bBytes\b/, /\bParseCsvFile\b/, /\bCSV\s*parse\b/i, /\bString.?to.?Integer\b/i,
  /\bdb_write_batch\b/, /^\s*capability\s+/, /^\s*effect\s+/, /\bSQL\b/,
  /\bActiveRecord\b/, /\bHTTP\b/, /\bRack\b/, /\bok\(/, /\berr\(/,
  /\bsome\(/, /\bnone\(/
]
closed_terms.each_with_index do |pattern, index|
  check("I-#{format('%02d', index + 1)}: app source avoids #{pattern.inspect}") do
    !CODE_SOURCE.match?(pattern)
  end
end
check("I-16: app source does not import stdlib.result") { !CODE_SOURCE.include?("stdlib.result") }
check("I-17: app source does not call first or last") { !CODE_SOURCE.match?(/\b(first|last)\(/) }
check("I-18: app source does not define storage capability") { !CODE_SOURCE.include?("StorageCapability") }
check("I-19: app source keeps parsing as escape-boundary prose only") { all_source.include?("parsing is escape") }

section("J Liveness And Determinism")
check("J-01: Rust liveness object present") { RUST_LIVENESS["kind"] == "liveness_instrumentation" }
check("J-02: Rust liveness breaches empty") { Array(RUST_LIVENESS["breaches"]).empty? }
check("J-03: Rust tc infer depth below 1000") { RUST_COUNTERS.fetch("typechecker.infer_expr.max_depth", 1001).to_i < 1000 }
check("J-04: Rust fr walk depth below 1000") { RUST_COUNTERS.fetch("form_resolver.walk_expr.max_depth", 1001).to_i < 1000 }
check("J-05: Rust import steps below 100") { RUST_COUNTERS.fetch("parser.parse_import.max_steps", 101).to_i < 100 }
check("J-06: Rust source hash deterministic run 1/2") { RUST_1[:result]["source_hash"] == RUST_2[:result]["source_hash"] }
check("J-07: Ruby source hash deterministic run 1/2") { RUBY_1[:result]["source_hash"] == RUBY_2[:result]["source_hash"] }
check("J-08: Rust and Ruby program ids agree") { RUST_1[:result]["program_id"] == RUBY_1[:result]["program_id"] }
check("J-09: Rust and Ruby semantic refs agree") { RUST_1[:result]["semantic_ir_ref"] == RUBY_1[:result]["semantic_ir_ref"] }
check("J-10: Rust and Ruby compilation report refs agree") { RUST_1[:result]["compilation_report_ref"] == RUBY_1[:result]["compilation_report_ref"] }

section("K Source Integrity")
check("K-01: types.ig unit hash unchanged") { source_unit_hashes(RUST_1[:report])["types.ig"] == EXPECTED_UNIT_HASHES["types.ig"] }
check("K-02: validate.ig unit hash unchanged") { source_unit_hashes(RUST_1[:report])["validate.ig"] == EXPECTED_UNIT_HASHES["validate.ig"] }
check("K-03: example.ig unit hash unchanged") { source_unit_hashes(RUST_1[:report])["example.ig"] == EXPECTED_UNIT_HASHES["example.ig"] }
check("K-04: source file order is proof runner only, not app metadata") { SOURCE_NAMES == %w[types.ig validate.ig example.ig] }
check("K-05: registry says no app mutation") { REGISTRY_TEXT.include?("No app mutation") || REGISTRY_TEXT.include?("No app source edits") }
check("K-06: card keeps no app source edits in acceptance") { CARD_TEXT.include?("No app source edits") }
check("K-07: proof evidence uses Open3/mktmpdir route") { File.read(__FILE__, encoding: "UTF-8").include?("Open3.capture3") && File.read(__FILE__, encoding: "UTF-8").include?("Dir.mktmpdir") }
check("K-08: no implementation claim in this card") { CARD_TEXT.include?("no implementation") || CARD_TEXT.include?("no app migration") }

section("L Baseline Verdict")
check("L-01: Ruby and Rust are dual-clean") { RUBY_RESULT["status"] == "ok" && RUST_RESULT["status"] == "ok" }
check("L-02: zero diagnostics both toolchains") { Array(RUBY_RESULT["diagnostics"]).empty? && Array(RUST_RESULT["diagnostics"]).empty? }
check("L-03: source hash is frozen") { RUST_RESULT["source_hash"] == EXPECTED_SOURCE_HASH }
check("L-04: BI-P01 typed extraction remains missing until collect/partition lands") do
  SUMTYPE_P3_TEXT.include?("**Status:** CLOSED") &&
    REGISTRY_TEXT.include?("collect/partition") &&
    !CODE_SOURCE.match?(/\b(collect|partition)\(/)
end
check("L-05: baseline avoids built-in Result migration") { !CODE_SOURCE.include?("Result[") && all_source.include?("variant RowResult") }
check("L-06: baseline preserves pure receipt core") { source("validate.ig").include?("BuildReceipt") && source("example.ig").include?("RunImport") }

puts "\nSummary: #{$pass}/#{$pass + $fail} checks passed"
exit($fail.zero? ? 0 : 1)
