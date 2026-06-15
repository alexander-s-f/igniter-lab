#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_audit_ledger_baseline_p1.rb
# LAB-AUDIT-LEDGER-BASELINE-P1 -- freeze audit_ledger as a positive
# dual-toolchain temporal/audit baseline and pressure source.
#
# Authority: evidence baseline only. No compiler, stdlib, runtime, storage,
# clock, Decimal/Money, BiHistory, as_of, or app source implementation.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WS_ROOT = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR = LAB_ROOT / "igniter-apps" / "audit_ledger"
RUST_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_BIN_FALLBACK = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

SOURCE_NAMES = %w[
  types.ig ledger.ig correct.ig example.ig
].freeze
SOURCE_FILES = SOURCE_NAMES.map { |name| (APP_DIR / name).to_s }.freeze

EXPECTED_SOURCE_HASH = "sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022"
EXPECTED_SOURCE_UNITS = %w[
  AuditLedgerCore AuditLedgerCorrect AuditLedgerExample AuditLedgerTypes
].sort.freeze
EXPECTED_TYPES = %w[
  AsOfQuery BalanceReconstruction CorrectionReceipt LedgerEntry
].sort.freeze
EXPECTED_CONTRACTS = %w[
  BalanceAsOfDay3 BalanceAsOfDay5 BuildCorrectionEntry BuildCorrectionReceipt
  CorrectionCount CorrectionTrail DemoLedger MakeEntry MakeQuery ReconstructBalance
  ShowCorrection SumVisible VisibleAsOf
].sort.freeze
EXPECTED_PRESSURES = (1..9).map { |n| "AL-P#{format('%02d', n)}" }.freeze

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

def code_source
  @code_source ||= all_source.lines.reject { |line| line.lstrip.start_with?("--") }.join
end

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_BIN_FALLBACK
end

def normalize_compile_result(result)
  result["result"] || result
end

TMP = Dir.mktmpdir("audit_ledger_baseline_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def run_rust_compile(label)
  out = File.join(TMP, "audit_ledger_rust_#{label}.igapp")
  stdout, stderr, status = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
  parsed = JSON.parse(stdout.force_encoding("UTF-8")) rescue {
    "_parse_error" => stdout,
    "_stderr" => stderr,
    "_status" => status.exitstatus
  }
  [parsed, out]
end

def run_ruby_compile(label)
  out = File.join(TMP, "audit_ledger_ruby_#{label}.igapp")
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
        "igapp_path" => inner["igapp_path"],
        "report" => inner["report"]
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
card = read_path(LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-AUDIT-LEDGER-BASELINE-P1.md")
lab_doc = read_path(LAB_ROOT / "lab-docs" / "governance" / "lab-audit-ledger-baseline-v0.md")
portfolio = read_path(LAB_ROOT / ".agents" / "portfolio-index.md")
temporal_gov = read_path(WS_ROOT / "igniter-gov" / "portfolio" / "governance" / "2026-06-14-lang-temporal-data-patterns-p2-v0.md")
fold_p1_gov = read_path(WS_ROOT / "igniter-gov" / "portfolio" / "governance" / "2026-06-14-lang-fold-struct-accumulator-p1-v0.md")
fold_p2_gov = read_path(WS_ROOT / "igniter-gov" / "portfolio" / "governance" / "2026-06-14-lang-fold-struct-accumulator-p2-v0.md")
fold_p3_gov = read_path(WS_ROOT / "igniter-gov" / "portfolio" / "governance" / "2026-06-14-lang-fold-struct-accumulator-p3-v0.md")

metrics = {
  files: SOURCE_FILES.size,
  types: all_source.scan(/^type\s+/).size,
  contracts: all_source.scan(/^(?:pure\s+)?contract\s+/).size,
  pure_contracts: all_source.scan(/^pure\s+contract\s+/).size,
  call_contract: all_source.scan(/call_contract\(/).size,
  call_contract_literals: all_source.scan(/call_contract\("([^"]+)"/).flatten,
  fold: all_source.scan(/\bfold\(/).size,
  filter: all_source.scan(/\bfilter\(/).size,
  count: all_source.scan(/\bcount\(/).size,
  map: all_source.scan(/\bmap\(/).size,
  concat: all_source.scan(/\bconcat\(/).size,
  variants: all_source.scan(/^variant\s+/).size,
  record_literals: all_source.scan(/=\s*\{/).size
}

manifest_contracts = (($manifest || {})["contracts"] || []).sort
sir_contracts = (($sir || {})["contracts"] || []).map { |c| c["contract_name"] || c["name"] }.compact.sort
manifest_units = (($manifest || {})["source_units"] || [])
sir_units = (($sir || {})["source_units"] || [])
manifest_entrypoint = ($manifest || {})["entrypoint"] || {}
sir_entrypoint = ($sir || {})["entrypoint"] || {}
found_types = all_source.scan(/^type\s+([A-Za-z0-9_]+)/).flatten.sort
found_contracts = all_source.scan(/^(?:pure\s+)?contract\s+([A-Za-z0-9_]+)/).flatten.sort

section("A -- Preconditions")
check("A-01: app directory exists") { APP_DIR.directory? }
check("A-02: rust compiler binary exists") { File.executable?(rust_bin.to_s) }
check("A-03: igniter-lang lib exists") { (LANG_ROOT / "lib" / "igniter_lang").directory? }
SOURCE_NAMES.each_with_index do |name, idx|
  check("A-#{format('%02d', idx + 4)}: source exists -- #{name}") { File.exist?(APP_DIR / name) }
end
check("A-08: pressure registry exists") { File.exist?(APP_DIR / "PRESSURE_REGISTRY.md") }
check("A-09: app report exists") { File.exist?(APP_DIR / "report.md") }
check("A-10: governance card exists") { !card.empty? }
check("A-11: lab baseline doc exists") { !lab_doc.empty? }
check("A-12: lab portfolio index exists") { !portfolio.empty? }
check("A-13: temporal data governance checkpoint readable") { !temporal_gov.empty? }
check("A-14: fold struct governance checkpoints readable") { [fold_p1_gov, fold_p2_gov, fold_p3_gov].all? { |doc| !doc.empty? } }

section("B -- Rust compilation via Open3/mktmpdir")
check("B-01: Rust compile returns status ok") { rust1["status"] == "ok" }
check("B-02: Rust diagnostics empty") { Array(rust1["diagnostics"]).empty? }
check("B-03: Rust warnings empty") { Array(rust1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("B-#{format('%02d', idx + 4)}: Rust stage #{stage} ok") { (rust1["stages"] || {})[stage] == "ok" }
end
check("B-09: Rust result has 13 contracts") { Array(rust1["contracts"]).size == 13 }
check("B-10: Rust contract list matches expected") { Array(rust1["contracts"]).sort == EXPECTED_CONTRACTS }
check("B-11: Rust compile wrote fresh igapp one") { File.directory?(rust_out1) }
check("B-12: Rust second compile wrote fresh igapp two") { File.directory?(rust_out2) }
check("B-13: Rust compile stdout parsed as JSON") { !rust1.key?("_parse_error") }
check("B-14: Rust source hash is standard absolute proof-runner hash") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("B-15: Rust source hash stable across two runs") { rust2["source_hash"] == rust1["source_hash"] }

section("C -- Ruby compilation via CompilerOrchestrator")
check("C-01: Ruby wrapper status ok") { ruby1_raw["status"] == "ok" || ruby1["status"] == "ok" }
check("C-02: Ruby inner status ok") { ruby1["status"] == "ok" }
check("C-03: Ruby diagnostics empty") { Array(ruby1["diagnostics"]).empty? }
check("C-04: Ruby warnings empty") { Array(ruby1["warnings"]).empty? }
%w[parse classify typecheck emit assemble].each_with_index do |stage, idx|
  check("C-#{format('%02d', idx + 5)}: Ruby stage #{stage} ok") { (ruby1["stages"] || {})[stage] == "ok" }
end
check("C-10: Ruby result has 13 contracts") { Array(ruby1["contracts"]).size == 13 }
check("C-11: Ruby contract list matches expected") { Array(ruby1["contracts"]).sort == EXPECTED_CONTRACTS }
check("C-12: Ruby compile wrote fresh igapp one") { File.directory?(ruby_out1) }
check("C-13: Ruby second compile wrote fresh igapp two") { File.directory?(ruby_out2) }
check("C-14: Ruby compile stdout parsed as JSON") { !ruby1_raw.key?("_parse_error") }

section("D -- Hash, path discipline, and artifacts")
check("D-01: Ruby source_hash matches expected") { ruby1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-02: Rust source_hash matches expected") { rust1["source_hash"] == EXPECTED_SOURCE_HASH }
check("D-03: Ruby source_hash stable across two runs") { ruby2["source_hash"] == ruby1["source_hash"] }
check("D-04: Ruby and Rust source_hash agree") { ruby1["source_hash"] == rust1["source_hash"] }
check("D-05: source_hash is sha256-prefixed") { rust1["source_hash"].to_s.start_with?("sha256:") }
check("D-06: registry records live hash") { registry.include?(EXPECTED_SOURCE_HASH) }
check("D-07: card records live hash") { card.include?(EXPECTED_SOURCE_HASH) }
check("D-08: lab doc records live hash") { lab_doc.include?(EXPECTED_SOURCE_HASH) }
check("D-09: lab doc documents absolute Open3 path") { lab_doc.include?("absolute") && lab_doc.include?("Open3") }
check("D-10: runner source uses Open3") { File.read(__FILE__, encoding: "UTF-8").include?("Open3.capture3") }
check("D-11: runner source uses mktmpdir") { File.read(__FILE__, encoding: "UTF-8").include?("Dir.mktmpdir") }
check("D-12: manifest.json exists and parsed") { !$manifest.nil? }
check("D-13: semantic_ir_program.json exists and parsed") { !$sir.nil? }
check("D-14: sourcemap.json exists and parsed") { !$sourcemap.nil? }
check("D-15: compilation_report.json exists and parsed") { !$report.nil? }
check("D-16: diagnostics.json exists") { File.exist?(diagnostics_path) }

section("E -- Manifest and SemanticIR")
check("E-01: manifest source_hash matches result") { ($manifest || {})["source_hash"] == rust1["source_hash"] }
check("E-02: SIR source_hash matches result") { ($sir || {})["source_hash"] == rust1["source_hash"] }
check("E-03: report source_hash matches result") { ($report || {})["source_hash"] == rust1["source_hash"] }
check("E-04: manifest has semantic_ir_ref") { !($manifest || {})["semantic_ir_ref"].to_s.empty? }
check("E-05: manifest has sourcemap_ref") { !($manifest || {})["sourcemap_ref"].to_s.empty? }
check("E-06: manifest contract_index has 13 entries") { (($manifest || {})["contract_index"] || {}).size == 13 }
check("E-07: SIR kind is semantic_ir_program") { ($sir || {})["kind"] == "semantic_ir_program" }
check("E-08: manifest has 4 source units") { manifest_units.size == 4 }
check("E-09: SIR has 4 source units") { sir_units.size == 4 }
check("E-10: manifest source unit modules match expected") { manifest_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("E-11: SIR source unit modules match expected") { sir_units.map { |u| u["module"] }.sort == EXPECTED_SOURCE_UNITS }
check("E-12: manifest contract list matches expected") { manifest_contracts == EXPECTED_CONTRACTS }
check("E-13: SIR contract list matches expected") { sir_contracts == EXPECTED_CONTRACTS }
check("E-14: Ruby contract list matches Rust") { Array(ruby1["contracts"]).sort == Array(rust1["contracts"]).sort }
EXPECTED_SOURCE_UNITS.each_with_index do |mod, idx|
  check("E-#{format('%02d', idx + 15)}: source unit #{mod} present") { manifest_units.any? { |u| u["module"] == mod } }
end

section("F -- Source shape and metrics")
check("F-01: exactly 4 source files") { metrics[:files] == 4 }
check("F-02: exactly 4 type declarations") { metrics[:types] == 4 }
check("F-03: type list matches expected") { found_types == EXPECTED_TYPES }
EXPECTED_TYPES.each_with_index do |type, idx|
  check("F-#{format('%02d', idx + 4)}: type #{type} present") { found_types.include?(type) }
end
check("F-08: exactly 13 contracts") { metrics[:contracts] == 13 }
check("F-09: contract list matches expected") { found_contracts == EXPECTED_CONTRACTS }
EXPECTED_CONTRACTS.each_with_index do |contract, idx|
  check("F-#{format('%02d', idx + 10)}: contract #{contract} present") { found_contracts.include?(contract) }
end
check("F-23: exactly 10 pure contracts") { metrics[:pure_contracts] == 10 }
check("F-24: exactly 15 call_contract sites") { metrics[:call_contract] == 15 }
check("F-25: all call_contract sites are string literals") { metrics[:call_contract_literals].size == metrics[:call_contract] }
check("F-26: all call_contract targets are PascalCase") { metrics[:call_contract_literals].all? { |name| name.match?(/\A[A-Z]/) } }
check("F-27: exactly 1 fold site") { metrics[:fold] == 1 }
check("F-28: exactly 2 filter sites") { metrics[:filter] == 2 }
check("F-29: exactly 2 count sites") { metrics[:count] == 2 }
check("F-30: no map sites") { metrics[:map] == 0 }
check("F-31: no concat sites") { metrics[:concat] == 0 }
check("F-32: no variant declarations") { metrics[:variants] == 0 }
check("F-33: at least 5 typed record literal computes") { metrics[:record_literals] >= 5 }

section("G -- Entrypoint and temporal reconstruction")
check("G-01: source has bare entrypoint BalanceAsOfDay5") { read_source("example.ig").include?("entrypoint BalanceAsOfDay5") }
check("G-02: Rust manifest entrypoint resolves BalanceAsOfDay5") do
  manifest_entrypoint["resolved_contract"] == "BalanceAsOfDay5" && manifest_entrypoint["declared_target"] == "BalanceAsOfDay5"
end
check("G-03: Rust SIR entrypoint resolves BalanceAsOfDay5") do
  sir_entrypoint["resolved_contract"] == "BalanceAsOfDay5" && sir_entrypoint["target"] == "BalanceAsOfDay5"
end
check("G-04: BalanceAsOfDay3 scenario exists") { EXPECTED_CONTRACTS.include?("BalanceAsOfDay3") }
check("G-05: BalanceAsOfDay5 scenario exists") { EXPECTED_CONTRACTS.include?("BalanceAsOfDay5") }
check("G-06: report documents day 3 pre-correction balance") { app_report.include?("17000") && app_report.include?("before the correction") }
check("G-07: report documents day 5 post-correction balance") { app_report.include?("16000") && app_report.include?("after the correction") }
check("G-08: VisibleAsOf filters transaction_time") { read_source("ledger.ig").include?("e.transaction_time <= q.as_of_tt") }
check("G-09: VisibleAsOf filters valid_time") { read_source("ledger.ig").include?("e.valid_time <= q.as_of_vt") }
check("G-10: VisibleAsOf filters account") { read_source("ledger.ig").include?("e.account == q.account") }
check("G-11: SumVisible uses scalar fold over amount") { read_source("ledger.ig").include?("fold(visible, 0, (acc, e) -> acc + e.amount)") }
check("G-12: ReconstructBalance counts visible entries") { read_source("ledger.ig").include?("count(visible)") && read_source("ledger.ig").include?("entries_used") }
check("G-13: two explicit time axes are Integer") { read_source("types.ig").include?("valid_time      : Integer") && read_source("types.ig").include?("transaction_time: Integer") }
check("G-14: query carries as_of_tt and as_of_vt") { read_source("types.ig").include?("as_of_tt  : Integer") && read_source("types.ig").include?("as_of_vt  : Integer") }

section("H -- Append-only correction model")
check("H-01: CorrectionReceipt type exists") { read_source("types.ig").include?("type CorrectionReceipt") }
check("H-02: LedgerEntry has correction_of id") { read_source("types.ig").include?("correction_of   : Integer") }
check("H-03: correction_of comment defines 0 original") { read_source("types.ig").include?("0 = original entry") }
check("H-04: BuildCorrectionEntry computes delta") { read_source("correct.ig").include?("corrected_amount - original.amount") }
check("H-05: BuildCorrectionEntry preserves original valid_time") { read_source("correct.ig").include?("valid_time: original.valid_time") }
check("H-06: BuildCorrectionEntry injects recorded_at as transaction_time") { read_source("correct.ig").include?("transaction_time: recorded_at") }
check("H-07: BuildCorrectionEntry links correction_of original id") { read_source("correct.ig").include?("correction_of: original.id") }
check("H-08: BuildCorrectionReceipt records was and became") { read_source("correct.ig").include?("was_amount") && read_source("correct.ig").include?("became_amount") }
check("H-09: DemoLedger appends c1 into ledger collection") { read_source("example.ig").include?("compute ledger = [e1, e2, e3, c1]") }
check("H-10: report says correction never mutates original") { app_report.include?("never mutates") || registry.include?("never mutate") }
check("H-11: no update mutation syntax in app source") { !all_source.match?(/\b(update|mutate|delete|replace|upsert)\b/i) }
check("H-12: registry preserves append-only safety interpretation") { registry.include?("append-only") && registry.include?("adjusting delta") }

section("I -- Pressure registry AL-P01..AL-P09")
EXPECTED_PRESSURES.each_with_index do |pid, idx|
  check("I-#{format('%02d', idx + 1)}: registry preserves #{pid}") { registry.include?(pid) }
end
check("I-10: AL-P01 routes bitemporal reads to PROP-022/temporal state") { registry.include?("AL-P01") && registry.include?("PROP-022") && registry.include?("LANG-TEMPORAL-STATE") }
check("I-11: AL-P02 routes Decimal/Money gap") { registry.include?("AL-P02") && registry.include?("Decimal") && registry.include?("Money") }
check("I-12: AL-P03 routes fold-to-struct accumulator") { registry.include?("AL-P03") && registry.include?("LANG-FOLD-STRUCT-ACCUMULATOR") }
check("I-13: AL-P04 marks append-only correction positive") { registry.include?("AL-P04") && registry.include?("POSITIVE") }
check("I-14: AL-P05 routes clock behind boundary") { registry.include?("AL-P05") && registry.include?("no ambient clock") }
check("I-15: AL-P06 routes record literal factories") { registry.include?("AL-P06") && registry.include?("record-literal") }
check("I-16: AL-P07 routes correction trail provenance") { registry.include?("AL-P07") && registry.include?("History") }
check("I-17: AL-P08 keeps latest/supersession as future primitive") { registry.include?("AL-P08") && registry.include?("supersession") }
check("I-18: AL-P09 routes authority/provenance behind effect surface") { registry.include?("AL-P09") && registry.include?("effect-surface authority") }

section("J -- Governance/doc interpretation")
check("J-01: registry says pure-data core") { registry.include?("pure-data core") }
check("J-02: registry says evidence baseline only through card") { card.include?("evidence baseline only") }
check("J-03: lab doc classifies positive baseline") { lab_doc.include?("positive baseline") && lab_doc.include?("pressure source") }
check("J-04: lab doc states evidence only") { lab_doc.include?("evidence baseline only") }
check("J-05: lab doc records proof runner path") { lab_doc.include?("verify_lab_audit_ledger_baseline_p1.rb") }
check("J-06: lab doc records AL-P01..AL-P09") { EXPECTED_PRESSURES.all? { |pid| lab_doc.include?(pid) } }
check("J-07: temporal governance keeps pure temporal data separate from authority") { temporal_gov.include?("does not create new canon language semantics") }
check("J-08: temporal governance excludes clocks/storage") { temporal_gov.include?("clock capability") && temporal_gov.include?("storage") }
check("J-09: fold P1/P2/P3 checkpoints exist as route evidence") { [fold_p1_gov, fold_p2_gov, fold_p3_gov].all? { |doc| doc.include?("LANG-FOLD-STRUCT-ACCUMULATOR") } }
check("J-10: fixed-point cents documented as substitute, not Decimal") { lab_doc.include?("fixed-point Integer cents") && lab_doc.include?("not a Decimal implementation") }
check("J-11: registry closure summary exists") { registry.include?("Baseline Closure") && registry.include?("verify_lab_audit_ledger_baseline_p1.rb") }
check("J-12: card closure summary exists") { card.include?("Closure Summary") && card.include?("CLOSED") }

section("K -- Closed runtime and authority surfaces")
check("K-01: source has no capability declarations") { !code_source.match?(/^\s*capability\s+/) }
check("K-02: source has no effect declarations") { !code_source.match?(/^\s*effect\s+/) }
check("K-03: source has no observed/effect modifiers") { !code_source.match?(/^\s*(observed|effect|privileged|irreversible)\s+contract\s+/) }
check("K-04: source imports no IO stdlib") { !code_source.include?("stdlib.io") }
check("K-05: source has no DB/SQL/ORM/ActiveRecord code") { !code_source.match?(/\b(SQL|ORM|ActiveRecord|Database)\b/) }
check("K-06: source has no HTTP/Rack/socket server") { !code_source.match?(/\b(HTTP|Rack|Socket|server)\b/) }
check("K-07: code has no BiHistory runtime declaration") { !code_source.match?(/\b(type|contract)\s+BiHistory\b/) }
check("K-08: code has no as_of runtime call") { !code_source.match?(/\bas_of\s*\(/) }
check("K-09: code has no now()") { !code_source.include?("now()") }
check("K-10: code has no DateTime/Timestamp type") { !code_source.match?(/\b(DateTime|Timestamp)\b/) }
check("K-11: code has no Decimal type") { !code_source.match?(/\bDecimal\b/) }
check("K-12: code has no Money type") { !code_source.match?(/\bMoney\b/) }
check("K-13: code has no store/backend implementation") { !code_source.match?(/\b(store|backend|TBackend)\b/i) }
check("K-14: manifest fragment class is core") { ($manifest || {})["fragment_class"] == "core" }
check("K-15: manifest effects are empty") { Array(($manifest || {})["effects"]).empty? }
check("K-16: manifest capabilities are empty") { Array(($manifest || {})["capabilities"]).empty? }
check("K-17: SIR contracts have empty escape_boundaries") { (($sir || {})["contracts"] || []).all? { |c| Array(c["escape_boundaries"]).empty? } }

section("L -- Liveness and complexity")
liveness = rust1["liveness_instrumentation"] || {}
counters = liveness["counters"] || {}
check("L-01: liveness object present") { liveness["kind"] == "liveness_instrumentation" }
check("L-02: no liveness breaches") { Array(liveness["breaches"]).empty? }
check("L-03: tc_infer depth below 1000") { counters.fetch("typechecker.infer_expr.max_depth", 1001).to_i < 1000 }
check("L-04: fr_walk depth below 1000") { counters.fetch("form_resolver.walk_expr.max_depth", 1001).to_i < 1000 }
check("L-05: parser import steps below 100") { counters.fetch("parser.parse_import.max_steps", 101).to_i < 100 }
check("L-06: tc_infer depth reaches multifile work") { counters.fetch("typechecker.infer_expr.max_depth", 0).to_i >= 5 }
check("L-07: fr_walk depth reaches multifile work") { counters.fetch("form_resolver.walk_expr.max_depth", 0).to_i >= 5 }
check("L-08: compiler result has no runtime smoke") { rust1["runtime_smoke"].nil? }

section("M -- Closure artifacts")
check("M-01: card is closed proved") { card.include?("Status:** CLOSED") && card.include?("PROVED") }
check("M-02: registry has closure summary") { registry.include?("Baseline Closure") }
check("M-03: lab doc has proof result") { lab_doc.include?("197/197 PASS") }
check("M-04: portfolio index has audit ledger closure row") { portfolio.include?("LAB-AUDIT-LEDGER-BASELINE-P1 CLOSED") }
check("M-05: closure artifacts preserve no app source edits") { card.include?("No app source edits") && lab_doc.include?("No app source edits") }
check("M-06: runner does not use shell pipe or redirect markers") do
  runner = File.read(__FILE__, encoding: "UTF-8")
  pipe_to_head = ["|", "head"].join(" ")
  redirect_marker = ["2>", "&1"].join("")
  !runner.include?(pipe_to_head) && !runner.include?(redirect_marker)
end

puts
total = $pass_count + $fail_count
puts "=" * 72
puts "RESULT: #{$pass_count}/#{total} PASS  |  #{$fail_count} FAIL"
puts "=" * 72
exit($fail_count.zero? ? 0 : 1)
