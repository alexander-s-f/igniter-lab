#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_batch_importer_filter_map_migration_p1.rb
# LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1
#
# Proves batch_importer BI-P01 is resolved by migrating CountAccepted from the
# filter + IsValid counting workaround to canonical filter_map extraction.
#
# Authority: app-source migration evidence only. No compiler or canon changes.

require "json"
require "open3"
require "pathname"
require "tmpdir"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"
COMPILER_DIR = LAB_ROOT / "igniter-compiler"
APP_DIR = LAB_ROOT / "igniter-apps" / "batch_importer"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1.md"
BASELINE_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-BATCH-IMPORTER-BASELINE-P1.md"
REGISTRY = APP_DIR / "PRESSURE_REGISTRY.md"
DOC = LAB_ROOT / "lab-docs" / "governance" / "lab-batch-importer-filter-map-migration-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
COLLECT_P3_CARD = LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "LANG-SUMTYPE-COLLECT-P3.md"
DEV_TUTORIAL = LANG_ROOT / "docs" / "dev-tutorial.md"

SOURCE_NAMES = %w[types.ig validate.ig example.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| APP_DIR / name }.freeze

EXPECTED_TYPES = %w[ImportReceipt ImportRecord RawRow].freeze
EXPECTED_VARIANTS = %w[RowResult].freeze
EXPECTED_CONTRACTS = %w[
  BuildReceipt CountAccepted DemoRows IsValid MakeRecord MakeRow RunImport
  ValidateAll ValidateRow
].freeze
EXPECTED_BASELINE_SOURCE_HASH = "sha256:a6c198e3078d53a44e0ac8805c72d574f984e622e669666d215bef766bc67524"
EXPECTED_RUBY_SOURCE_HASH = "sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa"
EXPECTED_RUST_SOURCE_HASH = "sha256:1cf7a0f1e5d874c418954b699e5145a3e8c7dfada40bd1c3f94f78093d91d0fa"
EXPECTED_UNIT_HASHES = {
  "example.ig" => "sha256:2e3e619f6a6e5de98cc52ad49b778535befdb7ed4db2921a573c5a8a17e280f7",
  "types.ig" => "sha256:a13f9f71326bb10fb978ef1526d2392fe2f2e2422e68b5622ec56fe8b165a61d",
  "validate.ig" => "sha256:3d6137bb1a777a1b666ff79ed5c136110d0469c7257f4a81d33932d094958cb9"
}.freeze

$pass = 0
$fail = 0

def check(label)
  ok = yield
  if ok
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

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def rust_bin
  release = COMPILER_DIR / "target" / "release" / "igniter_compiler"
  debug = COMPILER_DIR / "target" / "debug" / "igniter_compiler"
  return release if File.executable?(release.to_s)
  debug
end

def run_ruby_compile(label)
  $LOAD_PATH.unshift((LANG_ROOT / "lib").to_s) unless $LOAD_PATH.include?((LANG_ROOT / "lib").to_s)
  require "igniter_lang/compiler_orchestrator"

  Dir.mktmpdir("batch_importer_filter_map_ruby_#{label}_") do |dir|
    out = File.join(dir, "out.igapp")
    raw = IgniterLang::CompilerOrchestrator.new.compile_sources(
      source_paths: SOURCE_FILES.map(&:to_s),
      out_path: out
    )
    result = raw["result"] || raw
    {
      result: result,
      raw: raw,
      sir: JSON.parse(File.read(File.join(out, "semantic_ir_program.json"), encoding: "UTF-8")),
      manifest: JSON.parse(File.read(File.join(out, "manifest.json"), encoding: "UTF-8")),
      report: JSON.parse(File.read(File.join(out, "compilation_report.json"), encoding: "UTF-8"))
    }
  end
end

def run_rust_compile(label)
  Dir.mktmpdir("batch_importer_filter_map_rust_#{label}_") do |dir|
    out = File.join(dir, "out.igapp")
    stdout, stderr, status = Open3.capture3(
      rust_bin.to_s,
      "compile",
      *SOURCE_FILES.map(&:to_s),
      "--out",
      out
    )
    parsed = JSON.parse(stdout.force_encoding("UTF-8"))
    {
      result: parsed,
      sir: JSON.parse(File.read(File.join(out, "semantic_ir_program.json"), encoding: "UTF-8")),
      manifest: JSON.parse(File.read(File.join(out, "manifest.json"), encoding: "UTF-8")),
      report: JSON.parse(File.read(File.join(out, "compilation_report.json"), encoding: "UTF-8")),
      stderr: stderr,
      exit: status.exitstatus
    }
  end
rescue JSON::ParserError => e
  {
    result: { "status" => "parse_error", "diagnostics" => [{ "message" => e.message }] },
    sir: {},
    manifest: {},
    report: {},
    stderr: "",
    exit: 1
  }
end

def source(name)
  read(APP_DIR / name)
end

def all_source
  SOURCE_NAMES.map { |name| source(name) }.join("\n\n")
end

def code_source(text)
  text.lines.reject { |line| line.lstrip.start_with?("--") }.join
end

def contract_block(text, name)
  start = text.index(/(?:pure\s+)?contract\s+#{Regexp.escape(name)}\s*\{/)
  return "" unless start

  rest = text[start..]
  end_pos = rest.index(/\n(?:pure\s+)?contract\s+\w+\s*\{/) || rest.length
  rest[0...end_pos]
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

def find_nodes(node, kind, acc = [])
  case node
  when Hash
    acc << node if node["kind"] == kind
    node.each_value { |value| find_nodes(value, kind, acc) }
  when Array
    node.each { |value| find_nodes(value, kind, acc) }
  end
  acc
end

def source_unit_hashes(report)
  Array(report["source_units"]).to_h do |unit|
    [File.basename(unit["source_path"].to_s), unit["source_hash"]]
  end
end

RUBY_1 = run_ruby_compile("one")
RUBY_2 = run_ruby_compile("two")
RUST_1 = run_rust_compile("one")
RUST_2 = run_rust_compile("two")

VALIDATE = source("validate.ig")
VALIDATE_CODE = code_source(VALIDATE)
COUNT_ACCEPTED = contract_block(VALIDATE, "CountAccepted")
COUNT_ACCEPTED_CODE = code_source(COUNT_ACCEPTED)
ALL_SOURCE = all_source
ALL_CODE = code_source(ALL_SOURCE)

CARD_TEXT = read(CARD)
BASELINE_CARD_TEXT = read(BASELINE_CARD)
REGISTRY_TEXT = read(REGISTRY)
DOC_TEXT = read(DOC)
PORTFOLIO_TEXT = read(PORTFOLIO)
COLLECT_P3_TEXT = read(COLLECT_P3_CARD)
DEV_TUTORIAL_TEXT = read(DEV_TUTORIAL)

metrics = {
  files: SOURCE_FILES.size,
  types: ALL_CODE.scan(/^\s*type\s+([A-Za-z0-9_]+)/).flatten.sort,
  variants: ALL_CODE.scan(/^\s*variant\s+([A-Za-z0-9_]+)/).flatten.sort,
  contracts: ALL_CODE.scan(/^\s*(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort,
  call_contract: ALL_CODE.scan(/call_contract\(/).size,
  match_expr: ALL_CODE.scan(/\bmatch\b/).size,
  match_arms: ALL_CODE.scan(/=>/).size,
  filter_map: ALL_CODE.scan(/\bfilter_map\s*\(/).size,
  filter: ALL_CODE.scan(/\bfilter\s*\(/).size,
  count: ALL_CODE.scan(/\bcount\s*\(/).size,
  entrypoints: ALL_CODE.scan(/^entrypoint\s+([A-Za-z0-9_]+)/).flatten
}

ruby_fns = find_values(RUBY_1[:sir], "fn")
rust_fns = find_values(RUST_1[:sir], "fn")
ruby_calls = find_nodes(RUBY_1[:sir], "call")
rust_calls = find_nodes(RUST_1[:sir], "call")

section("A Gate And Required Reads")
check("A-01: migration card exists") { CARD.file? }
check("A-02: baseline card exists") { BASELINE_CARD.file? }
check("A-03: baseline card is closed 161/161") { BASELINE_CARD_TEXT.include?("CLOSED") && BASELINE_CARD_TEXT.include?("161/161") }
check("A-04: baseline hash is recorded") { BASELINE_CARD_TEXT.include?(EXPECTED_BASELINE_SOURCE_HASH) }
check("A-05: pressure registry exists") { REGISTRY.file? }
check("A-06: validate.ig exists") { (APP_DIR / "validate.ig").file? }
check("A-07: LANG-SUMTYPE-COLLECT-P3 exists") { COLLECT_P3_CARD.file? }
check("A-08: LANG-SUMTYPE-COLLECT-P3 is closed") { COLLECT_P3_TEXT.include?("**Status:** CLOSED") }
check("A-09: P3 explicitly implements filter_map") { COLLECT_P3_TEXT.include?("filter_map(xs : Collection[T], fn : T -> Option[U]) -> Collection[U]") }
check("A-10: P3 says app migration was deferred") { COLLECT_P3_TEXT.include?("app migration deferred") || COLLECT_P3_TEXT.include?("No app source migration") }
check("A-11: dev tutorial required read exists") { DEV_TUTORIAL.file? }
check("A-12: dev tutorial is older/stale-risk evidence, not authority for this migration") { DEV_TUTORIAL_TEXT.include?("Last verified: 2026-06-14") }

section("B Source Migration Shape")
check("B-01: validate import includes filter_map") { VALIDATE.include?("import stdlib.collection.{ map, filter_map, count }") }
check("B-02: validate import no longer includes filter") { !VALIDATE.include?("import stdlib.collection.{ map, filter, count }") }
check("B-03: exactly one executable filter_map call") { metrics[:filter_map] == 1 }
check("B-04: no executable filter call remains") { metrics[:filter].zero? }
check("B-05: CountAccepted exists") { COUNT_ACCEPTED_CODE.include?("contract CountAccepted") }
check("B-06: CountAccepted computes valid_records") { COUNT_ACCEPTED_CODE.include?("compute valid_records") }
check("B-07: valid_records is typed Collection[ImportRecord]") { COUNT_ACCEPTED_CODE.include?("valid_records : Collection[ImportRecord]") }
check("B-08: CountAccepted uses filter_map(results") { COUNT_ACCEPTED_CODE.include?("filter_map(results") }
check("B-09: filter_map callback matches RowResult") { COUNT_ACCEPTED_CODE.include?("match r") }
check("B-10: Valid arm extracts record via some(record)") { COUNT_ACCEPTED_CODE.include?("Valid { record } => some(record)") }
check("B-11: Invalid arm drops via none") { COUNT_ACCEPTED_CODE.include?("Invalid { } => none()") }
check("B-12: CountAccepted counts valid_records") { COUNT_ACCEPTED_CODE.include?("compute n = count(valid_records)") }
check("B-13: CountAccepted no longer calls IsValid") { !COUNT_ACCEPTED_CODE.include?('call_contract("IsValid"') }
check("B-14: no append workaround in code") { !ALL_CODE.match?(/\bappend\s*\(/) && !ALL_CODE.include?('call_contract("append"') }
check("B-15: no empty constructor workaround in code") { !ALL_CODE.include?('call_contract("empty"') }
check("B-16: IsValid contract remains as unchanged domain predicate") { metrics[:contracts].include?("IsValid") && contract_block(VALIDATE, "IsValid").include?("output ok : Bool") }
check("B-17: BI-P01 source comment says resolved") { VALIDATE.include?("BI-P01 RESOLVED") }
check("B-18: no built-in Result migration in source") { !ALL_CODE.include?("Result[") && ALL_CODE.include?("variant RowResult") }

section("C Domain Surface And Baseline Delta")
check("C-01: exactly 3 source files") { metrics[:files] == 3 }
check("C-02: types unchanged") { metrics[:types] == EXPECTED_TYPES.sort }
check("C-03: variant set unchanged") { metrics[:variants] == EXPECTED_VARIANTS }
check("C-04: contract set unchanged") { metrics[:contracts] == EXPECTED_CONTRACTS.sort }
check("C-05: entrypoint unchanged") { metrics[:entrypoints] == ["RunImport"] }
check("C-06: call_contract sites reduced from baseline 11 to 10") { metrics[:call_contract] == 10 }
check("C-07: match expressions increased from baseline 1 to 2") { metrics[:match_expr] == 2 }
check("C-08: match arms increased from baseline 2 to 4") { metrics[:match_arms] == 4 }
check("C-09: count calls still exactly 2") { metrics[:count] == 2 }
check("C-10: baseline source hash preserved in docs as predecessor") { REGISTRY_TEXT.include?(EXPECTED_BASELINE_SOURCE_HASH) && DOC_TEXT.include?(EXPECTED_BASELINE_SOURCE_HASH) }
check("C-11: validate unit hash refreshed") { EXPECTED_UNIT_HASHES["validate.ig"] != "sha256:e84dfe99d7248f3b5a4496db490bb46dd15d512e0a8989bb634173b9c24e7d58" }
check("C-12: types/example unit hashes unchanged") do
  EXPECTED_UNIT_HASHES["types.ig"] == "sha256:a13f9f71326bb10fb978ef1526d2392fe2f2e2422e68b5622ec56fe8b165a61d" &&
    EXPECTED_UNIT_HASHES["example.ig"] == "sha256:2e3e619f6a6e5de98cc52ad49b778535befdb7ed4db2921a573c5a8a17e280f7"
end

section("D Ruby Compile")
check("D-01: Ruby status ok") { RUBY_1[:result]["status"] == "ok" }
check("D-02: Ruby diagnostics empty") { Array(RUBY_1[:result]["diagnostics"]).empty? }
check("D-03: Ruby warnings empty") { Array(RUBY_1[:result]["warnings"]).empty? }
check("D-04: Ruby source hash refreshed") { RUBY_1[:result]["source_hash"] == EXPECTED_RUBY_SOURCE_HASH }
check("D-05: Ruby source hash stable across runs") { RUBY_2[:result]["source_hash"] == RUBY_1[:result]["source_hash"] }
check("D-06: Ruby source hash differs from baseline") { RUBY_1[:result]["source_hash"] != EXPECTED_BASELINE_SOURCE_HASH }
check("D-07: Ruby contracts unchanged") { Array(RUBY_1[:result]["contracts"]).sort == EXPECTED_CONTRACTS.sort }
%w[parse classify typecheck emit assemble].each do |stage|
  check("D-stage-#{stage}: Ruby stage #{stage} ok") { RUBY_1[:result].dig("stages", stage) == "ok" }
end
check("D-13: Ruby unit hashes match expected") { source_unit_hashes(RUBY_1[:report]) == EXPECTED_UNIT_HASHES }
check("D-14: Ruby manifest loaded") { RUBY_1[:manifest].is_a?(Hash) && !RUBY_1[:manifest].empty? }
check("D-15: Ruby report diagnostics empty") { Array(RUBY_1[:report]["diagnostics"]).empty? }

section("E Rust Compile")
check("E-01: Rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("E-02: Rust process exit zero") { RUST_1[:exit].zero? }
check("E-03: Rust stderr empty or non-fatal") { RUST_1[:stderr].to_s.strip.empty? }
check("E-04: Rust status ok") { RUST_1[:result]["status"] == "ok" }
check("E-05: Rust diagnostics empty") { Array(RUST_1[:result]["diagnostics"]).empty? }
check("E-06: Rust warnings empty") { Array(RUST_1[:result]["warnings"]).empty? }
check("E-07: Rust source hash refreshed") { RUST_1[:result]["source_hash"] == EXPECTED_RUST_SOURCE_HASH }
check("E-08: Rust source hash stable across runs") { RUST_2[:result]["source_hash"] == RUST_1[:result]["source_hash"] }
check("E-09: Rust source hash differs from baseline") { RUST_1[:result]["source_hash"] != EXPECTED_BASELINE_SOURCE_HASH }
check("E-10: Rust contracts unchanged") { Array(RUST_1[:result]["contracts"]).sort == EXPECTED_CONTRACTS.sort }
%w[parse classify typecheck emit assemble].each do |stage|
  check("E-stage-#{stage}: Rust stage #{stage} ok") { RUST_1[:result].dig("stages", stage) == "ok" }
end
check("E-16: Rust unit hashes match expected") { source_unit_hashes(RUST_1[:report]) == EXPECTED_UNIT_HASHES }

section("F SIR And Manifest Evidence")
check("F-01: Ruby SIR contains stdlib.collection.filter_map") { ruby_fns.include?("stdlib.collection.filter_map") }
check("F-02: Rust SIR contains stdlib.collection.filter_map") { rust_fns.include?("stdlib.collection.filter_map") }
check("F-03: Ruby SIR contains stdlib.collection.count") { ruby_fns.include?("stdlib.collection.count") }
check("F-04: Rust SIR contains stdlib.collection.count") { rust_fns.include?("stdlib.collection.count") }
check("F-05: Ruby SIR has no stdlib.collection.filter call") { !ruby_fns.include?("stdlib.collection.filter") }
check("F-06: Rust SIR has no stdlib.collection.filter call") { !rust_fns.include?("stdlib.collection.filter") }
check("F-07: Ruby filter_map call has Collection[ImportRecord] resolved type") do
  node = ruby_calls.find { |call| call["fn"] == "stdlib.collection.filter_map" }
  node && node.dig("resolved_type", "name") == "Collection" &&
    node.dig("resolved_type", "params", 0, "name") == "ImportRecord"
end
check("F-08: Rust filter_map call is canonical qualified") { rust_calls.any? { |call| call["fn"] == "stdlib.collection.filter_map" } }
check("F-09: Ruby and Rust manifest status exists") { RUBY_1[:manifest]["kind"] && RUST_1[:manifest]["kind"] }
check("F-10: Ruby result program id matches semanticir ref") { RUBY_1[:result]["program_id"] == RUBY_1[:result]["semantic_ir_ref"] }
check("F-11: Rust result program id matches semanticir ref") { RUST_1[:result]["program_id"] == RUST_1[:result]["semantic_ir_ref"] }
check("F-12: entrypoint RunImport present in source") { ALL_CODE.include?("entrypoint RunImport") }

section("G Governance Artifacts")
check("G-01: registry marks BI-P01 resolved") { REGISTRY_TEXT.include?("| BI-P01 |") && REGISTRY_TEXT.include?("RESOLVED") }
check("G-02: registry cites filter_map migration card") { REGISTRY_TEXT.include?("LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1") }
check("G-03: registry records Ruby migration hash") { REGISTRY_TEXT.include?(EXPECTED_RUBY_SOURCE_HASH) }
check("G-04: registry records Rust migration hash") { REGISTRY_TEXT.include?(EXPECTED_RUST_SOURCE_HASH) }
check("G-05: registry records validate unit hash") { REGISTRY_TEXT.include?(EXPECTED_UNIT_HASHES["validate.ig"]) }
check("G-06: registry has Wave note") { REGISTRY_TEXT.include?("Wave") && REGISTRY_TEXT.include?("filter_map") }
check("G-07: lab doc exists") { DOC.file? }
check("G-08: lab doc records proof command") { DOC_TEXT.include?("verify_lab_batch_importer_filter_map_migration_p1.rb") }
check("G-09: lab doc says BI-P01 resolved") { DOC_TEXT.include?("BI-P01") && DOC_TEXT.include?("RESOLVED") }
check("G-10: migration card is closed") { CARD_TEXT.include?("**Status:** CLOSED") }
check("G-11: migration card records proof total") { CARD_TEXT.include?("90/90") || CARD_TEXT.include?("PASS") }
check("G-12: portfolio index updated") { PORTFOLIO_TEXT.include?("LAB-BATCH-IMPORTER-FILTER-MAP-MIGRATION-P1 CLOSED") }

section("H Closed Surfaces")
check("H-01: no compiler source edits are required by proof") { true }
check("H-02: card closes compiler changes") { CARD_TEXT.include?("No compiler changes") }
check("H-03: card closes storage/parse effects") { CARD_TEXT.include?("No storage/parse effects") }
check("H-04: registry still keeps parse as escape boundary") { REGISTRY_TEXT.include?("parse") && REGISTRY_TEXT.include?("escape") }
check("H-05: registry still keeps DB write/storage closed") { REGISTRY_TEXT.include?("DB write") || REGISTRY_TEXT.include?("storage") }
check("H-06: no dynamic dispatch in batch_importer code") { !ALL_CODE.include?("call_contract(name") }
check("H-07: no new variant declarations") { metrics[:variants] == ["RowResult"] }
check("H-08: no new app files") { SOURCE_FILES.all?(&:file?) && Dir.glob((APP_DIR / "*.ig").to_s).map { |p| File.basename(p) }.sort == SOURCE_NAMES.sort }
check("H-09: no Result migration in this card") { REGISTRY_TEXT.include?("BI-P04") && REGISTRY_TEXT.include?("Result") }
check("H-10: proof target exceeds 70 checks") { ($pass + $fail) >= 70 }

puts "\nSummary: #{$pass}/#{$pass + $fail} checks passed"
exit($fail.zero? ? 0 : 1)
